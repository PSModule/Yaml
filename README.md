# {{ NAME }}

{{ DESCRIPTION }}

## Prerequisites

This uses the following external resources:
- The [PSModule framework](https://github.com/PSModule) for building, testing and publishing the module.

## Installation

To install the module from the PowerShell Gallery, you can use the following command:

```powershell
Install-PSResource -Name {{ NAME }}
Import-Module -Name {{ NAME }}
```

## Usage

The module provides two cmdlets that mirror PowerShell's built-in `ConvertFrom-Json` / `ConvertTo-Json`:

| Cmdlet              | Alias            | Purpose                                |
| ------------------- | ---------------- | -------------------------------------- |
| `ConvertFrom-Yaml`  | `ConvertFrom-Yml` | Parse a YAML string into an object.   |
| `ConvertTo-Yaml`    | `ConvertTo-Yml`  | Serialize an object into a YAML string. |

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

### Example 3: Parse YAML frontmatter from a markdown file

```powershell
Get-Content post.md -Raw | ConvertFrom-Yaml
```

### Example 4: Convert an object to YAML

```powershell
[ordered]@{
    name = 'Alice'
    skills = @('PowerShell', 'YAML')
} | ConvertTo-Yaml
```

### Example 5: Force a top-level YAML sequence

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
