# Conversion

Convert between YAML text and PowerShell values.

| Command | Purpose |
| --- | --- |
| [`ConvertFrom-Yaml`](https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/) | Parse one or more YAML documents into PowerShell values. |
| [`ConvertTo-Yaml`](https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/) | Serialize supported PowerShell values as YAML 1.2-compatible text. |

Conversion projects YAML through to PowerShell values: a parsed document becomes
objects, arrays and scalars you can index, filter and pass down the pipeline, and
a PowerShell value becomes YAML text. If you need to keep YAML *as* YAML, with its
tags, anchors and node kinds intact, use the [Streams](../Streams/Streams.md)
commands instead.

## Parse YAML

Ordinary string-key mappings become ordered `PSCustomObject` values. A top-level
sequence writes its items to the pipeline by default.

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

Use `-AsHashtable` for insertion-ordered dictionaries and mappings with complex,
non-string, empty, or case-colliding keys:

```powershell
$mapping = @'
? [region, port]
: eu-1
'@ | ConvertFrom-Yaml -AsHashtable
```

## The YAML to PowerShell object model

This section describes exactly what a parsed document becomes, so you can predict
the shape before you run anything.

### Scalars

Plain, unquoted scalars are resolved with the YAML 1.2 **core schema**. Quoted and
block scalars are always strings unless you give them an explicit tag.

| YAML text | PowerShell type | Value |
| --- | --- | --- |
| `null`, `Null`, `NULL`, `~`, empty | *none* | `$null` |
| `true`, `True`, `TRUE`, `false`, `False`, `FALSE` | `System.Boolean` | `$true` / `$false` |
| `7`, `-7`, `+7`, `010` | `System.Int32` | `7`, `-7`, `7`, `10` |
| `0o17`, `0x1F` | `System.Int32` | `15`, `31` |
| `9223372036854775807` | `System.Int64` | widened past `Int32` |
| `9223372036854775808` | `System.Numerics.BigInteger` | widened past `Int64` |
| `1.5`, `.5`, `1.`, `3.0` | `System.Decimal` | exact, no exponent |
| `1e3`, `0.5e3`, `2.3e-5` | `System.Double` | exponent present |
| `.inf`, `+.inf`, `-.inf`, `.nan` | `System.Double` | infinity and NaN |
| anything else | `System.String` | the scalar text |

Integers pick the narrowest of `Int32`, `Int64` and `BigInteger` that holds the
value. Finite decimal forms without an exponent become `Decimal` when
representable, so `0.1` keeps its exact value; anything with an exponent becomes
`Double`. `010` is decimal ten, because the core schema has no leading-zero octal.

Forms that only exist in YAML 1.1 are **not** resolved and stay strings:

```powershell
$v = 'a: yes', 'b: 0b1010', 'c: 1_000', 'd: 2001-12-14' -join "`n" | ConvertFrom-Yaml
$v.a.GetType().Name   # String
$v.b.GetType().Name   # String
$v.c.GetType().Name   # String
$v.d.GetType().Name   # String  - an implicit timestamp is text
```

### Explicitly tagged scalars

| Tag | PowerShell type |
| --- | --- |
| `!!str` | `System.String` |
| `!!null` | `$null` |
| `!!bool` | `System.Boolean` |
| `!!int` | `System.Int32`, `System.Int64`, or `System.Numerics.BigInteger` |
| `!!float` | `System.Decimal` or `System.Double` |
| `!!binary` | `System.Byte[]` decoded from base64 |
| `!!timestamp` | `System.DateTime` or `System.DateTimeOffset` |

A standard tag whose text does not fit the tag fails rather than falling back to a
string. `!!bool "yes"` raises `YamlInvalidTaggedScalar`, because `yes` is not a
YAML 1.2 Boolean. Unknown application tags are discarded safely: `!custom 5`
becomes the string `5`, and a tagged collection keeps its sequence or mapping
shape.

Timestamps are only constructed for the explicit `!!timestamp` tag:

```powershell
$t = @'
day:    !!timestamp 2001-12-14
zoned:  !!timestamp 2001-12-14T21:59:43.10-05:00
naive:  !!timestamp "2001-12-14 21:59:43"
'@ | ConvertFrom-Yaml

