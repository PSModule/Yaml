# Streams

Work on YAML as YAML, without projecting it to PowerShell values.

| Command | Purpose |
| --- | --- |
| [`Test-Yaml`](https://psmodule.io/Yaml/Functions/Streams/Test-Yaml/) | Test YAML syntax, tags, duplicate keys, and configured resource limits. |
| [`Format-Yaml`](https://psmodule.io/Yaml/Functions/Streams/Format-Yaml/) | Normalize YAML streams without projecting representation nodes to PowerShell values. |
| [`Merge-Yaml`](https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/) | Merge complete YAML streams without losing representation graph details. |

These three commands share one defining property: they operate on YAML text at the
representation level and never project to PowerShell objects. That is what
separates them from [Conversion](https://psmodule.io/Yaml/Functions/Conversion/). A stream keeps its
node kinds, effective tags, anchors and aliases, complex keys, recursive graphs,
empty documents and mapping order all the way through, because nothing is ever
turned into a `PSCustomObject` or a dictionary along the way.

Practical consequence: values that cannot survive a PowerShell projection — a
sequence used as a mapping key, a `!!set`, a node that references itself, a
mapping whose keys collide only by case — pass through these commands intact.

## Validate YAML

```powershell
if (Get-Content -Path '.\config.yaml' | Test-Yaml) {
    'The YAML stream is valid.'
}
```

`Test-Yaml` uses the same parser and limits as `ConvertFrom-Yaml`. It returns
`$false` for YAML-specific failures, including duplicate keys and resource limit
violations. Unexpected runtime failures are not suppressed, so a genuine bug still
surfaces as an error instead of a quiet `$false`.

Use it as a gate before a more expensive step:

```powershell
Get-ChildItem -Path '.\manifests' -Filter '*.yaml' |
    Where-Object { -not (Get-Content -LiteralPath $_.FullName | Test-Yaml) } |
    Select-Object -ExpandProperty FullName
```

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
styles, and original anchor names are normalized. Effective standard tags use `!!`
shorthand where possible, while local and global tags use a deterministic verbatim
form.

Formatting is byte-idempotent at the same options:

```powershell
$normalized -ceq ($normalized | Format-Yaml -Indent 4)
```

`-Indent` accepts 2 through 9 spaces. The `-Depth`, `-MaxNodes`, `-MaxAliases`,
`-MaxScalarLength`, `-MaxTagLength`, `-MaxTotalTagLength`, and `-MaxNumericLength`
defaults and ranges match `ConvertFrom-Yaml`. Invalid YAML, duplicate
representation keys, undefined aliases, malformed tags, and resource limit
violations terminate with the same classified YAML errors as parsing.

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
order remains stable, replacing a value retains its position, and new overlay keys
append in overlay order. Complex and tagged keys are supported. Structural
fingerprints select comparison candidates only; mutation-aware indexes are
retained across overlays, and graph-aware equality makes the final key decision.

Compatible sequences use `-SequenceAction Replace`, `Append`, or `Unique`. Unequal
scalars, collection kinds, and incompatible effective tags use `-ConflictAction
Replace` or `Error`. A later YAML null uses `-NullAction Replace` or `Ignore`;
ignoring retains an existing prior node, including at a document root.

```powershell
$baseYaml, $environmentYaml, $secretYaml |
    Merge-Yaml -SequenceAction Unique -ConflictAction Error -Indent 4
```

Tags, anchors, aliases, repeated nodes, cycles, mapping order, and selected
representation nodes remain graph data. Inputs are immutable, and YAML 1.1 `<<`
merge keys remain ordinary mapping entries rather than being expanded. Output is
one deterministic string with LF line endings, explicit document starts, and no
final newline.

The parser safety parameters and defaults match `Format-Yaml`. `-MaxNodes` limits
each parsed stream and applies independently to invocation-wide clone creation,
charged merge operations, and the resulting stream graph. Index, fingerprint,
candidate, alias-traversal, and equality work all consume the merge operation
budget. Alias and expanded-tag budgets are also enforced on the result.

## Choosing between Streams and Conversion

| You want to | Use |
| --- | --- |
| Read configuration values into PowerShell | [`ConvertFrom-Yaml`](https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/) or [`Import-Yaml`](https://psmodule.io/Yaml/Functions/Files/Import-Yaml/) |
| Check a file before using it | `Test-Yaml` |
| Canonicalize YAML for diffing or storage | `Format-Yaml` |
| Layer environment or secret overlays onto a base file | `Merge-Yaml` |
| Emit YAML from PowerShell values | [`ConvertTo-Yaml`](https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/) or [`Export-Yaml`](https://psmodule.io/Yaml/Functions/Files/Export-Yaml/) |

If the YAML must come back out looking like YAML, stay in this group. If you need
to read or compute with the data, cross over to
[Conversion](https://psmodule.io/Yaml/Functions/Conversion/).
