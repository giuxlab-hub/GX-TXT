# Elapsed Time Requested-Unit API v1

**Introduced:** GX-TXT Pipeline v0.9.7.60  
**API version:** 1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

The public [Elapsed Time Contract v1](ELAPSED_TIME_CONTRACT_v1.md) defines the numeric CORE boundary for:

```text
value_kind = elapsed_time
```

as canonical elapsed **seconds**. Elapsed Time Requested-Unit API v1 adds an explicit consumer view on top of that invariant:

```text
source representation
        ↓
CORE parsing
        ↓
canonical numeric elapsed-time value
        ↓
seconds
        ↓
optional requested-unit conversion
```

The conversion never reparses the source text and never uses Dataset `source_unit` as its input unit. It always converts **from canonical seconds**.

If no target unit is requested, the result remains seconds.

## Public units

The required CORE target units are registered in Unit Registry API v1:

| Registry symbol | Meaning | Exact relation to seconds |
|---|---|---:|
| `s` | second | `1 s` |
| `min` | minute | `60 s` |
| `h` | hour | `3600 s` |
| `day` | day | `86400 s` |
| `a` | Julian year | `31557600 s` |
| `ka` | kiloannum, 1000 Julian years | `31557600000 s` |
| `Ma` | megaannum, 1000000 Julian years | `31557600000000 s` |

The symbol `a` is explicitly defined as the **Julian year**, exactly 365.25 days. `ka` and `Ma` are exact decimal multiples of that definition.

GX-TXT does **not** register a generic `year`, `yr`, or calendar-year unit in this API. A calendar year is not a fixed elapsed duration and must not be silently substituted for the Julian year.

## Tcl CORE API

Location:

```text
core/tcl/elapsed_time_requested_unit_api_v1.tcl
```

Public helpers:

```tcl
::GX::elapsedTimeCanonicalUnit
::GX::elapsedTimeRequestedUnit targetUnit
::GX::elapsedTimeConvert values ?targetUnit?
```

Examples:

```tcl
::GX::elapsedTimeConvert 90
# -> 90.0

::GX::elapsedTimeConvert 90 min
# -> 1.5

::GX::elapsedTimeConvert 5400 h
# -> 1.5

::GX::elapsedTimeConvert 31557600 a
# -> 1.0

::GX::elapsedTimeConvert {0 60 90 3600} min
# -> 0.0 1.0 1.5 60.0
```

`elapsedTimeRequestedUnit` normalizes a missing target to `s`, verifies that the target is an active Unit Registry resource, and rejects units that are not physically compatible with seconds.

The Tcl converter accepts the intrinsic linear time units and registered linear scale relations. Affine or nonlinear relations are intentionally rejected for elapsed duration because an elapsed interval has no origin-dependent offset and must not acquire nonlinear semantics.

## Octave CORE API

Location:

```text
core/octave/units/gxtxt_elapsed_time_convert.m
```

Usage:

```octave
out = gxtxt_elapsed_time_convert(values);
out = gxtxt_elapsed_time_convert(values,target_unit);
[out,target_unit] = gxtxt_elapsed_time_convert(values,target_unit);
```

Examples:

```octave
gxtxt_elapsed_time_convert(90,'min')
% 1.5

gxtxt_elapsed_time_convert([0;60;90;3600],'min')
% [0;1;1.5;60]

gxtxt_elapsed_time_convert(31557600000000,'Ma')
% 1
```

The helper preserves the normal Octave array shape and double-precision behavior. It validates compatibility with `s` and delegates numeric conversion to the existing public Unit Registry / Unit Dimension helper:

```octave
gxtxt_unit_convert(values,'s',target_unit)
```

No module should reproduce `/60`, `/3600`, `/86400`, Julian-year factors, or geological-scale factors privately.

## Standard Octave runtime

Normal `standard_octave` jobs already receive the derived Unit Registry through:

```text
GXTXT_UNIT_REGISTRY_FILE
```

Unit Registry API v1 writes the CORE `a`, `ka`, and `Ma` definitions into that derived runtime resource. The requested-unit helper reads those definitions through the existing public registry binding; modules do not open or parse the registry file directly.

The runtime file is derived state. The authoritative physical definitions remain CORE Unit Registry definitions.

## Source unit and requested unit are different

Dataset Variable Schema may preserve a source declaration such as:

```text
value_kind = elapsed_time
value_format = hms
unit = h
```

For the source text:

```text
01:00:00
```

CORE parsing produces:

```text
3600
```

and that numeric value means 3600 seconds. A request for minutes is therefore:

```text
3600 canonical seconds
        ↓ requested unit min
60
```

It is **not**:

```text
3600 interpreted again as source hours
```

The requested-unit API has no `source_unit` argument by design. This prevents the double-conversion class corrected when the elapsed-time contract was formalized in 0.9.7.59.

## Dataset immutability

Requested-unit conversion is a consumer view only. It does not change:

- canonical Dataset values;
- Dataset Variable Schema;
- `source_unit` / `unit` metadata;
- stored CSV/HDF5 data;
- Dataset Selection;
- Temporal Set definitions;
- Analysis Source bindings.

Consumers that make no requested-unit call continue to receive canonical seconds.

## Temporal Set API relationship

Temporal Set API v1 continues to resolve `value_kind=elapsed_time` from canonical seconds. Presentation or consumer target units do not participate in internal row/window resolution.

An explicit Temporal Set generator `duration_unit` remains an input-unit declaration for that generator and is converted to the temporal axis unit by the existing Temporal Set logic. The new requested-unit API does not change persisted Temporal Set semantics.

## Errors

A missing requested unit is valid and means `s`.

Unknown targets fail explicitly. Examples include unregistered `year` and arbitrary symbols.

Known but incompatible physical units also fail explicitly, for example:

```text
V
m
A
```

The API never falls back to seconds after an invalid explicit request.

## Precision

Conversions use GX-TXT's normal double-precision numeric behavior. Tests should use tolerance-based comparisons where binary floating-point representation makes exact equality inappropriate, especially for fractional or geological-scale values.