$t.day.GetType().Name     # DateTime,       Kind Utc, midnight
$t.zoned.GetType().Name   # DateTimeOffset, offset preserved
$t.naive.GetType().Name   # DateTime,       Kind Utc
```

A value with a zone (`Z` or `±hh:mm`) becomes `DateTimeOffset`. A date-only or
zone-less value becomes `DateTime` with `Kind` set to `Utc`.

### Mappings

By default a mapping becomes a `PSCustomObject` whose note-properties are added in
source order, so `Format-List` and `PSObject.Properties` both report the original
key order.

With `-AsHashtable` a mapping becomes a
`System.Collections.Specialized.OrderedDictionary` instead. The switch is
recursive: nested mappings are dictionaries too. Dictionary keys are the projected
key values, so keys that are not usable as property names survive:

```powershell
$d = @'
? [region, port]
: eu-1
~: nullkey
1: number
'1': text
'@ | ConvertFrom-Yaml -AsHashtable

$d.Count                                       # 4
($d.Keys | Select-Object -First 1).GetType()   # System.Object[]  - the complex key
```

The four key types are `Object[]`, `DBNull`, `Int32` and `String`, in source order.
A YAML null key is stored as `[System.DBNull]::Value`, because a dictionary cannot
hold a `$null` key. The integer key `1` and the string key `'1'` are distinct
entries.

### Sequences

A sequence becomes `System.Object[]`. Nested sequences are always arrays, whatever
the enumeration options.

A top-level sequence is enumerated onto the pipeline by default, one record per
item. `-NoEnumerate` writes the whole sequence as a single record:

```powershell
(ConvertFrom-Yaml -Yaml "- 1`n- 2" | Measure-Object).Count               # 2
(ConvertFrom-Yaml -Yaml "- 1`n- 2" -NoEnumerate | Measure-Object).Count  # 1
```

An empty top-level sequence therefore writes nothing by default, and one empty
array with `-NoEnumerate`.

### Multi-document streams

One object is emitted per document, in document order. An empty document emits
`$null`:

```powershell
@(ConvertFrom-Yaml -Yaml "---`n---`n").Count   # 2, both $null
```

`-NoEnumerate` applies per document, so a stream of two sequence documents writes
two records instead of one per item.

### Anchors and aliases

An alias to a collection projects to the **same object instance**, in both
`PSCustomObject` and `-AsHashtable` mode. Editing through one reference is visible
through the other:

```powershell
$g = @'
defaults: &d { region: eu-1 }
primary: *d
'@ | ConvertFrom-Yaml

[object]::ReferenceEquals($g.defaults, $g.primary)   # True
```

Recursive aliases are supported, so a node can contain itself. Aliases to scalars
carry the value, not an identity: scalars are compared by value.

### Collection tags

| Tag | PowerShell projection |
| --- | --- |
| `!!seq` | `System.Object[]` |
| `!!map` | `PSCustomObject`, or `OrderedDictionary` with `-AsHashtable` |
| `!!set` | `OrderedDictionary` with `$null` values, **always**, even without `-AsHashtable` |
| `!!omap` | `OrderedDictionary`, duplicate keys rejected |
| `!!pairs` | `System.Object[]` of single-entry `OrderedDictionary` values, duplicates allowed |

```powershell
$s = ConvertFrom-Yaml -Yaml "!!set`n? a`n? b"
$s.GetType().Name    # OrderedDictionary
$null -eq $s['a']    # True

