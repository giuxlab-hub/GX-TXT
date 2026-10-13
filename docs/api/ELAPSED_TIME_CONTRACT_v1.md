# Elapsed Time Contract v1

**Formalized:** GX-TXT Pipeline v0.9.7.59  
**Scope:** public CORE semantic contract for `value_kind=elapsed_time`

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

GX-TXT treats elapsed time as a semantic value kind rather than as a formatting convention. A supported source representation is parsed once at the CORE boundary and exposed to numeric consumers using one stable base representation:

```text
value_kind = elapsed_time
        ↓
supported source representation
        ↓
CORE parsing
        ↓
numeric elapsed-time value
        ↓
seconds
```

The public default numeric unit is **seconds**. This is an invariant, not a display preference.

## Current supported textual representation

Dataset Variable Schema API v2 currently supports:

```text
value_kind=elapsed_time
value_format=hms
```

with serialized values of the form:

```text
HH:MM:SS
HH:MM:SS.fraction
HH:MM:SS,fraction
```

Hours may exceed 23. Minutes and seconds must remain in `00..59` before any fractional part.

Examples:

```text
00:00:00       -> 0
00:00:30       -> 30
00:10:00       -> 600
01:00:00       -> 3600
01:30:00.5     -> 5400.5
27:15:01       -> 98101
```

The numeric values above are seconds.

Invalid values continue to follow the existing typed-read behavior: they become `NaN` rather than being reinterpreted using a different time syntax.

## Source unit metadata

Existing Dataset Variable Schema records may declare a compatible source `unit` of `s`, `min`, or `h` for an HMS elapsed-time field. That declaration is preserved for compatibility, provenance and presentation metadata. It does **not** rescale the normalized numeric elapsed-time value.

Therefore these supported schemas:

```text
value_kind=elapsed_time, value_format=hms, unit=s
value_kind=elapsed_time, value_format=hms, unit=min
value_kind=elapsed_time, value_format=hms, unit=h
```

all map `00:01:30` to numeric `90` at the public numeric boundary.

This rule applies specifically to `value_kind=elapsed_time`. A normal numeric variable (`value_kind=number`) whose semantic role happens to be `elapsed_time` keeps its ordinary declared-unit numeric semantics.

## Parsing and unit conversion are separate concerns

Parsing answers:

```text
What physical elapsed duration does the serialized source value represent?
```

The answer is normalized to seconds.

Requested-unit conversion answers a separate question:

```text
In which compatible unit should a consumer receive or display that duration?
```

GX-TXT 0.9.7.60 adds [Elapsed Time Requested-Unit API v1](ELAPSED_TIME_REQUESTED_UNIT_API_v1.md) as an explicit layer above this contract. When no target unit is requested, the numeric elapsed-time representation remains seconds. Explicit conversion always starts from canonical seconds and delegates to the existing Unit Registry / Unit Dimension infrastructure.

Consumer modules must not add private HMS parsers, infer the original source text from the normalized number, or apply the preserved source-unit metadata a second time.

## Public data-access paths

The seconds invariant applies wherever CORE exposes parsed `value_kind=elapsed_time` numeric values, including:

- Canonical Dataset API v2 typed CSV reads;
- Table Stream API v3 through Canonical Dataset API v2;
- legacy Table Stream API v2 numeric views through `gxtxt_table_chunk_numeric`;
- Analysis Source data consumed through the standard runtime and Table Stream interfaces.

Runtime metadata may still expose the original Dataset schema fields (`unit`, `value_kind`, `value_format`, `time_reference`, `time_origin`). Those fields describe the source/schema semantics; they do not change the numeric elapsed-time base representation.

## Temporal Set API v1

Temporal Set API v1 uses the same invariant. For a variable with:

```text
value_kind=elapsed_time
value_format=hms
```

its `numeric_unit` / runtime `temporal_unit` is `s`. Duration-based window calculations therefore operate on seconds before any explicit compatible-unit conversion of the generator definition.

This guarantees that equal physical durations resolve to the same row/sample ranges regardless of whether the original HMS Dataset schema declared `s`, `min`, or `h`.

## Stability requirement for future importers

Future importers may add source time syntaxes, but every supported representation of the same physical elapsed duration must converge to the same numeric value in seconds before it reaches generic consumers.

Changing the implicit base unit would break Dataset Selection, Temporal Set resolution, plotting, analysis runtimes and future FFT/spectrogram consumers. Any future alternate-unit access must therefore be explicit and additive rather than changing this base contract.
