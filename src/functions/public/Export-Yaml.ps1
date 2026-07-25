function Export-Yaml {
    <#
        .SYNOPSIS
        Exports PowerShell values to a YAML file.

        .DESCRIPTION
        Collects pipeline records with the same aggregation semantics as
        ConvertTo-Yaml, serializes the complete value before changing the
        filesystem, and writes strict encoded bytes through a cryptographically
        random same-directory temporary file.

        The completed temporary file is flushed and closed before it atomically
        replaces or moves to the destination. Existing files are never
        truncated before serialization and writing succeed.

        .PARAMETER InputObject
        A value to serialize. Multiple pipeline records become one YAML
        sequence. A directly supplied array is one input value.

        .PARAMETER Path
        One literal FileSystem destination path. Wildcard characters are not
        expanded.

        .PARAMETER Depth
        Maximum object-graph nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum number of traversed nodes. The default is 100000.

        .PARAMETER MaxScalarLength
        Maximum character count for one emitted scalar. The default is
        1048576.

        .PARAMETER Indent
        Block indentation from 2 through 9 spaces. The default is 2.

        .PARAMETER ExplicitDocumentStart
        Emits an explicit `---` document start marker.

        .PARAMETER EnumsAsStrings
        Emits enum names as strings instead of underlying numeric values.

        .PARAMETER Encoding
        Strict output encoding. utf8 omits a byte order mark; utf8BOM and the
        UTF-16 and UTF-32 encodings include their corresponding byte order mark.

        .PARAMETER NewLine
        Line ending used for emitted YAML structure. The default is LF.

        .PARAMETER NoFinalNewline
        Omits the final line ending. By default, exactly one is written.

        .PARAMETER NoClobber
        Fails when the destination already exists.

        .PARAMETER Force
        Permits atomic replacement of a read-only destination and preserves its
        read-only attribute. Force cannot be combined with NoClobber.

        .PARAMETER CreateDirectory
        Creates missing parent directories after ShouldProcess approval.

        .PARAMETER PassThru
        Writes the final FileInfo after a successful export.

        .EXAMPLE
        $config | Export-Yaml -Path '.\config.yaml'

        Serializes one pipeline value to config.yaml with UTF-8 and LF.

        .EXAMPLE
        'one', 'two' | Export-Yaml -Path '.\items.yaml' -Encoding utf16LE

        Collects two pipeline records into one sequence and writes UTF-16LE.

        .EXAMPLE
        Export-Yaml -InputObject $config -Path '.\new\config.yaml' -CreateDirectory -PassThru

        Creates the parent directory and returns the final FileInfo.

        .INPUTS
        System.Object

        .OUTPUTS
        System.IO.FileInfo

        .NOTES
        Only FileSystem provider destinations are supported.

        .LINK
        ConvertTo-Yaml
    #>
    [OutputType([System.IO.FileInfo])]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        # Collects one value per pipeline record.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object] $InputObject,

        # Selects one literal FileSystem destination.
        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        # Limits object-graph nesting depth.
        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        # Limits traversed serialization nodes.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        # Limits emitted characters in one scalar.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        # Selects block indentation width.
        [Parameter()]
        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        # Emits an explicit YAML document start marker.
        [Parameter()]
        [switch] $ExplicitDocumentStart,

        # Emits enum names instead of numeric values.
        [Parameter()]
        [switch] $EnumsAsStrings,

        # Selects strict output encoding and byte order mark policy.
        [Parameter()]
        [ValidateSet('utf8', 'utf8BOM', 'utf16LE', 'utf16BE', 'utf32LE', 'utf32BE')]
        [string] $Encoding = 'utf8',

        # Selects structural line endings.
        [Parameter()]
        [ValidateSet('LF', 'CRLF')]
        [string] $NewLine = 'LF',

        # Omits the one final structural line ending.
        [Parameter()]
        [switch] $NoFinalNewline,

        # Prevents replacement of an existing destination.
        [Parameter()]
        [switch] $NoClobber,

        # Permits replacement of a read-only destination.
        [Parameter()]
        [switch] $Force,

        # Creates missing parent directories after approval.
        [Parameter()]
        [switch] $CreateDirectory,

        # Emits the final FileInfo after success.
        [Parameter()]
        [switch] $PassThru
    )

    begin {
        $values = [System.Collections.Generic.List[object]]::new()
        $inspectionState = [pscustomobject]@{
            MaxScalarLength = $MaxScalarLength
            MaxNodes        = $MaxNodes
            NodeCount       = 0
        }
    }
    process {
        try {
            $null = Get-YamlSerializationShape -Value $InputObject -State $inspectionState `
                -EnumsAsStrings:$EnumsAsStrings -InspectOnly
            if ($values.Count -gt 0 -and ($values.Count + 2) -gt $MaxNodes) {
                throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                        "The object graph exceeds the configured limit of $MaxNodes nodes."
                    ))
            }
        } catch [System.NotSupportedException] {
            $serializationError = $_
            $exception = [System.InvalidOperationException]::new(
                "Cannot serialize YAML for '$Path': $($serializationError.Exception.Message)",
                $serializationError.Exception
            )
            $errorId = if ($serializationError.Exception.Data.Contains('YamlErrorId')) {
                [string] $serializationError.Exception.Data['YamlErrorId']
            } else {
                'YamlUnsupportedType'
            }
            $record = New-YamlErrorRecord -Exception $exception -DefaultErrorId $errorId `
                -Category InvalidType -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.InvalidOperationException] {
            $serializationError = $_
            $exception = [System.InvalidOperationException]::new(
                "Cannot serialize YAML for '$Path': $($serializationError.Exception.Message)",
                $serializationError.Exception
            )
            $errorId = if ($serializationError.Exception.Data.Contains('YamlErrorId')) {
                [string] $serializationError.Exception.Data['YamlErrorId']
            } else {
                'YamlExportSerializationFailed'
            }
            $record = New-YamlErrorRecord -Exception $exception -DefaultErrorId $errorId `
                -Category InvalidOperation -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        }
        $values.Add($InputObject)
    }
    end {
        if ($values.Count -eq 0) {
            return
        }
        if ($NoClobber -and $Force) {
            $exception = [System.ArgumentException]::new(
                "Cannot export YAML to '$Path': Force and NoClobber cannot be combined."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportConflictingFileOptions' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        }

        try {
            $provider = $null
            $drive = $null
            $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
                $Path,
                [ref] $provider,
                [ref] $drive
            )
            $destinationPath = [System.IO.Path]::GetFullPath($providerPath)
        } catch [System.Management.Automation.ProviderNotFoundException] {
            $pathError = $_
            $exception = [System.ArgumentException]::new(
                "Cannot export YAML to '$Path': the provider is not available.",
                $pathError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportProviderNotSupported' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.Management.Automation.DriveNotFoundException] {
            $pathError = $_
            $exception = [System.IO.DirectoryNotFoundException]::new(
                "Cannot export YAML to '$Path': the drive was not found.",
                $pathError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportDirectoryNotFound' -Category ObjectNotFound `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.ArgumentException] {
            $pathError = $_
            $exception = [System.ArgumentException]::new(
                "Cannot resolve YAML output path '$Path': $($pathError.Exception.Message)",
                $pathError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInvalid' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.NotSupportedException] {
            $pathError = $_
            $exception = [System.ArgumentException]::new(
                "Cannot resolve YAML output path '$Path': $($pathError.Exception.Message)",
                $pathError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInvalid' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.IO.PathTooLongException] {
            $pathError = $_
            $exception = [System.ArgumentException]::new(
                "Cannot resolve YAML output path '$Path': $($pathError.Exception.Message)",
                $pathError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInvalid' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        }

        if ($provider.Name -ne 'FileSystem') {
            $exception = [System.NotSupportedException]::new(
                "Cannot export YAML to '$Path': only the FileSystem provider is supported."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportProviderNotSupported' -Category InvalidArgument `
                -TargetObject $Path
            $PSCmdlet.ThrowTerminatingError($record)
        }
        $destinationExists = $false
        $destinationAttributes = [System.IO.FileAttributes]::Normal
        try {
            $destinationAttributes = [System.IO.File]::GetAttributes($destinationPath)
            $destinationExists = $true
        } catch [System.IO.FileNotFoundException] {
            $destinationExists = $false
        } catch [System.IO.DirectoryNotFoundException] {
            $destinationExists = $false
        } catch [System.UnauthorizedAccessException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML destination '$destinationPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.IO.IOException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML destination '$destinationPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInspectionFailed' -Category ReadError `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if ($destinationExists -and
            ($destinationAttributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            $exception = [System.IO.IOException]::new(
                "Cannot export YAML to '$destinationPath': the destination is a directory."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportNotFile' -Category InvalidType `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $directoryPath = [System.IO.Path]::GetDirectoryName($destinationPath)
        $directoryExists = $false
        $directoryAttributes = [System.IO.FileAttributes]::Normal
        try {
            $directoryAttributes = [System.IO.File]::GetAttributes($directoryPath)
            $directoryExists = $true
        } catch [System.IO.FileNotFoundException] {
            $directoryExists = $false
        } catch [System.IO.DirectoryNotFoundException] {
            $directoryExists = $false
        } catch [System.UnauthorizedAccessException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML output directory '$directoryPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.IO.IOException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML output directory '$directoryPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInspectionFailed' -Category ReadError `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if ($directoryExists -and
            ($directoryAttributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
            $exception = [System.IO.IOException]::new(
                "Cannot export YAML to '$destinationPath': the parent path is not a directory."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportDirectoryInvalid' -Category InvalidType `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if (-not $directoryExists -and -not $CreateDirectory) {
            $exception = [System.IO.DirectoryNotFoundException]::new(
                "Cannot export YAML to '$destinationPath': the parent directory does not exist."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportDirectoryNotFound' -Category ObjectNotFound `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        if ($destinationExists -and $NoClobber) {
            $exception = [System.IO.IOException]::new(
                "Cannot export YAML to '$destinationPath': the destination already exists."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportDestinationExists' -Category ResourceExists `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $destinationWasReadOnly = $false
        if ($destinationExists) {
            $destinationWasReadOnly = (
                $destinationAttributes -band [System.IO.FileAttributes]::ReadOnly
            ) -ne 0
            if ($destinationWasReadOnly -and -not $Force) {
                $exception = [System.UnauthorizedAccessException]::new(
                    "Cannot export YAML to '$destinationPath': the destination is read-only. Use Force to replace it."
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportDestinationReadOnly' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }

        $value = if ($values.Count -eq 1) {
            [object] $values[0]
        } else {
            [object[]] $values.ToArray()
        }
        $serializerParameters = @{
            InputObject           = $value
            Depth                 = $Depth
            MaxNodes              = $MaxNodes
            MaxScalarLength       = $MaxScalarLength
            Indent                = $Indent
            ExplicitDocumentStart = $ExplicitDocumentStart
            EnumsAsStrings        = $EnumsAsStrings
        }
        try {
            $yamlText = ConvertTo-Yaml @serializerParameters
        } catch {
            $serializationError = $_
            $errorId = ($serializationError.FullyQualifiedErrorId -split ',')[0]
            if ([string]::IsNullOrWhiteSpace($errorId) -or
                $errorId -notmatch '^[A-Za-z][A-Za-z0-9_.-]*$') {
                $errorId = 'YamlExportSerializationFailed'
            }
            $exception = [System.InvalidOperationException]::new(
                "Cannot serialize YAML for '$destinationPath': $($serializationError.Exception.Message)",
                $serializationError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception -DefaultErrorId $errorId `
                -Category $serializationError.CategoryInfo.Category -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        if ($yamlText.Contains("`r") -or -not $yamlText.EndsWith("`n")) {
            $exception = [System.InvalidOperationException]::new(
                "Cannot export YAML to '$destinationPath': the serializer did not return LF-normalized text with one final line feed."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPresentationFailed' -Category InvalidData `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $lineEnding = if ($NewLine -eq 'CRLF') {
            "`r`n"
        } else {
            "`n"
        }
        $presentationText = $yamlText.Substring(0, $yamlText.Length - 1).Replace(
            "`n",
            $lineEnding
        )
        if (-not $NoFinalNewline) {
            $presentationText += $lineEnding
        }

        $textEncoding = Get-YamlTextEncoding -Name $Encoding
        try {
            $contentBytes = $textEncoding.GetBytes($presentationText)
        } catch [System.Text.EncoderFallbackException] {
            $encodingError = $_
            $exception = [System.Text.EncoderFallbackException]::new(
                "Cannot encode YAML for '$destinationPath': the text contains an invalid character sequence.",
                $encodingError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportEncodingFailed' -Category InvalidData `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
        $preamble = $textEncoding.GetPreamble()
        $outputBytes = [byte[]]::new($preamble.Length + $contentBytes.Length)
        [System.Buffer]::BlockCopy($preamble, 0, $outputBytes, 0, $preamble.Length)
        [System.Buffer]::BlockCopy(
            $contentBytes,
            0,
            $outputBytes,
            $preamble.Length,
            $contentBytes.Length
        )

        $approvedDestinationExists = $destinationExists
        $action = if ($destinationExists) {
            'Replace YAML file'
        } else {
            'Create YAML file'
        }
        if (-not $PSCmdlet.ShouldProcess($destinationPath, $action)) {
            return
        }

        if (-not $directoryExists) {
            try {
                [void] [System.IO.Directory]::CreateDirectory($directoryPath)
            } catch [System.UnauthorizedAccessException] {
                $directoryError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot create YAML output directory '$directoryPath': $($directoryError.Exception.Message)",
                    $directoryError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportDirectoryCreateFailed' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.IO.IOException] {
                $directoryError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot create YAML output directory '$directoryPath': $($directoryError.Exception.Message)",
                    $directoryError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportDirectoryCreateFailed' -Category WriteError `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }

        $destinationExists = $false
        $destinationAttributes = [System.IO.FileAttributes]::Normal
        try {
            $destinationAttributes = [System.IO.File]::GetAttributes($destinationPath)
            $destinationExists = $true
        } catch [System.IO.FileNotFoundException] {
            $destinationExists = $false
        } catch [System.IO.DirectoryNotFoundException] {
            $destinationExists = $false
        } catch [System.UnauthorizedAccessException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML destination '$destinationPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.IO.IOException] {
            $inspectionError = $_
            $exception = [System.IO.IOException]::new(
                "Cannot inspect YAML destination '$destinationPath': $($inspectionError.Exception.Message)",
                $inspectionError.Exception
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportPathInspectionFailed' -Category ReadError `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        if ($destinationExists -and
            ($destinationAttributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            $exception = [System.IO.IOException]::new(
                "Cannot export YAML to '$destinationPath': the destination is a directory."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportNotFile' -Category InvalidType `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if (-not $approvedDestinationExists -and $destinationExists -and
            -not $PSCmdlet.ShouldProcess($destinationPath, 'Replace YAML file')) {
            return
        }
        if ($destinationExists -and $NoClobber) {
            $exception = [System.IO.IOException]::new(
                "Cannot export YAML to '$destinationPath': the destination already exists."
            )
            $record = New-YamlErrorRecord -Exception $exception `
                -DefaultErrorId 'YamlExportDestinationExists' -Category ResourceExists `
                -TargetObject $destinationPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $destinationWasReadOnly = $false
        $destinationUnixMode = $null
        if ($destinationExists) {
            try {
                if (-not $IsWindows) {
                    $destinationUnixMode = [System.IO.File]::GetUnixFileMode($destinationPath)
                }
            } catch [System.Security.SecurityException] {
                $metadataError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot read security metadata for YAML destination '$destinationPath': $($metadataError.Exception.Message)",
                    $metadataError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.UnauthorizedAccessException] {
                $metadataError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot read security metadata for YAML destination '$destinationPath': $($metadataError.Exception.Message)",
                    $metadataError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.IO.IOException] {
                $metadataError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot read security metadata for YAML destination '$destinationPath': $($metadataError.Exception.Message)",
                    $metadataError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportMetadataReadFailed' -Category ReadError `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }

            $destinationWasReadOnly = (
                $destinationAttributes -band [System.IO.FileAttributes]::ReadOnly
            ) -ne 0
            if ($destinationWasReadOnly -and -not $Force) {
                $exception = [System.UnauthorizedAccessException]::new(
                    "Cannot export YAML to '$destinationPath': the destination is read-only. Use Force to replace it."
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportDestinationReadOnly' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }

        $temporaryPath = $null
        $backupPath = $null
        $backupFileHandle = $null
        $replacementAttempted = $false
        $replacementCompleted = $false
        $replacementOriginalAtBackup = $false
        $nativeReplacementCompleted = $false
        $attributesCleared = $false
        $backupCleanupError = $null
        $temporaryCleanupError = $null
        try {
            $randomName = [System.Convert]::ToHexString(
                [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
            ).ToLowerInvariant()
            $temporaryPath = [System.IO.Path]::Combine(
                $directoryPath,
                ".yaml-$randomName.tmp"
            )

            try {
                $streamOptions = [System.IO.FileStreamOptions]::new()
                $streamOptions.Mode = [System.IO.FileMode]::CreateNew
                $streamOptions.Access = [System.IO.FileAccess]::Write
                $streamOptions.Share = [System.IO.FileShare]::None
                $streamOptions.BufferSize = 4096
                $streamOptions.Options = [System.IO.FileOptions]::WriteThrough
                if (-not $IsWindows) {
                    $streamOptions.UnixCreateMode = (
                        [System.IO.UnixFileMode]::UserRead -bor
                        [System.IO.UnixFileMode]::UserWrite
                    )
                }

                $stream = [System.IO.FileStream]::new($temporaryPath, $streamOptions)
                try {
                    $stream.Write($outputBytes, 0, $outputBytes.Length)
                    $stream.Flush($true)
                    if ($destinationExists -and -not $IsWindows) {
                        [System.IO.File]::SetUnixFileMode(
                            $stream.SafeFileHandle,
                            $destinationUnixMode
                        )
                        $stream.Flush($true)
                    }
                } finally {
                    if ($null -ne $stream) {
                        $stream.Dispose()
                    }
                }
            } catch [System.Security.SecurityException] {
                $writeError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot secure YAML temporary file for '$destinationPath': $($writeError.Exception.Message)",
                    $writeError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.UnauthorizedAccessException] {
                $writeError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot write YAML temporary file for '$destinationPath': $($writeError.Exception.Message)",
                    $writeError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportWriteFailed' -Category WriteError `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.IO.IOException] {
                $writeError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot write YAML temporary file for '$destinationPath': $($writeError.Exception.Message)",
                    $writeError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception `
                    -DefaultErrorId 'YamlExportWriteFailed' -Category WriteError `
                    -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }

            if ($destinationWasReadOnly -and $IsWindows) {
                $prepareError = $null
                try {
                    [System.IO.File]::SetAttributes(
                        $destinationPath,
                        $destinationAttributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                    )
                    $attributesCleared = $true
                } catch [System.UnauthorizedAccessException] {
                    $prepareError = $_
                } catch [System.IO.IOException] {
                    $prepareError = $_
                }
                if ($null -ne $prepareError) {
                    if ($attributesCleared) {
                        try {
                            [System.IO.File]::SetAttributes(
                                $destinationPath,
                                $destinationAttributes
                            )
                        } catch [System.UnauthorizedAccessException] {
                            $restoreError = $_
                            $exception = [System.IO.IOException]::new(
                                "Cannot restore read-only YAML destination '$destinationPath': $($restoreError.Exception.Message)",
                                $restoreError.Exception
                            )
                            $record = New-YamlErrorRecord -Exception $exception `
                                -DefaultErrorId 'YamlExportReadOnlyRestoreFailed' `
                                -Category PermissionDenied -TargetObject $destinationPath
                            $PSCmdlet.ThrowTerminatingError($record)
                        } catch [System.IO.IOException] {
                            $restoreError = $_
                            $exception = [System.IO.IOException]::new(
                                "Cannot restore read-only YAML destination '$destinationPath': $($restoreError.Exception.Message)",
                                $restoreError.Exception
                            )
                            $record = New-YamlErrorRecord -Exception $exception `
                                -DefaultErrorId 'YamlExportReadOnlyRestoreFailed' `
                                -Category WriteError -TargetObject $destinationPath
                            $PSCmdlet.ThrowTerminatingError($record)
                        }
                    }
                    $exception = [System.IO.IOException]::new(
                        "Cannot prepare read-only YAML destination '$destinationPath' for replacement: $($prepareError.Exception.Message)",
                        $prepareError.Exception
                    )
                    $record = New-YamlErrorRecord -Exception $exception `
                        -DefaultErrorId 'YamlExportPermissionDenied' -Category PermissionDenied `
                        -TargetObject $destinationPath
                    $PSCmdlet.ThrowTerminatingError($record)
                }
            }

            $moveError = $null
            $moveErrorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified
            try {
                if ($destinationExists -and $IsWindows) {
                    $backupRandomName = [System.Convert]::ToHexString(
                        [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
                    ).ToLowerInvariant()
                    $backupPath = [System.IO.Path]::Combine(
                        $directoryPath,
                        ".yaml-$backupRandomName.old"
                    )
                    $replacementAttempted = $true
                    [System.IO.File]::Replace(
                        $temporaryPath,
                        $destinationPath,
                        $backupPath,
                        $false
                    )
                    $nativeReplacementCompleted = $true
                    $temporaryPath = $null
                    if ($destinationWasReadOnly) {
                        [System.IO.File]::SetAttributes(
                            $destinationPath,
                            $destinationAttributes
                        )
                    }
                    $replacementCompleted = $true
                } elseif ($NoClobber -and -not $IsWindows) {
                    $escapedDirectoryPath = (
                        [System.Management.Automation.WildcardPattern]::Escape($directoryPath)
                    )
                    $null = New-Item -Path $escapedDirectoryPath `
                        -Name ([System.IO.Path]::GetFileName($destinationPath)) `
                        -ItemType HardLink -Value $temporaryPath -Confirm:$false `
                        -ErrorAction Stop
                    try {
                        [System.IO.File]::Delete($temporaryPath)
                        $temporaryPath = $null
                    } catch [System.UnauthorizedAccessException] {
                        $temporaryCleanupError = $_
                    } catch [System.IO.IOException] {
                        $temporaryCleanupError = $_
                    }
                } else {
                    [System.IO.File]::Move(
                        $temporaryPath,
                        $destinationPath,
                        -not $NoClobber
                    )
                }
                $temporaryPath = $null
            } catch [System.UnauthorizedAccessException] {
                $moveError = $_
                $moveErrorCategory = [System.Management.Automation.ErrorCategory]::PermissionDenied
                $replacementOriginalAtBackup = $nativeReplacementCompleted
            } catch [System.IO.IOException] {
                $moveError = $_
                $moveErrorCategory = [System.Management.Automation.ErrorCategory]::WriteError
                $nativeErrorCode = $moveError.Exception.HResult -band 0xFFFF
                if ($null -ne $moveError.Exception.InnerException) {
                    $innerErrorCode = (
                        $moveError.Exception.InnerException.HResult -band 0xFFFF
                    )
                    if ($innerErrorCode -ge 1175 -and $innerErrorCode -le 1177) {
                        $nativeErrorCode = $innerErrorCode
                    }
                }
                $replacementOriginalAtBackup = (
                    $nativeReplacementCompleted -or $nativeErrorCode -eq 1177
                )
                if ($nativeErrorCode -in 5, 32, 33) {
                    $moveErrorCategory = (
                        [System.Management.Automation.ErrorCategory]::PermissionDenied
                    )
                }
            } catch {
                $moveError = $_
                $moveErrorCategory = $moveError.CategoryInfo.Category
            }

            if ($replacementCompleted -and $null -ne $backupPath) {
                try {
                    if ($destinationWasReadOnly) {
                        $backupFileHandle = [System.IO.File]::OpenHandle(
                            $backupPath,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::Write,
                            (
                                [System.IO.FileShare]::ReadWrite -bor
                                [System.IO.FileShare]::Delete
                            ),
                            [System.IO.FileOptions]::None
                        )
                        [System.IO.File]::Delete($backupPath)
                        [System.IO.File]::SetAttributes(
                            $backupFileHandle,
                            $destinationAttributes
                        )
                        $backupFileHandle.Dispose()
                        $backupFileHandle = $null
                    } else {
                        [System.IO.File]::Delete($backupPath)
                    }
                    $backupPath = $null
                } catch [System.UnauthorizedAccessException] {
                    $backupCleanupError = $_
                } catch [System.IO.IOException] {
                    $backupCleanupError = $_
                } finally {
                    if ($null -ne $backupFileHandle) {
                        $backupFileHandle.Dispose()
                        $backupFileHandle = $null
                    }
                }
            }
            if ($null -ne $moveError) {
                $destinationCreatedDuringExport = $false
                if ($NoClobber) {
                    try {
                        $null = [System.IO.File]::GetAttributes($destinationPath)
                        $destinationCreatedDuringExport = $true
                    } catch [System.IO.FileNotFoundException] {
                        $destinationCreatedDuringExport = $false
                    } catch [System.IO.DirectoryNotFoundException] {
                        $destinationCreatedDuringExport = $false
                    } catch [System.UnauthorizedAccessException] {
                        $destinationCreatedDuringExport = $false
                    } catch [System.IO.IOException] {
                        $destinationCreatedDuringExport = $false
                    }
                }
                $errorId = if ($NoClobber -and (
                        $destinationCreatedDuringExport -or $moveErrorCategory -eq (
                            [System.Management.Automation.ErrorCategory]::ResourceExists
                        )
                    )) {
                    $moveErrorCategory = [System.Management.Automation.ErrorCategory]::ResourceExists
                    'YamlExportDestinationExists'
                } else {
                    'YamlExportReplaceFailed'
                }
                $exception = [System.IO.IOException]::new(
                    "Cannot replace YAML destination '$destinationPath': $($moveError.Exception.Message)",
                    $moveError.Exception
                )
                $record = New-YamlErrorRecord -Exception $exception -DefaultErrorId $errorId `
                    -Category $moveErrorCategory -TargetObject $destinationPath
                $PSCmdlet.ThrowTerminatingError($record)
            }
        } finally {
            if ($null -ne $backupFileHandle) {
                $backupFileHandle.Dispose()
            }
            if ($null -ne $backupPath) {
                if ($replacementCompleted) {
                    try {
                        if ($destinationWasReadOnly) {
                            $backupFileHandle = [System.IO.File]::OpenHandle(
                                $backupPath,
                                [System.IO.FileMode]::Open,
                                [System.IO.FileAccess]::Write,
                                (
                                    [System.IO.FileShare]::ReadWrite -bor
                                    [System.IO.FileShare]::Delete
                                ),
                                [System.IO.FileOptions]::None
                            )
                            [System.IO.File]::Delete($backupPath)
                            [System.IO.File]::SetAttributes(
                                $backupFileHandle,
                                $destinationAttributes
                            )
                        } else {
                            [System.IO.File]::Delete($backupPath)
                        }
                        $backupPath = $null
                    } catch [System.IO.FileNotFoundException] {
                        $backupPath = $null
                    } catch [System.IO.DirectoryNotFoundException] {
                        $backupPath = $null
                    } catch [System.UnauthorizedAccessException] {
                        $cleanupError = $_
                        $cleanupHistory = if ($null -ne $backupCleanupError) {
                            " A previous cleanup attempt failed: $($backupCleanupError.Exception.Message)"
                        } else {
                            ''
                        }
                        $exception = [System.IO.IOException]::new(
                            "Cannot clean YAML replacement backup '$backupPath': $($cleanupError.Exception.Message)$cleanupHistory",
                            $cleanupError.Exception
                        )
                        $record = New-YamlErrorRecord -Exception $exception `
                            -DefaultErrorId 'YamlExportTempCleanupFailed' `
                            -Category PermissionDenied -TargetObject $backupPath
                        $PSCmdlet.ThrowTerminatingError($record)
                    } catch [System.IO.IOException] {
                        $cleanupError = $_
                        $cleanupHistory = if ($null -ne $backupCleanupError) {
                            " A previous cleanup attempt failed: $($backupCleanupError.Exception.Message)"
                        } else {
                            ''
                        }
                        $exception = [System.IO.IOException]::new(
                            "Cannot clean YAML replacement backup '$backupPath': $($cleanupError.Exception.Message)$cleanupHistory",
                            $cleanupError.Exception
                        )
                        $record = New-YamlErrorRecord -Exception $exception `
                            -DefaultErrorId 'YamlExportTempCleanupFailed' `
                            -Category WriteError -TargetObject $backupPath
                        $PSCmdlet.ThrowTerminatingError($record)
                    } finally {
                        if ($null -ne $backupFileHandle) {
                            $backupFileHandle.Dispose()
                            $backupFileHandle = $null
                        }
                    }
                } elseif ($replacementAttempted) {
                    $backupAvailable = $false
                    $destinationAvailable = $false
                    $recoveryCause = $null
                    $recoveryCategory = [System.Management.Automation.ErrorCategory]::WriteError
                    try {
                        $null = [System.IO.File]::GetAttributes($backupPath)
                        $backupAvailable = $true
                    } catch [System.IO.FileNotFoundException] {
                        $backupAvailable = $false
                    } catch [System.IO.DirectoryNotFoundException] {
                        $backupAvailable = $false
                    } catch [System.UnauthorizedAccessException] {
                        $recoveryCause = $_.Exception
                        $recoveryCategory = (
                            [System.Management.Automation.ErrorCategory]::PermissionDenied
                        )
                    } catch [System.IO.IOException] {
                        $recoveryCause = $_.Exception
                    }

                    if ($null -eq $recoveryCause) {
                        try {
                            $currentDestinationAttributes = (
                                [System.IO.File]::GetAttributes($destinationPath)
                            )
                            $destinationAvailable = $true
                        } catch [System.IO.FileNotFoundException] {
                            $destinationAvailable = $false
                        } catch [System.IO.DirectoryNotFoundException] {
                            $destinationAvailable = $false
                        } catch [System.UnauthorizedAccessException] {
                            $recoveryCause = $_.Exception
                            $recoveryCategory = (
                                [System.Management.Automation.ErrorCategory]::PermissionDenied
                            )
                        } catch [System.IO.IOException] {
                            $recoveryCause = $_.Exception
                        }
                    }

                    if ($null -eq $recoveryCause -and
                        $replacementOriginalAtBackup -and $backupAvailable) {
                        try {
                            [System.IO.File]::SetAttributes(
                                $backupPath,
                                $destinationAttributes
                            )
                            if ($destinationAvailable) {
                                $destinationIsReadOnly = (
                                    $currentDestinationAttributes -band
                                    [System.IO.FileAttributes]::ReadOnly
                                ) -ne 0
                                if ($destinationIsReadOnly) {
                                    [System.IO.File]::SetAttributes(
                                        $destinationPath,
                                        $currentDestinationAttributes -band (
                                            -bnot [System.IO.FileAttributes]::ReadOnly
                                        )
                                    )
                                }
                            }
                            [System.IO.File]::Move(
                                $backupPath,
                                $destinationPath,
                                $true
                            )
                            $backupPath = $null
                        } catch [System.UnauthorizedAccessException] {
                            $recoveryCause = $_.Exception
                            $recoveryCategory = (
                                [System.Management.Automation.ErrorCategory]::PermissionDenied
                            )
                        } catch [System.IO.IOException] {
                            $recoveryCause = $_.Exception
                        }
                    } elseif ($null -eq $recoveryCause -and
                        $replacementOriginalAtBackup) {
                        $recoveryCause = [System.IO.FileNotFoundException]::new(
                            "The replacement backup containing the original YAML file was not found."
                        )
                    } elseif ($null -eq $recoveryCause -and $destinationAvailable) {
                        if ($attributesCleared) {
                            try {
                                [System.IO.File]::SetAttributes(
                                    $destinationPath,
                                    $destinationAttributes
                                )
                            } catch [System.UnauthorizedAccessException] {
                                $recoveryCause = $_.Exception
                                $recoveryCategory = (
                                    [System.Management.Automation.ErrorCategory]::PermissionDenied
                                )
                            } catch [System.IO.IOException] {
                                $recoveryCause = $_.Exception
                            }
                        }
                        if ($null -eq $recoveryCause) {
                            $backupPath = $null
                        }
                    } elseif ($null -eq $recoveryCause) {
                        $recoveryCause = [System.IO.FileNotFoundException]::new(
                            "Neither the YAML destination nor its replacement backup could be found."
                        )
                    }

                    if ($null -ne $recoveryCause) {
                        $recoveryMessage = (
                            "Cannot recover YAML destination '$destinationPath' after replacement failed. " +
                            "The original is retained at '$backupPath' when that path exists."
                        )
                        $exception = [System.IO.IOException]::new(
                            $recoveryMessage,
                            $recoveryCause
                        )
                        $record = New-YamlErrorRecord -Exception $exception `
                            -DefaultErrorId 'YamlExportRecoveryFailed' `
                            -Category $recoveryCategory -TargetObject $destinationPath
                        $PSCmdlet.ThrowTerminatingError($record)
                    }
                }
            }
            if ($null -ne $temporaryPath) {
                $temporaryMissing = $false
                try {
                    $temporaryAttributes = [System.IO.File]::GetAttributes($temporaryPath)
                    if (($temporaryAttributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                        [System.IO.File]::SetAttributes(
                            $temporaryPath,
                            $temporaryAttributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                        )
                    }
                    [System.IO.File]::Delete($temporaryPath)
                } catch [System.IO.FileNotFoundException] {
                    $temporaryMissing = $true
                } catch [System.IO.DirectoryNotFoundException] {
                    $temporaryMissing = $true
                } catch [System.UnauthorizedAccessException] {
                    $cleanupError = $_
                    $cleanupHistory = if ($null -ne $temporaryCleanupError) {
                        " A previous cleanup attempt failed: $($temporaryCleanupError.Exception.Message)"
                    } else {
                        ''
                    }
                    $exception = [System.IO.IOException]::new(
                        "Cannot clean YAML temporary file '$temporaryPath': $($cleanupError.Exception.Message)$cleanupHistory",
                        $cleanupError.Exception
                    )
                    $record = New-YamlErrorRecord -Exception $exception `
                        -DefaultErrorId 'YamlExportTempCleanupFailed' -Category PermissionDenied `
                        -TargetObject $temporaryPath
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.IO.IOException] {
                    $cleanupError = $_
                    $cleanupHistory = if ($null -ne $temporaryCleanupError) {
                        " A previous cleanup attempt failed: $($temporaryCleanupError.Exception.Message)"
                    } else {
                        ''
                    }
                    $exception = [System.IO.IOException]::new(
                        "Cannot clean YAML temporary file '$temporaryPath': $($cleanupError.Exception.Message)$cleanupHistory",
                        $cleanupError.Exception
                    )
                    $record = New-YamlErrorRecord -Exception $exception `
                        -DefaultErrorId 'YamlExportTempCleanupFailed' -Category WriteError `
                        -TargetObject $temporaryPath
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                if ($temporaryMissing) {
                    $temporaryPath = $null
                }
            }
        }

        if ($PassThru) {
            $fileInfo = [System.IO.FileInfo]::new($destinationPath)
            $fileInfo.Refresh()
            $PSCmdlet.WriteObject($fileInfo, $false)
        }
    }
}
