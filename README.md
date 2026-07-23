# Yaml

`Yaml` converts between YAML streams and PowerShell values. Its parser,
schema construction, graph projection, and emitter are implemented in the
module's PowerShell source, with no external parser library or runtime
assembly dependency.

Compatibility target: PowerShell Core LTS and newer, with the source and
artifact contract pinned to PowerShell 7.6 (`CompatiblePSEditions = 'Core'`).

The implementation is layered: Unicode and c-printable validation feeds a
document/directive scanner; context-aware block and flow readers produce syntax
tokens; an iterative composer builds the representation graph; the core-schema
constructor and PowerShell projector create public values. Serialization uses a
separate safe value classifier, iterative reference-graph normalizer, and
presentation emitter. Internal arrays, nulls, and byte arrays move through
boxed values rather than the PowerShell pipeline.

## Installation

```powershell
Install-PSResource -Name Yaml
Import-Module -Name Yaml
```

The module exports:

| Command | Purpose |
| --- | --- |
| `ConvertFrom-Yaml` | Parse one or more YAML documents into PowerShell values. |
| `ConvertTo-Yaml` | Serialize supported PowerShell values as YAML 1.2-compatible text. |
| `Test-Yaml` | Test YAML syntax, tags, duplicate keys, and configured resource limits. |

## Parse YAML

Ordinary string-key mappings become ordered `PSCustomObject` values. A
top-level sequence writes its items to the pipeline by default.

```powershell
$config = @'
name: example
enabled: true
ports: [80, 443]
'@ | ConvertFrom-Yaml

$config.name
$config.ports[0]
```

Pipeline strings are joined with LF and parsed as one stream. This makes
line-oriented input work as expected:

```powershell
$config = Get-Content -Path '.\config.yaml' | ConvertFrom-Yaml
```

Use `-NoEnumerate` when a top-level sequence must remain one pipeline record:

```powershell
$servers = @'
- name: web-1
- name: web-2
'@ | ConvertFrom-Yaml -NoEnumerate
```

Every YAML document is returned separately:

```powershell
$documents = @(@'
---
name: first
---
name: second
'@ | ConvertFrom-Yaml)
```

Use `-AsHashtable` for insertion-ordered dictionaries and mappings with
complex, non-string, empty, or case-colliding keys:

```powershell
$mapping = @'
? [region, port]
: eu-1
'@ | ConvertFrom-Yaml -AsHashtable
```

## Serialize PowerShell values

`ConvertTo-Yaml` supports `PSCustomObject` and explicit PSObject note-property
bags, dictionaries, sequences, strings, characters, Booleans, integer and
floating-point numbers, `BigInteger`, `DateTime`, `DateTimeOffset`, enums,
null, and byte arrays.

```powershell
$yaml = [ordered]@{
    name    = 'example'
    enabled = $true
    ports   = @(80, 443)
} | ConvertTo-Yaml -ExplicitDocumentStart

$roundTrip = $yaml | ConvertFrom-Yaml
```

Multiple pipeline records are collected into one top-level YAML sequence:

```powershell
'one', 'two' | ConvertTo-Yaml
```

Pass an array directly when it represents one input value:

```powershell
$items = @('one', 'two')
ConvertTo-Yaml -InputObject $items
```

`-EnumsAsStrings` emits enum names instead of their underlying numeric values.
`-Indent` accepts 2 through 9 spaces. `-Depth`, `-MaxNodes`, and
`-MaxScalarLength` constrain serialization. The maximum supported depth is
128, and the default is 100.

Repeated acyclic collection references are emitted with anchors and aliases.
Cyclic graphs and unsupported runtime objects fail specifically; values are
never silently truncated or converted with `ToString()`.

## Validate YAML

```powershell
if (Get-Content -Path '.\config.yaml' | Test-Yaml) {
    'The YAML stream is valid.'
}
```

`Test-Yaml` uses the same parser and limits as `ConvertFrom-Yaml`. It returns
`$false` for YAML-specific failures, including duplicate keys and resource
limit violations. Unexpected runtime failures are not suppressed.

## Data model and safety

- Plain implicit scalars use the YAML 1.2 core schema. YAML 1.1-only Boolean
  words such as `yes` and untagged timestamps remain strings.
- Standard explicit tags are handled without reflection: `str`, `null`,
  `bool`, `int`, `float`, `binary`, `timestamp`, `seq`, `map`, `set`, `omap`,
  and `pairs`.
- Unknown application tags are discarded safely. Tagged scalars become
  strings and tagged collections retain their sequence or mapping shape.
- Duplicate mapping keys are rejected after scalar construction, including
  structurally equal complex keys.
- Aliases preserve collection reference identity where PowerShell can
  represent it.
- YAML merge keys are not expanded; `<<` is ordinary mapping data under the
  YAML 1.2 core schema.
- Parsing defaults to depth 100, 100000 nodes, 1000 aliases, 1048576 decoded
  characters per scalar, 1024 characters per expanded tag, 65536 cumulative
  expanded tag characters, and 4096 digits per numeric scalar. The
  corresponding limit parameters can be lowered for untrusted input.
- The public maximum depth of 128 is exercised for parsing and serialization
  in fresh PowerShell 7.6+ artifact tests.

Default object projection requires mapping keys that can be represented
without loss as PowerShell properties. Use `-AsHashtable` when that restriction
does not fit the data.

## Conformance corpus

The offline test gate runs the complete released `yaml-test-suite` data corpus
at commit `6ad3d2c62885d82fc349026c136ef560838fdf3d` (generated from source
commit `45db50ae`). The pinned archive contains 402 inputs:

- all 94 fixtures marked invalid are rejected;
- 306 of 308 fixtures marked valid are accepted;
- the other two valid-syntax fixtures, `2JQS` and `X38W`, are deliberately
  rejected as a load/composition policy after syntactic recognition because this
  module rejects duplicate mapping keys in the representation graph;
- 282 fixtures include `in.json`; three belong to invalid inputs, 277 of the
  279 applicable constructions match exactly, and two use a different
  documented projection policy.

The two construction-policy differences are `565N`, where this module
constructs `!!binary` as `byte[]` instead of a Base64 string, and `J7PZ`, where
the explicitly supported `!!omap` tag becomes an ordered dictionary instead of
remaining a sequence of one-entry mappings. The deterministic runner reports
398 passing cases, four policy exclusions, and no unexplained failures.

These results are a pinned compatibility measurement, not a claim that a finite
corpus proves complete YAML 1.2.2 compliance.

## Compatibility boundaries

The module preserves data values and graph sharing where representable. A
PowerShell object does not retain YAML presentation details, so data round
trips do **not** preserve comments, scalar style, tag spelling or handles,
anchor names, mapping presentation, line endings, or source formatting.
Unknown application tags are not reconstructed.

Exact integer CLR widths and enum CLR types are not reconstructed after a YAML
round trip. Finite non-exponent decimal values are constructed as `Decimal`
when representable; other finite floats use `Double`. The emitter writes a
deliberately limited YAML 1.2-compatible subset.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
