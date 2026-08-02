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

## Commands

The seven exported commands fall into three groups. Each group has an in-depth
guide with runnable examples.

| Group | Command | Purpose |
| --- | --- | --- |
| [Conversion](src/functions/public/Conversion/Conversion.md) | `ConvertFrom-Yaml` | Parse one or more YAML documents into PowerShell values. |
| [Conversion](src/functions/public/Conversion/Conversion.md) | `ConvertTo-Yaml` | Serialize supported PowerShell values as YAML 1.2-compatible text. |
| [Files](src/functions/public/Files/Files.md) | `Import-Yaml` | Strictly decode and parse YAML files. |
| [Files](src/functions/public/Files/Files.md) | `Export-Yaml` | Serialize values and atomically write one YAML file. |
| [Streams](src/functions/public/Streams/Streams.md) | `Test-Yaml` | Test YAML syntax, tags, duplicate keys, and configured resource limits. |
| [Streams](src/functions/public/Streams/Streams.md) | `Format-Yaml` | Normalize YAML streams without projecting representation nodes to PowerShell values. |
| [Streams](src/functions/public/Streams/Streams.md) | `Merge-Yaml` | Merge complete YAML streams without losing representation graph details. |

`Conversion` moves data between YAML text and PowerShell values. `Files` adds
path resolution, strict decoding, and atomic writes on top of that. `Streams`
works on YAML text at the representation level and never projects to PowerShell
objects, which is what lets it keep tags, anchors, complex keys, and mapping
order intact.

## Convert YAML to PowerShell values

Ordinary string-key mappings become ordered `PSCustomObject` values. A top-level
sequence writes its items to the pipeline by default.

```powershell
$config = @'
name: example
enabled: true
ports: [80, 443]
'@ | ConvertFrom-Yaml

$config.name        # example
$config.ports[0]    # 80
```

Use `-AsHashtable` for insertion-ordered dictionaries and mappings with complex,
non-string, empty, or case-colliding keys, and `-NoEnumerate` to keep a top-level
sequence as one pipeline record. Every document in a multi-document stream is
returned separately.

The [Conversion](src/functions/public/Conversion/Conversion.md) guide is the full
projection reference: which YAML scalars produce which .NET types, how anchors
preserve object identity, what `!!set`, `!!omap`, `!!pairs`, and `!!binary`
produce, and which cases deliberately fail instead of losing data.

## Serialize PowerShell values as YAML

```powershell
[ordered]@{
    name    = 'example'
    enabled = $true
    ports   = @(80, 443)
} | ConvertTo-Yaml -ExplicitDocumentStart
```

`ConvertTo-Yaml` supports `PSCustomObject` and explicit PSObject note-property
bags, dictionaries, sequences, strings, characters, Booleans, integer and
floating-point numbers, `BigInteger`, `DateTime`, `DateTimeOffset`, enums, null,
and byte arrays. Repeated acyclic collection references are emitted with anchors
and aliases. Cyclic graphs and unsupported runtime objects fail specifically;
values are never silently truncated or converted with `ToString()`.

## Read and write files

```powershell
$configs = Import-Yaml -Path '.\config\*.yaml' -AsHashtable
$config | Export-Yaml -Path '.\generated\config.yaml' -CreateDirectory
```

`Import-Yaml` decodes strictly, detects UTF-8, UTF-16, and UTF-32 byte order
marks, and parses with `ConvertFrom-Yaml` semantics. `Export-Yaml` serializes the
complete value before touching the filesystem and publishes it atomically as
UTF-8 without a byte order mark, LF line endings, and exactly one final newline.
See [Files](src/functions/public/Files/Files.md) for encodings, `-LiteralPath`
and wildcard handling, `-NoClobber` and `-Force`, and `-PassThru`.

## Validate, normalize, and merge YAML

```powershell
if (Get-Content -Path '.\config.yaml' | Test-Yaml) {
    Get-Content -Path '.\config.yaml' | Format-Yaml -Indent 4
}

$baseYaml, $environmentYaml | Merge-Yaml -SequenceAction Unique
```

`Format-Yaml` is byte-idempotent at the same options and retains node kinds,
effective tags, anchors and aliases, recursive graphs, complex keys, and mapping
order. `Merge-Yaml` combines complete streams pairwise by document index with
configurable sequence, conflict, and null handling. See
[Streams](src/functions/public/Streams/Streams.md) for the full options and
guarantees.

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
does not fit the data. The
[Conversion](src/functions/public/Conversion/Conversion.md) guide lists every
resulting type and every rejection case.

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
becomes `byte[]` instead of a base64 string, and `J7PZ`, where legacy `!!omap`
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

## Documentation

The command reference and the group guides are published at
[psmodule.io/Yaml](https://psmodule.io/Yaml/). Help is also available in the
console:

```powershell
Get-Help -Name ConvertFrom-Yaml -Examples
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
