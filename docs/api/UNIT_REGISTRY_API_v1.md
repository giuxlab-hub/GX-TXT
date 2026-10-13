# Unit Registry API v1

`unitRegistryConversionPlan source_unit target_unit` returns the exact public
conversion descriptor: source/target definitions, source-to-canonical expression,
intrinsic base scale ratio and target-from-canonical expression. It reuses CORE's
prefix/base/dimension authority; consumers do not maintain another unit table.
Incompatible or semantic identity-only conversions reject the request. The same
descriptor is available to both Script Bridge languages as `conversion_plan`.
Dataset Transform persists and applies this descriptor only on explicit request.

SPDX-License-Identifier: GPL-3.0-or-later

Introduced in GX-TXT 0.9.7.7. This public API is distinct from Semantic
Registry API v1. Unit is a numeric/presentation symbol, not a scientific role.

## Audit of the preexisting unit system

Before this API, Tcl's Unit Selector used
`core/tcl/scientific_plot_framework_api_v1.tcl`:
`unitTclSingle`, `unitTclDimensionKey`, `unitTclCompatible`, and a
hardcoded candidate list. Octave's Unit/Dimension API v1 used
`core/octave/units/gxtxt_unit_parse.m`, `gxtxt_unit_compatible.m`, and
`gxtxt_unit_convert.m`. Both handled base A/V/s/Hz/Ohm/W/J/K/mol/m/g,
SI prefixes, min/h/day and simple products/divisions/powers. Octave
conversion used scale ratios of matching dimension vectors. The plot
display scaler selected time units or SI prefixes when recognized; an
unrecognized unit was left as-is for auto display. There was no public
plugin registration or persisted custom conversion definition.

FS/dB/dBFS were added as identity-only level units in 0.9.7.1; ppm/pH
were added by explicit hardcoded identity cases in 0.9.7.3. These remain
opaque by default. All symbols, including previously unknown ones, now
support identity `foo -> foo`. No implicit ppm→mg/L or pH→concentration
conversion exists.

## Tcl API

```tcl
::GX::unitRegistryRegister custom_activity [dict create \
    label "Custom activity" description "Assay-specific activity" \
    owner_plugin my.plugin conversion_kind formula \
    canonical_unit mol/L \
    to_canonical {x * 2e-3} from_canonical {x / 2e-3}]
::GX::unitRegistryDefinition custom_activity
::GX::unitRegistryList
::GX::unitRegistryByProvider my.plugin
::GX::datasetVariableUnitDefinition dataset_id variable_id
```

`conversion_kind` is `opaque`, `identity`, `intrinsic`, `scale`,
`affine`, or `formula`. For `scale`, provide nonzero `scale` and
`canonical_unit`; for `affine`, add `offset` such that
`canonical = source * scale + offset`. The API derives both formulas.
For `formula`, provide both directions. The registry validates syntax
before registration. Unknown units resolve as opaque definitions. An
owner module's definitions are offered only while it is installed and
enabled; the dataset unit string stays intact when the provider is absent.

Descriptor-driven plugins can register without Tcl internals:

```ini
[units]
ids=particle_speed_unit
[unit.particle_speed_unit]
symbol=cm/s
label=Centimeters per second
description=Particle speed display unit
conversion_kind=scale
canonical_unit=m/s
scale=0.01
```

`ids` are descriptor keys; `symbol` is the visible/persisted unit.
Definitions become active with the normal module lifecycle.

## Per-variable custom relation

Dataset Variable Schema API v2 additionally persists `unit`,
`canonical_unit`, `to_canonical`, `from_canonical`, and
`display_label` by stable variable ID, including after rename and
Use=no/yes. Variables can retain an opaque unit without formulas.
A custom relation requires both formulas. These are exported to the
derived session runtime unit registry for Octave consumers and survive
save/reload. A plugin definition and a variable-specific relation for
the same symbol must agree; conflicting relations are rejected.

## Restricted formula grammar

