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
| `Export-Yaml` | Serialize values and atomically write one YAML file. |
| `Format-Yaml` | Normalize YAML streams without projecting representation nodes to PowerShell values. |
| `Import-Yaml` | Strictly decode and parse YAML files. |
| `Merge-Yaml` | Merge complete YAML streams without losing representation graph details. |
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
order marks are detected automatically and override `-Encoding`. Malformed
bytes terminate with a path-specific error. `-NoEnumerate` and all parser
resource limits have the same behavior as `ConvertFrom-Yaml`.

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

## Format YAML streams

`Format-Yaml` normalizes existing YAML without converting it through
`PSCustomObject` or dictionary values. It retains document order and empty
documents, node kinds, scalar content, effective tags, anchors and aliases,
recursive graphs, complex keys, collection structure, and mapping order.

```powershell
$normalized = Get-Content -Path '.\config.yaml' | Format-Yaml -Indent 4
```

Pipeline records are joined with LF and parsed as one stream. The output is one
string with LF line endings and no final newline. Every document starts with
`---`; document-end markers, comments, directives, flow presentation, scalar
styles, and original anchor names are normalized. Effective standard tags use
`!!` shorthand where possible, while local and global tags use a deterministic
verbatim form.

Formatting is byte-idempotent at the same options:

```powershell
$normalized -ceq ($normalized | Format-Yaml -Indent 4)
```

`-Indent` accepts 2 through 9 spaces. The `-Depth`, `-MaxNodes`, `-MaxAliases`,
`-MaxScalarLength`, `-MaxTagLength`, `-MaxTotalTagLength`, and
`-MaxNumericLength` defaults and ranges match `ConvertFrom-Yaml`. Invalid YAML,
duplicate representation keys, undefined aliases, malformed tags, and resource
limit violations terminate with the same classified YAML errors as parsing.

## Merge YAML streams

`Merge-Yaml` combines two or more complete YAML streams directly through their
representation graphs. Every array element or pipeline record is one complete
stream, and every stream must contain the same positive document count. Later
streams have higher precedence, and documents merge pairwise by zero-based index.

```powershell
$baseYaml = Get-Content -LiteralPath '.\base.yaml' -Raw
$overlayYaml = Get-Content -LiteralPath '.\overlay.yaml' -Raw
$mergedYaml = Merge-Yaml -InputObject @($baseYaml, $overlayYaml)
```

Compatible mappings merge recursively by structural YAML key equality. Base key
order remains stable, replacing a value retains its position, and new overlay
keys append in overlay order. Complex and tagged keys are supported. Structural
fingerprints select comparison candidates only; mutation-aware indexes are
retained across overlays, and graph-aware equality makes the final key decision.

Compatible sequences use `-SequenceAction Replace`, `Append`, or `Unique`.
Unequal scalars, collection kinds, and incompatible effective tags use
`-ConflictAction Replace` or `Error`. A later YAML null uses `-NullAction
Replace` or `Ignore`; ignoring retains an existing prior node, including at a
document root.

```powershell
$baseYaml, $environmentYaml, $secretYaml |
    Merge-Yaml -SequenceAction Unique -ConflictAction Error -Indent 4
```

Tags, anchors, aliases, repeated nodes, cycles, mapping order, and selected
representation nodes remain graph data. Inputs are immutable, and YAML 1.1 `<<`
merge keys remain ordinary mapping entries rather than being expanded. Output is
one deterministic string with LF line endings, explicit document starts, and no
final newline.

The parser safety parameters and defaults match `Format-Yaml`. `-MaxNodes`
limits each parsed stream and applies independently to invocation-wide clone
creation, charged merge operations, and the resulting stream graph. Index,
fingerprint, candidate, alias-traversal, and equality work all consume the merge
operation budget. Alias and expanded-tag budgets are also enforced on the result.

## Export YAML files

`Export-Yaml` aggregates pipeline records like `ConvertTo-Yaml`, serializes the
complete value before changing the filesystem, and atomically publishes a
same-directory temporary file. It writes UTF-8 without a byte order mark, LF
line endings, and exactly one final newline by default.

```powershell
$config | Export-Yaml -Path '.\config.yaml'
'one', 'two' | Export-Yaml -Path '.\items.yaml' -Encoding utf16LE
$config | Export-Yaml -Path '.\generated\config.yaml' -CreateDirectory -PassThru
```

Use `-NewLine CRLF` or `-NoFinalNewline` to change presentation. `-NoClobber`
prevents replacement, while `-Force` permits replacing a read-only destination
and preserves its read-only state. The switches are mutually exclusive.
`-WhatIf` creates no directory or temporary file. `-PassThru` is the only mode
that emits the final `FileInfo`.

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
- YAML stream merging compares effective tags and structural representation
  values without projecting through PowerShell objects.
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

The offline test gate runs the latest official `yaml-test-suite` source release,
`v2022-01-17`, at commit `45db50aecf9b1520f8258938c88f396e96f30831`.
Its `data-2022-01-17` export is pinned at commit
`6e6c296ae9c9d2d5c4134b4b64d01b29ac19ff6f` with archive SHA-256
`47C173AFFEB480517B30FB77DC8C76FD48609B9B65DD1C1D3D0D0BAEE48D6AA9`.
The archive contains 402 inputs:

| Surface | Pass | PolicyDifference | Fail | NotApplicable |
| --- | ---: | ---: | ---: | ---: |
| Syntax and composition | 400 | 2 | 0 | 0 |
| Representation events | 308 | 0 | 0 | 94 |
| JSON projection | 277 | 2 | 0 | 123 |
| `out.yaml` projection | 241 | 1 | 0 | 160 |
| Official `emit.yaml` fixtures | 55 | 0 | 0 | 347 |
| Module self-round-trip | 305 | 3 | 0 | 94 |
| `Format-Yaml` representation and idempotence | 400 | 0 | 0 | 2 |

All 94 fixtures marked invalid are rejected. The valid `2JQS` and `X38W`
inputs are syntactically recognized and produce matching representation
events, then are rejected during load validation because representation
mapping keys must be unique. They are not unsupported grammar. Both are
reported as policy differences for module self-round-trip; `X38W`, the one
case with an `out.yaml` fixture, is also reported that way on that surface.

The formatter surface directly compares representation events and graph
identity before and after formatting, validates the emitted stream, and
requires byte-identical second formatting. It passes all 306 loadable valid
inputs and confirms that all 94 invalid inputs remain rejected. The two valid
duplicate-key policy cases are not applicable because `Format-Yaml` applies
the same representation-key uniqueness policy as `ConvertFrom-Yaml`.

The two JSON projection differences are `565N`, where `!!binary` intentionally
becomes `byte[]` instead of a Base64 string, and `J7PZ`, where legacy `!!omap`
intentionally becomes `System.Collections.Specialized.OrderedDictionary`
instead of remaining a sequence of one-entry mappings. `J7PZ` is also a
self-round-trip policy difference: once projected, its ordered dictionary
cannot be distinguished from an ordinary insertion-ordered PowerShell
dictionary, so emission cannot reconstruct the explicit `!!omap` tag. The
runner still preserves and compares `!!omap` order from representation
metadata. No event mismatch is classified as policy. All 55 official
`emit.yaml` fixtures are read and validated independently of the 402-input
module self-round-trip. The deterministic runner reports no unexplained
failures.

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
