# Files

Read and write YAML files.

| Command | Purpose |
| --- | --- |
| [`Import-Yaml`](https://psmodule.io/Yaml/Functions/Import-Yaml/) | Strictly decode and parse YAML files. |
| [`Export-Yaml`](https://psmodule.io/Yaml/Functions/Export-Yaml/) | Serialize values and atomically write one YAML file. |

These two commands own everything the filesystem adds on top of conversion:
resolving paths, decoding and encoding text, and publishing a file safely. The
value semantics are unchanged — `Import-Yaml` parses exactly like
[`ConvertFrom-Yaml`](https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/) and
`Export-Yaml` serializes exactly like
[`ConvertTo-Yaml`](https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/), so the
[Conversion](../Conversion/Conversion.md) page is the reference for what you get
back and what you can write.

## Import YAML files

`Import-Yaml` reads complete files with strict Unicode decoding and delegates
parsing to `ConvertFrom-Yaml`. `-Path` expands wildcards and accepts `FileInfo`
pipeline input; `-LiteralPath` preserves wildcard characters in filenames.
Resolved files are deduplicated and read in deterministic path order.

```powershell
$configs = Import-Yaml -Path '.\config\*.yaml' -AsHashtable
Get-ChildItem -Path '.\services' -Filter '*.yaml' | Import-Yaml
Import-Yaml -LiteralPath '.\config[production].yaml'
```

UTF-8 without a byte order mark is the default. UTF-8, UTF-16, and UTF-32 byte
order marks are detected automatically and override `-Encoding`. Malformed bytes
terminate with a path-specific error. `-NoEnumerate` and all parser resource
limits have the same behavior as `ConvertFrom-Yaml`.

Because parsing is identical, every projection rule documented for
`ConvertFrom-Yaml` applies: mappings become `PSCustomObject` values unless you ask
for `-AsHashtable`, a top-level sequence enumerates unless you pass
`-NoEnumerate`, and each document in a multi-document file is emitted separately.

```powershell
$deployments = Import-Yaml -Path '.\manifests\*.yaml' |
    Where-Object { $_.kind -eq 'Deployment' }
```

## Export YAML files

`Export-Yaml` aggregates pipeline records like `ConvertTo-Yaml`, serializes the
complete value before changing the filesystem, and atomically publishes a
same-directory temporary file. It writes UTF-8 without a byte order mark, LF line
endings, and exactly one final newline by default.

```powershell
$config | Export-Yaml -Path '.\config.yaml'
'one', 'two' | Export-Yaml -Path '.\items.yaml' -Encoding utf16LE
$config | Export-Yaml -Path '.\generated\config.yaml' -CreateDirectory -PassThru
```

Use `-NewLine CRLF` or `-NoFinalNewline` to change presentation. `-NoClobber`
prevents replacement, while `-Force` permits replacing a read-only destination and
preserves its read-only state. The switches are mutually exclusive. `-WhatIf`
creates no directory or temporary file. `-PassThru` is the only mode that emits
the final `FileInfo`.

Serializing before touching the filesystem means an unsupported value or a cyclic
graph fails without leaving a partial or truncated file behind. An existing
destination is only replaced once the complete new content exists on disk.

## Round-tripping a file

```powershell
$config = Import-Yaml -LiteralPath '.\config.yaml'
$config.replicas = 3
$config | Add-Member -NotePropertyName 'tier' -NotePropertyValue 'standard'
$config | Export-Yaml -Path '.\config.yaml' -Force
```

Assignment updates a key that already exists. A parsed mapping is a
`PSCustomObject`, so a *new* key has to be added with `Add-Member`, or the whole
document parsed with `-AsHashtable` and edited as a dictionary.

This rewrites the values, not the presentation: comments, scalar styles, anchor
names and original formatting are not carried through a PowerShell object. When
the file's YAML presentation must survive the edit, use
[`Merge-Yaml`](https://psmodule.io/Yaml/Functions/Merge-Yaml/) or
[`Format-Yaml`](https://psmodule.io/Yaml/Functions/Format-Yaml/) from the
[Streams](../Streams/Streams.md) group instead, which work on the representation
graph directly.
