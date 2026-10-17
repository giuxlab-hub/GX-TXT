# Unit Registry API v1

`unitRegistryConversionPlan source_unit target_unit` returns the exact public
conversion descriptor: source/target definitions, source-to-canonical expression,
intrinsic base scale ratio and target-from-canonical expression. It reuses CORE's
prefix/base/dimension authority; consumers do not maintain another unit table.
Incompatible or semantic identity-only conversions reject the request. The same
descriptor is available to both Script Bridge languages as `conversion_plan`.
Dataset Transform persists and applies this descriptor only on explicit request.

`unitRegistryAffinePlan source target ?source_override?` (Script Bridge:
`affine_plan`) adds an `affine` boolean to this descriptor. When the registered
formula syntax establishes an affine coordinate relation algebraically, it also
returns finite `scale` and `offset` such that `target = scale * source + offset`.
It supports intrinsic prefixes, affine units and declared affine formulas,
including variable-specific relations. It never infers linearity by sampling.
Unsupported/nonlinear expressions return `affine=false` with a reason and no
coefficients; callers must use pointwise conversion. Invalid domains, incompatible
dimensions, nonfinite coefficients and a collapsed coordinate dimension reject.
Identity conversions preserve even opaque units without a guessed relation.
The classification is conservative and expresses the mathematical relation;
floating-point evaluation order can differ from pointwise conversion. It does
not establish that an arbitrary input value is finite or within a formula's
representable numerical range. Coordinate consumers must validate their data.

`unitFormulaProgram formula` (Script Bridge: `formula_program`) returns the
registered parser's arithmetic tree in `program_version=1`, `tree=<node>`.
A node is a list: `x`, `number <finite binary64 constant>`, or an operation with
one/two child nodes. Operations follow the restricted grammar below; unary signs
are `unary+`/`unary-`. Programs are bounded to depth 64 and 4096 nodes. Both Script
languages receive nested cells/lists with the same operation/operand order.
CORE bulk consumers use `core/python/gxtxt_unit_program_v1.py` to decode and
compile this program once. Dataset Transform consumes that parsed program
with the canonical unary/power precedence. The canonical grammar is unchanged:
`-x^2` means `(-x)^2`; use `-(x^2)` to negate the square, and `x^2^3` means `x^(2^3)`.

SPDX-License-Identifier: GPL-3.0-or-later

Unit Registry API v1 is distinct from Semantic Registry API v1. A unit is a
numeric or presentation symbol; a Semantic role identifies scientific meaning.

<a id="audit-of-the-preexisting-unit-system"></a>
## Intrinsic units and opaque symbols

CORE Tcl uses `unitTclSingle`, `unitTclDimensionKey` and `unitTclCompatible`;
CORE Octave uses `gxtxt_unit_parse`, `gxtxt_unit_compatible` and
`gxtxt_unit_convert`. Both support base A/V/s/Hz/Ohm/W/J/K/mol/m/g, SI prefixes,
min/h/day and simple products, divisions and integer powers. The exact token
`1` is a neutral dimensionless factor, including reciprocal units such as
`1/s` and `1/ms`. For example, `1/ms` converts to Hz with scale 1000.
The original unit string is retained; parsing does not rename stored units.

Intrinsic conversion uses scale ratios of matching dimensions. Plot auto display
selects recognized time units or SI prefixes and retains unrecognized symbols.
Plugins and Variables can supply explicit persisted custom conversions.
FS, dB, dBFS, ppm and pH are identity-only units by default. All symbols support
identity conversion `foo -> foo`. There is no implicit ppm to mg/L or pH to
concentration relation.

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
metadata computes both scale and offset for affine conversions.
Auto display retains opaque/custom units; explicit display conversion
requires a declared relation or compatible intrinsic dimensions.

<a id="core-elapsed-duration-scale-definitions-v09760"></a>
## CORE elapsed-duration scale definitions

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

<a id="bounded-in-process-coordinate-conversion-integrated-dev097"></a>
## Bounded in-process coordinate conversion

`unitRegistryConvertValues source target values ?source_override?` converts at
most 4096 finite binary64 coordinate/control values in the calling Tcl process.
It uses `unitRegistryConversionPlan` and the existing registration grammar,
including intrinsic, affine and explicit nonlinear relations. An optional
per-variable override has the same three-field contract as `conversion_plan`.
The global registry and Dataset values are not modified. Source/target identity
without an override preserves the original finite binary64 values.

`unitFormulaEvaluate formula value` evaluates the same parsed arithmetic tree
used to validate registration. No script evaluation, string substitution or
external numerical process is used. The existing grammar treats unary signs as
atoms: `-x^2` means `(-x)^2`; exponentiation is right-associative. These semantics
match `gxtxt_unit_formula_eval` and are not replaced by another language's
operator precedence.

