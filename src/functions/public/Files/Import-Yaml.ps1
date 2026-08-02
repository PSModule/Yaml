function Import-Yaml {
    <#
        .SYNOPSIS
        Imports YAML documents from files.

        .DESCRIPTION
        Resolves FileSystem files deterministically, decodes each file with a
        strict Unicode encoding, and delegates YAML parsing to ConvertFrom-Yaml.
        Wildcards are expanded only for Path. Duplicate resolved files are read
        once, and each file's documents retain their source order.

        Byte order marks for UTF-8, UTF-16, and UTF-32 are detected
        automatically and override Encoding. Files without a byte order mark
        default to strict UTF-8.

        .EXAMPLE
        Import-Yaml -Path '.\config.yaml'

        Imports the YAML documents from config.yaml.

        .EXAMPLE
        Get-ChildItem -Path '.\config' -Filter '*.yaml' | Import-Yaml -AsHashtable

        Imports FileInfo pipeline input and returns mappings as dictionaries.

        .EXAMPLE
        Import-Yaml -LiteralPath '.\config[production].data' -NoEnumerate

        Imports a literal wildcard-bearing filename and preserves root arrays.

        .INPUTS
        System.String

        A FileSystem path to a YAML file, piped in.

        .INPUTS
        System.IO.FileInfo

        A file whose path is resolved from its FullName property, piped in.

        .OUTPUTS
        System.Object

        The PowerShell value constructed from each imported YAML document.

        .NOTES
        Only FileSystem provider paths are supported.

        .LINK
        https://psmodule.io/Yaml/Functions/Import-Yaml/
    #>
    [OutputType([object])]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        # Expands wildcard paths and accepts string pipeline values.
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ParameterSetName = 'Path'
        )]
        [string[]] $Path,

        # Resolves exact paths from LiteralPath, PSPath, or FullName properties.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'LiteralPath'
        )]
        [Alias('PSPath', 'FullName')]
        [string[]] $LiteralPath,

        # Selects the fallback decoder when a file has no byte order mark.
        [Parameter()]
        [ValidateSet('utf8', 'utf8BOM', 'utf16LE', 'utf16BE', 'utf32LE', 'utf32BE')]
        [string] $Encoding = 'utf8',

        # Preserves YAML mappings as insertion-ordered dictionaries.
        [Parameter()]
        [switch] $AsHashtable,

        # Preserves each root YAML sequence as one output record.
        [Parameter()]
        [switch] $NoEnumerate,

        # Limits YAML node nesting depth.
        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        # Limits the number of YAML nodes in each file.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        # Limits alias nodes in each file.
        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases = 1000,

        # Limits decoded characters in one scalar.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        # Limits expanded characters in one tag.
        [Parameter()]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength = 1024,

        # Limits cumulative expanded tag characters.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength = 65536,

        # Limits digits in numeric scalars.
        [Parameter()]
        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength = 4096
    )

    begin {
        $resolvedPaths = [System.Collections.Generic.List[string]]::new()
    }
    process {
        $currentPaths = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
            $LiteralPath
        } else {
            $Path
        }
        foreach ($requestedPath in $currentPaths) {
            if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
                try {
                    $provider = $null
                    $drive = $null
                    $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
                        $requestedPath,
                        [ref] $provider,
                        [ref] $drive
                    )
                } catch [System.Management.Automation.ProviderNotFoundException] {
                    $pathError = $_
                    $exception = [System.ArgumentException]::new(
                        "Cannot import YAML from '$requestedPath': the provider is not available.",
                        $pathError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportProviderNotSupported',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.Management.Automation.DriveNotFoundException] {
                    $pathError = $_
                    $exception = [System.IO.FileNotFoundException]::new(
                        "Cannot import YAML from '$requestedPath': the path was not found.",
                        $pathError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch {
                    $pathError = $_
                    $exception = [System.ArgumentException]::new(
                        "Cannot resolve YAML input path '$requestedPath': $($pathError.Exception.Message)",
                        $pathError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathResolutionFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }

                if ($provider.Name -ne 'FileSystem') {
                    $exception = [System.NotSupportedException]::new(
                        "Cannot import YAML from '$requestedPath': only the FileSystem provider is supported."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportProviderNotSupported',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                try {
                    $pathAttributes = [System.IO.File]::GetAttributes($providerPath)
                } catch [System.IO.FileNotFoundException] {
                    $exception = [System.IO.FileNotFoundException]::new(
                        "Cannot import YAML from '$requestedPath': the path was not found."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.IO.DirectoryNotFoundException] {
                    $exception = [System.IO.FileNotFoundException]::new(
                        "Cannot import YAML from '$requestedPath': the path was not found."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.UnauthorizedAccessException] {
                    $inspectionError = $_
                    $exception = [System.IO.IOException]::new(
                        "Cannot inspect YAML input path '$requestedPath': $($inspectionError.Exception.Message)",
                        $inspectionError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPermissionDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.IO.IOException] {
                    $inspectionError = $_
                    $exception = [System.IO.IOException]::new(
                        "Cannot inspect YAML input path '$requestedPath': $($inspectionError.Exception.Message)",
                        $inspectionError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathInspectionFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                if (($pathAttributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $exception = [System.IO.IOException]::new(
                        "Cannot import YAML from '$requestedPath': the path is not a file."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportNotFile',
                        [System.Management.Automation.ErrorCategory]::InvalidType,
                        $requestedPath
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                $resolvedPaths.Add([System.IO.Path]::GetFullPath($providerPath))
                continue
            }

            try {
                $pathInfos = $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath(
                    $requestedPath
                )
            } catch [System.Management.Automation.ItemNotFoundException] {
                $pathError = $_
                $exception = [System.IO.FileNotFoundException]::new(
                    "Cannot import YAML from '$requestedPath': the path was not found.",
                    $pathError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportPathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $requestedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.Management.Automation.ProviderNotFoundException] {
                $pathError = $_
                $exception = [System.ArgumentException]::new(
                    "Cannot import YAML from '$requestedPath': the provider is not available.",
                    $pathError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportProviderNotSupported',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $requestedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.Management.Automation.DriveNotFoundException] {
                $pathError = $_
                $exception = [System.IO.FileNotFoundException]::new(
                    "Cannot import YAML from '$requestedPath': the path was not found.",
                    $pathError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportPathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $requestedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            } catch {
                $pathError = $_
                $exception = [System.ArgumentException]::new(
                    "Cannot resolve YAML input path '$requestedPath': $($pathError.Exception.Message)",
                    $pathError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportPathResolutionFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $requestedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            }
            if ($pathInfos.Count -eq 0) {
                $exception = [System.IO.FileNotFoundException]::new(
                    "Cannot import YAML from '$requestedPath': the path was not found."
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportPathNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $requestedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            }

            foreach ($pathInfo in $pathInfos) {
                if ($pathInfo.Provider.Name -ne 'FileSystem') {
                    $exception = [System.NotSupportedException]::new(
                        "Cannot import YAML from '$($pathInfo.Path)': only the FileSystem provider is supported."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportProviderNotSupported',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $pathInfo.Path
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                try {
                    $pathAttributes = [System.IO.File]::GetAttributes($pathInfo.ProviderPath)
                } catch [System.UnauthorizedAccessException] {
                    $inspectionError = $_
                    $exception = [System.IO.IOException]::new(
                        "Cannot inspect YAML input path '$($pathInfo.Path)': $($inspectionError.Exception.Message)",
                        $inspectionError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPermissionDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $pathInfo.Path
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                } catch [System.IO.IOException] {
                    $inspectionError = $_
                    $exception = [System.IO.IOException]::new(
                        "Cannot inspect YAML input path '$($pathInfo.Path)': $($inspectionError.Exception.Message)",
                        $inspectionError.Exception
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportPathInspectionFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $pathInfo.Path
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                if (($pathAttributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $exception = [System.IO.IOException]::new(
                        "Cannot import YAML from '$($pathInfo.Path)': the path is not a file."
                    )
                    $record = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'YamlImportNotFile',
                        [System.Management.Automation.ErrorCategory]::InvalidType,
                        $pathInfo.Path
                    )
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                $resolvedPaths.Add([System.IO.Path]::GetFullPath($pathInfo.ProviderPath))
            }
        }
    }
    end {

        $pathsByIdentity = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal
        )
        $directoryNameGroups = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($resolvedPath in $resolvedPaths) {
            $identityComponents = [System.Collections.Generic.List[string]]::new()
            $identityPath = $resolvedPath
            $identityFailed = $false

            while ($true) {
                $directoryPath = [System.IO.Path]::GetDirectoryName($identityPath)
                $leafName = [System.IO.Path]::GetFileName($identityPath)
                if ([string]::IsNullOrEmpty($directoryPath) -or
                    [string]::IsNullOrEmpty($leafName)) {
                    break
                }

                $nameGroups = $null
                try {
                    if (-not $directoryNameGroups.TryGetValue(
                            $directoryPath,
                            [ref]$nameGroups
                        )) {
                        $nameGroups = (
                            [System.Collections.Generic.Dictionary[string, object]]::new(
                                [System.StringComparer]::OrdinalIgnoreCase
                            )
                        )
                        foreach ($directoryEntry in (
                                [System.IO.Directory]::EnumerateFileSystemEntries($directoryPath)
                            )) {
                            $entryName = [System.IO.Path]::GetFileName($directoryEntry)
                            $entryIdentityName = $entryName.Normalize(
                                [System.Text.NormalizationForm]::FormC
                            )
                            $nameGroup = $null
                            if ($nameGroups.TryGetValue(
                                    $entryIdentityName,
                                    [ref]$nameGroup
                                )) {
                                $nameGroup.Count++
                            } else {
                                $nameGroups.Add(
                                    $entryIdentityName,
                                    [pscustomobject]@{
                                        Count         = 1
                                        CanonicalName = $entryName
                                    }
                                )
                            }
                        }
                        $directoryNameGroups.Add($directoryPath, $nameGroups)
                    }

                    $nameGroup = $null
                    $leafIdentityName = $leafName.Normalize(
                        [System.Text.NormalizationForm]::FormC
                    )
                    if (-not $nameGroups.TryGetValue(
                            $leafIdentityName,
                            [ref]$nameGroup
                        )) {
                        $identityFailed = $true
                        break
                    }
                    if ($nameGroup.Count -gt 1) {
                        $identityComponents.Add($leafName)
                    } else {
                        $identityComponents.Add($nameGroup.CanonicalName)
                    }
                } catch [System.UnauthorizedAccessException] {
                    $identityFailed = $true
                    break
                } catch [System.IO.IOException] {
                    $identityFailed = $true
                    break
                }

                $identityPath = $directoryPath
            }

            if ($identityFailed) {
                $identityKey = $resolvedPath
            } else {
                $rootPath = [System.IO.Path]::GetPathRoot($resolvedPath)
                if ($IsWindows) {
                    $rootPath = $rootPath.ToUpperInvariant()
                }
                $identityComponents.Add($rootPath)
                $identityComponents.Reverse()
                $identityKeyBuilder = [System.Text.StringBuilder]::new()
                foreach ($identityComponent in $identityComponents) {
                    $null = $identityKeyBuilder.Append($identityComponent.Length)
                    $null = $identityKeyBuilder.Append(':')
                    $null = $identityKeyBuilder.Append($identityComponent)
                }
                $identityKey = $identityKeyBuilder.ToString()
            }

            $null = $pathsByIdentity.TryAdd($identityKey, $resolvedPath)
        }

        [string[]] $orderedIdentityKeys = $pathsByIdentity.Keys
        [System.Array]::Sort($orderedIdentityKeys, [System.StringComparer]::Ordinal)

        foreach ($identityKey in $orderedIdentityKeys) {
            $resolvedPath = $pathsByIdentity[$identityKey]
            try {
                $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
            } catch [System.UnauthorizedAccessException] {
                $readError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot read YAML file '$resolvedPath': $($readError.Exception.Message)",
                    $readError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $resolvedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            } catch [System.IO.IOException] {
                $readError = $_
                $exception = [System.IO.IOException]::new(
                    "Cannot read YAML file '$resolvedPath': $($readError.Exception.Message)",
                    $readError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $resolvedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            }

            $textEncoding = Get-YamlTextEncoding -Name $Encoding
            $preambleLength = 0
            if ($bytes.Length -ge 4 -and
                $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and
                $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
                $textEncoding = Get-YamlTextEncoding -Name 'utf32BE'
                $preambleLength = 4
            } elseif ($bytes.Length -ge 4 -and
                $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and
                $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
                $textEncoding = Get-YamlTextEncoding -Name 'utf32LE'
                $preambleLength = 4
            } elseif ($bytes.Length -ge 3 -and
                $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and
                $bytes[2] -eq 0xBF) {
                $textEncoding = Get-YamlTextEncoding -Name 'utf8BOM'
                $preambleLength = 3
            } elseif ($bytes.Length -ge 2 -and
                $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                $textEncoding = Get-YamlTextEncoding -Name 'utf16BE'
                $preambleLength = 2
            } elseif ($bytes.Length -ge 2 -and
                $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                $textEncoding = Get-YamlTextEncoding -Name 'utf16LE'
                $preambleLength = 2
            }

            try {
                $yamlText = $textEncoding.GetString(
                    $bytes,
                    $preambleLength,
                    $bytes.Length - $preambleLength
                )
            } catch [System.Text.DecoderFallbackException] {
                $decodeError = $_
                $exception = [System.Text.DecoderFallbackException]::new(
                    "Cannot decode YAML file '$resolvedPath': the byte sequence is invalid.",
                    $decodeError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'YamlImportEncodingFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $resolvedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            }

            $parserParameters = @{
                Yaml              = $yamlText
                AsHashtable       = $AsHashtable
                NoEnumerate       = $NoEnumerate
                Depth             = $Depth
                MaxNodes          = $MaxNodes
                MaxAliases        = $MaxAliases
                MaxScalarLength   = $MaxScalarLength
                MaxTagLength      = $MaxTagLength
                MaxTotalTagLength = $MaxTotalTagLength
                MaxNumericLength  = $MaxNumericLength
            }
            try {
                ConvertFrom-Yaml @parserParameters | ForEach-Object {
                    $PSCmdlet.WriteObject($_, $false)
                }
            } catch {
                $parseError = $_
                $errorId = ($parseError.FullyQualifiedErrorId -split ',')[0]
                if ([string]::IsNullOrWhiteSpace($errorId)) {
                    $errorId = 'YamlImportParseFailed'
                }
                $exception = [System.FormatException]::new(
                    "Cannot parse YAML file '$resolvedPath': $($parseError.Exception.Message)",
                    $parseError.Exception
                )
                $record = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    $errorId,
                    $parseError.CategoryInfo.Category,
                    $resolvedPath
                )
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }
    }
}