```text
expression := sum
sum        := product (('+' | '-') product)*
product    := power (('*' | '/') power)*
power      := atom ('^' power)?
atom       := number | x | ('+'|'-') atom | '(' expression ')'
           | (log|log10|exp|sqrt) '(' expression ')'
```

Numbers accept decimal dot and scientific notation. Formulas must
contain `x`. Both Tcl validation and Octave numerical evaluation parse
this grammar without `eval`, shell execution, arbitrary functions, or
code interpolation. Formula domain restrictions remain the author's
responsibility; specify both inverse directions explicitly.

## Octave API and renderer

```octave
gxtxt_unit_parse(symbol)
gxtxt_unit_compatible(from_unit,to_unit)
gxtxt_unit_convert(values,from_unit,to_unit)
gxtxt_unit_formula_eval(formula,x)
gxtxt_plot_display_scale(values,source_unit,mode)
```

The framework sets `GXTXT_UNIT_REGISTRY_FILE` when running or rerendering
standard modules. The file is a derived session view of active plugin
definitions and per-variable custom relations. Consumers call the public
helpers; they do not parse registry internals. The generic CORE plot
metadata now computes both scale and offset for affine conversions.
Auto display retains opaque/custom units; explicit display conversion
requires a declared relation or compatible intrinsic dimensions.

## CORE elapsed-duration scale definitions (v0.9.7.60)

Elapsed Time Requested-Unit API v1 keeps canonical elapsed-time values in
seconds and uses this registry for explicit consumer conversions. Existing
intrinsic `s`, `min`, `h`, and `day` behavior is preserved. CORE additionally
registers these exact scale relations to `s`:

```text
a   = 31557600 s          Julian year, exactly 365.25 days
ka  = 31557600000 s       1000 Julian years
Ma  = 31557600000000 s    1000000 Julian years
```

`a` is deliberately the Julian-year symbol. No ambiguous generic `year` is
registered. Normal `standard_octave` jobs receive these definitions in the
derived Unit Registry runtime file, so `gxtxt_unit_convert` and the semantic
`gxtxt_elapsed_time_convert` wrapper use the same authoritative relations.

A definition is independent of Semantic role. A suggested semantic unit
is a hint, never a constraint.

## Octave Script Bridge

Bridge API ID: `UNIT_REGISTRY_API_v1`.

| Operation | Positional `args` | Result |
|---|---|---|
| `list` | `{}` | Cell of registered unit symbols. |
| `definition` | `{symbol}` | Registered unit definition struct. |
| `compatible` | `{source_unit, target_unit}` | Logical scalar. |
| `convert` | `{numeric_scalar_or_array, source_unit, target_unit}` | Converted numeric value with its original shape. |

`convert` delegates to the public CORE Octave unit converter, including
intrinsic dimension/prefix rules and registered formula definitions. It
reports incompatibility as an Octave error.

`unitRegistryConversionPlan source target ?source_override?` accepts an optional
variable-specific `{canonical_unit, to_canonical, from_canonical}` dictionary.
All three fields are required together and formulas use the normal validated
Unit Registry grammar. The descriptor records the effective override without
mutating global unit definitions. Dataset Transform applies this calibration
before the explicit compatible target conversion. Script `conversion_plan`
accepts the same optional third argument.
## Existing symbol-validation operations used by exact publication

`unitRegistryList` lists available registered units, including intentionally opaque
scientific labels. `unitRegistryIntrinsicScale symbol` validates an unregistered
intrinsic/composite unit expression through the existing CORE unit parser and
returns its scale; unknown or semantic-only expressions reject. Registered opaque
units do not require intrinsic interpretation. `unitRegistryConversionPlan a b`
validates explicit conversion relations; identity conversion alone does not prove
that an unregistered symbol is understood. Exact Curve Dataset publication reuses
these existing operations before staging, preserving supported opaque labels and
rejecting unsupported expressions without a private unit parser or new authority.
