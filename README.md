# Yaml

A PowerShell module for working with YAML — parse YAML strings into PowerShell objects and serialize PowerShell objects back into YAML.

The module ships two cmdlets that mirror PowerShell's built-in `ConvertFrom-Json` / `ConvertTo-Json`, so the experience is familiar:

- `ConvertFrom-Yaml` — parses a YAML string into a `[PSCustomObject]` (or an ordered hashtable with `-AsHashtable`).
- `ConvertTo-Yaml` — serializes a PowerShell object, hashtable, or array into a YAML-formatted string.

No external dependencies — pure PowerShell. Aligned with the [YAML 1.2.2 core schema](https://yaml.org/spec/1.2.2/#103-core-schema).

## Prerequisites

This uses the following external resources:

- The [PSModule framework](https://github.com/PSModule) for building, testing and publishing the module.

## Installation

To install the module from the PowerShell Gallery, you can use the following command:

```powershell
Install-PSResource -Name Yaml
Import-Module -Name Yaml
```

## Usage

The module provides two cmdlets that mirror PowerShell's built-in `ConvertFrom-Json` / `ConvertTo-Json`:

| Cmdlet              | Alias             | Purpose                                  |
| ------------------- | ----------------- | ---------------------------------------- |
| `ConvertFrom-Yaml`  | `ConvertFrom-Yml` | Parse a YAML string into an object.      |
| `ConvertTo-Yaml`    | `ConvertTo-Yml`   | Serialize an object into a YAML string.  |

> [!IMPORTANT]
> The input to `ConvertFrom-Yaml` must be a valid YAML string. The cmdlet does not read files — use `Get-Content -Raw` or similar to read the file first, then pipe the string into `ConvertFrom-Yaml`.

### YAML specification

The module aligns with [**YAML 1.2.2**](https://yaml.org/spec/1.2.2/) (October 2021) — the latest revision of the YAML specification — and follows the [**core schema**](https://yaml.org/spec/1.2.2/#103-core-schema) for scalar resolution.

Practical implications of the core schema:

- `true` and `false` (lowercase only) parse as `[bool]`. `True`, `TRUE`, `yes`, `no`, `on`, `off`, etc. are plain strings.
- `null`, `~`, and an empty value parse as `$null`. `Null`, `NULL` are plain strings.
- Integers and floats parse to their native types using invariant culture.
- Anything else is a string. Quoted strings (`'...'`, `"..."`) always preserve the string type.

The supported YAML subset covers block-style mappings, block-style sequences, nested structures, single- and double-quoted scalars (with `\n`, `\t`, `\r`, `\\`, `\"` escapes in double quotes), document start (`---`) and end (`...`) markers, and full-line / inline `#` comments. Flow style (`[a, b]`, `{a: 1}`), block scalars (`|`, `>`), anchors, aliases, tags, multi-document streams, and `!!timestamp` are not yet supported.

### Example 1: Parse a YAML string

```powershell
$yaml = @'
name: Alice
age: 30
skills:
  - PowerShell
  - YAML
'@

$yaml | ConvertFrom-Yaml
```

### Example 2: Parse YAML as an ordered hashtable

```powershell
Get-Content config.yaml -Raw | ConvertFrom-Yaml -AsHashtable
```

### Example 3: Convert an object to YAML

```powershell
[ordered]@{
    name = 'Alice'
    skills = @('PowerShell', 'YAML')
} | ConvertTo-Yaml
```

### Example 4: Force a top-level YAML sequence

```powershell
Get-Process | Select-Object -First 3 Name, Id | ConvertTo-Yaml -AsArray
```

### Find more examples

To find more examples of how to use the module, please refer to the [examples](examples) folder.

Alternatively, you can use the Get-Command -Module 'This module' to find more commands that are available in the module.
To find examples of each of the commands you can use Get-Help -Examples 'CommandName'.

## Documentation

Link to further documentation if available, or describe where in the repository users can find more detailed documentation about
the module's functions and features.

## Contributing

Coder or not, you can contribute to the project! We welcome all contributions.

### For Users

If you don't code, you still sit on valuable information that can make this project even better. If you experience that the
product does unexpected things, throw errors or is missing functionality, you can help by submitting bugs and feature requests.
Please see the issues tab on this project and submit a new issue that matches your needs.

### For Developers

If you do code, we'd love to have your contributions. Please read the [Contribution guidelines](CONTRIBUTING.md) for more information.
You can either help by picking up an existing issue or submit a new one if you have an idea for a new feature or improvement.

## Acknowledgements

Here is a list of people and projects that helped this project in some way.
