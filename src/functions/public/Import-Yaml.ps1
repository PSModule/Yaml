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

        .PARAMETER Path
        One or more FileSystem paths. Wildcards are expanded. Resolved files
        are sorted deterministically and duplicates are suppressed.

        .PARAMETER LiteralPath
        One or more literal FileSystem paths. Wildcard characters are not
        expanded.

        .PARAMETER Encoding
        Encoding for files without a byte order mark. The default is utf8,
        which is strict UTF-8 without a byte order mark.

        .PARAMETER AsHashtable
        Returns mappings as insertion-ordered dictionaries.

        .PARAMETER NoEnumerate
        Writes each top-level YAML sequence as one array pipeline record.

        .PARAMETER Depth
        Maximum YAML node nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum number of YAML nodes in each file. The default is 100000.

        .PARAMETER MaxAliases
        Maximum number of alias nodes in each file. The default is 1000.

        .PARAMETER MaxScalarLength
        Maximum decoded character count for one scalar. The default is
        1048576.

        .PARAMETER MaxTagLength
        Maximum expanded character count for one tag. The default is 1024.

        .PARAMETER MaxTotalTagLength
        Maximum cumulative expanded tag characters. The default is 65536.

        .PARAMETER MaxNumericLength
        Maximum digits in an implicitly or explicitly typed number. The
        default is 4096.

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
        System.IO.FileInfo

        .OUTPUTS
        System.Object
    #>
    [OutputType([object])]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        # Expands wildcard paths and accepts path values or FullName properties.
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Path'
        )]
        [Alias('FullName')]
        [string[]] $Path,

        # Resolves exact paths from LiteralPath, PSPath, or FullName properties.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'LiteralPath'
        )]
        [Alias('PSPath')]
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
        $requestedPaths = [System.Collections.Generic.List[string]]::new()
    }
    process {
        $currentPaths = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
            $LiteralPath
        } else {
            $Path
        }
        foreach ($currentPath in $currentPaths) {
            $requestedPaths.Add($currentPath)
        }
    }
    end {
        $resolvedPaths = [System.Collections.Generic.List[string]]::new()
        foreach ($requestedPath in $requestedPaths) {
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
                if (-not [System.IO.File]::Exists($providerPath)) {
                    if ([System.IO.Directory]::Exists($providerPath)) {
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
                if (-not [System.IO.File]::Exists($pathInfo.ProviderPath)) {
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

        $pathComparer = if ($IsWindows) {
            [System.StringComparer]::OrdinalIgnoreCase
        } else {
            [System.StringComparer]::Ordinal
        }
        $uniquePaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
        foreach ($resolvedPath in $resolvedPaths) {
            $null = $uniquePaths.Add($resolvedPath)
        }
        [string[]] $orderedPaths = $uniquePaths
        [System.Array]::Sort($orderedPaths, $pathComparer)

        foreach ($resolvedPath in $orderedPaths) {
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