Inputs, formula intermediates and outputs must be finite and real. Domain
errors, overflowing conversions and integers not exactly representable in
binary64 are rejected. Empty input remains empty; negative zero is preserved.
Use the existing Dataset Transform/typed array surfaces for large scientific
arrays. The existing Script `convert` operation retains its established bulk
Octave behavior.

Both Script Bridge languages expose the additive operation:

```python
gxtxt_api_call('UNIT_REGISTRY_API_v1', 'convert_values',
               [values, 'Hz', 'kHz'])
```

The optional fourth argument is the variable-specific override. Scalar or
array shape follows the existing Bridge numeric conventions, and the bound is
checked before a binary resource is materialized. Complex and logical arrays
are rejected. This API supports scientific axis presentation; it does not
change the length-only semantics of `unitRegistryConvertCoordinates`.
<a id="declared-inverse-affine-planning-dev097"></a>
### Declared inverse affine planning

`unitRegistryAffinePlan source target ?sourceOverride? ?direction?` accepts
`forward` (default) or `inverse`. Script `affine_plan` has the same final optional
argument. Inverse classification uses the target's declared forward formula and
the source Variable's declared inverse formula; it does not assume reciprocal
coefficients. Results include `direction`, `input_unit`, `output_unit`, and the
existing `affine`, `scale`, `offset`, `reason` contract. A nonlinear declaration
remains non-affine. Formula authors must still declare a consistent inverse and
valid domain; classification cannot prove those physical claims.

## Differential units

`unitRegistryDifferentialRatioPlan numerator denominator ?target?` is the public
CORE owner for differential units. Python/Octave call `differential_ratio_plan`
on UNIT_REGISTRY_API_v1 with two or three arguments. The versioned
`gxtxt.differential_unit_plan.v1` result declares `status=value|unavailable`,
`output_unit`, `dimension_key`, an explanatory `reason` and the offset policy.
Only a value result has a finite nonzero `scale` and numerator/denominator/output
basis records. Each basis names its registered unit, canonical unit, dimensions,
scale and affine offset. Multiply a numerical differential ratio by `scale` to
express it in `output_unit`; for example V/mA to Ohm has scale 1000.

An omitted target uses CORE's canonical dimension product. Compatible prefixes
and registered affine conversions are supported. Affine offsets cancel only
for differentials: this plan must never convert absolute coordinate values.
Nonlinear conversions, unknown units, semantic units and incompatible requested
units return unavailable without an invented scale. No unit registry is modified.
String fields remain strings and scale/offset fields remain numeric in both
Script Bridge languages, independent of Tcl's internal object representation.


Canonical symbol `1` is explicitly registered by CORE as an intrinsic
dimensionless unit. Unit Selector, definition/list, compatible conversion and
Python/Octave bindings share that same registration. It is distinct from an
undeclared empty unit and does not permit conversion to a dimensioned quantity.

## Homogeneous Euclidean coordinate frames

`::GX::unitRegistryHomogeneousCoordinatePlan source target` validates a common
proportional coordinate frame. It reuses the registered dimension, intrinsic
scale and algebraic affine authorities. Known compatible non-length units such
as V/V, kg/kg and (m/s)/(m/s) are admitted. Explicit mV→V has scale0.001;
cm→mm has scale10. Incompatible dimensions, unknown/semantic/opaque bases,
nonlinear relations, nonzero affine origins and nonpositive scales are refused.
Identity conversion alone does not prove a valid Euclidean metric.

The `gxtxt.homogeneous_coordinate_plan.v1` record contains `source_unit`,
`target_unit`, `dimension_key`, finite positive `scale`, zero `offset` and a
`physical_length` boolean. Python and Octave discover the same
`homogeneous_coordinate_plan` operation on `UNIT_REGISTRY_API_v1` with two unit
arguments. This is admission/planning only; canonical values are not modified.
Existing bounded `convert_values` or explicit Dataset Transform operations apply
conversions. The existing physical `unitRegistryConvertCoordinates` contract
remains length-only for consumers that require real spatial dimensions.

Curve Workbench uses the plan for primitive/common working units and whole-frame
conversion. Mixed V/mA or kg/(m/s) scientific axes remain legitimate independent
coordinates but cannot become a Euclidean CAD metric. Formal measurements retain
their coordinate units: distance in V, area in V², and compound area in `(m/s)^2`.
These labels do not claim that a physical exporter accepts a non-length plane or
that every formal derived-unit expression has a registered conversion.