$p = ConvertFrom-Yaml -Yaml "!!pairs`n- a: 1`n- a: 2" -NoEnumerate
$p.Count             # 2, both keyed 'a'
```

`!!set`, `!!omap` and `!!pairs` need dictionary semantics to keep their meaning, so
they select dictionary projection for themselves regardless of `-AsHashtable`.

### What fails instead of losing data

Default `PSCustomObject` projection only accepts mapping keys that can become
PowerShell properties without loss. Everything else is a terminating,
specifically classified error rather than a silent rename or drop.

| Error ID | Cause | Fix |
| --- | --- | --- |
| `YamlMappingKeyNotString` | The key is a sequence, mapping, number, Boolean, null, or empty string. | Use `-AsHashtable`. |
| `YamlPropertyNameCollision` | Two keys differ only by case, such as `Name` and `name`. | Use `-AsHashtable`. |
| `YamlPropertyNameReserved` | The key is `PSObject`, `PSTypeNames`, `PSBase`, `PSAdapted`, or `PSExtended`. | Use `-AsHashtable`. |
| `YamlDuplicateKey` | The same key appears twice in one mapping. | Fix the document. Rejected in both modes. |

`YamlDuplicateKey` is a representation-level rule and applies with `-AsHashtable`
too, including structurally equal complex keys. The other three are property-model
restrictions that `-AsHashtable` lifts.

### Worked example

```yaml
name: example
retries: 3
ratio: 0.25
enabled: true
notes: null
created: !!timestamp 2024-05-01T09:30:00Z
tags: [alpha, beta]
defaults: &defaults
  region: eu-1
  tier: standard
services:
  - name: api
    settings: *defaults
  - name: worker
    settings: *defaults
```

Parsing that document with `ConvertFrom-Yaml` produces one `PSCustomObject`:

```text
PSCustomObject
├─ name       System.String           'example'
├─ retries    System.Int32            3
├─ ratio      System.Decimal          0.25
├─ enabled    System.Boolean          True
├─ notes      $null
├─ created    System.DateTimeOffset   2024-05-01T09:30:00+00:00
├─ tags       System.Object[]
│  ├─ [0]     System.String           'alpha'
│  └─ [1]     System.String           'beta'
├─ defaults   PSCustomObject          ◄─────────┐  same instance
│  ├─ region  System.String           'eu-1'    │
│  └─ tier    System.String           'standard'│
└─ services   System.Object[]                   │
   ├─ [0]     PSCustomObject                    │
   │  ├─ name     System.String  'api'          │
   │  └─ settings PSCustomObject ───────────────┤
   └─ [1]     PSCustomObject                    │
      ├─ name     System.String  'worker'       │
      └─ settings PSCustomObject ───────────────┘
```

```powershell
$doc = Get-Content -Path '.\config.yaml' -Raw | ConvertFrom-Yaml

$doc.retries.GetType().Name    # Int32
$doc.ratio.GetType().Name      # Decimal
$doc.created.GetType().Name    # DateTimeOffset
$doc.services[1].name          # worker

[object]::ReferenceEquals($doc.defaults, $doc.services[0].settings)   # True
```

## Serialize PowerShell values

`ConvertTo-Yaml` supports `PSCustomObject` and explicit PSObject note-property
bags, dictionaries, sequences, strings, characters, Booleans, integer and
floating-point numbers, `BigInteger`, `DateTime`, `DateTimeOffset`, enums, null,
and byte arrays.

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
`-MaxScalarLength` constrain serialization. The maximum supported depth is 128,
and the default is 100.

Repeated acyclic collection references are emitted with anchors and aliases.
Cyclic graphs and unsupported runtime objects fail specifically; values are never
silently truncated or converted with `ToString()`.

## Round-trip expectations

A PowerShell object does not retain YAML presentation, so a data round trip does
**not** preserve comments, scalar style, tag spelling or handles, anchor names,
mapping presentation, line endings, or source formatting. Unknown application tags
are not reconstructed.

Exact integer CLR widths and enum CLR types are not reconstructed after a YAML
round trip. Finite non-exponent decimal values are constructed as `Decimal` when
representable; other finite floats use `Double`. The emitter writes a deliberately
limited YAML 1.2-compatible subset.

When presentation matters more than the values, format or merge the YAML directly
with the [Streams](../Streams/Streams.md) commands, which never project through
PowerShell values at all.
