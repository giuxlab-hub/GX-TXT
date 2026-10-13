# Unit / Dimension API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.8.4  
**API version:** 1 (additively extended in GX-TXT v0.9.7.1)

## Scope

GX-TXT v0.8.4 adds a deliberately small unit/dimension layer for Scientific Analysis Definition API v1. Unit checking is opt-in so definitions written for v0.8.1-v0.8.3 remain unchanged.

Supported base symbols:

```text
A V s Hz Ohm W J K mol m g
```

`Ω` is accepted as `Ohm`, and `µ` as `u`.

Supported SI prefixes:

```text
p n u/µ m c d h da k M G
```

Simple products, divisions and integer powers are supported, for example:

```text
mA
V/A
V*A
m/s
s^-1
```


## Semantic level units (v0.9.7.1)

GX-TXT v0.9.7.1 recognizes these non-SI presentation/measurement metadata units:

```text
FS
dB
dBFS
```

They are deliberately **identity-preserved semantic units**, not affine/SI conversion targets:

- `FS` means a value already expressed relative to a declared full-scale reference;
- `dB` is a logarithmic ratio already expressed in decibels;
- `dBFS` is a logarithmic level already referenced to full scale.

The Unit/Dimension API does **not** invent or infer the missing scientific reference needed to convert between linear values and logarithmic levels. Therefore:

```text
dB   -> dB      allowed, identity
dBFS -> dBFS    allowed, identity
FS   -> FS      allowed, identity
dB   -> dBFS    rejected
FS   -> dBFS    rejected
1    -> FS      rejected
```

This is sufficient for generic plotting, annotations, Dataset metadata and unit selectors to carry these units without treating them as unknown. Conversion to or from a logarithmic representation remains the responsibility of the scientific module that owns the reference/normalization semantics.

`strict_units=1` arithmetic intentionally rejects semantic level units. They are not silently treated as ordinary dimensionless linear quantities.

## Public helpers

Location:

```text
core/octave/units/
```

Functions:

```octave
U = gxtxt_unit_parse(unit)
tf = gxtxt_unit_compatible(a,b)
out = gxtxt_unit_convert(value,from_unit,to_unit)
key = gxtxt_unit_dimension_key(unit)
```

## Strict expressions

An `expression` operation may request dimensional checking:

```ini
[operation.power]
type=expression
expression=voltage * current
strict_units=1
unit=W
output=power
```

When `strict_units=1`:

- every referenced numeric series must have unit metadata;
- `+`/`-` require compatible dimensions;
- `*` and `/` combine dimensions;
- `^` requires an integer literal exponent;
- if `unit=` is declared, the result is converted to that compatible unit;
- incompatible arithmetic is an execution error.

Without `strict_units=1`, units remain metadata as in earlier releases.

## Explicit conversion

```ini
[operation.current_A]
type=convert_unit
value=current_mA
from_unit=mA
to_unit=A
output=current_A
```

If `from_unit=` is omitted, the input series unit metadata is used. `to_unit=` may be supplied through the operation `unit=` field.

## Limitations

This is not a complete dimensional-analysis package. It intentionally does not parse arbitrary derived-unit names, affine units such as Celsius, or domain-specific concentration notation. `FS`, `dB` and `dBFS` are supported only as identity-preserved semantic units; GX-TXT does not infer reference levels or perform linear/logarithmic transforms. Use an explicit scientific module/operation when such a transform is required.

## v0.9.7.7 extensibility

Unit Registry API v1 adds lifecycle-aware plugin definitions, per-variable
custom relations and identity for unknown opaque symbols. The original
intrinsic SI parser remains available. Explicit scale, affine and restricted
formula conversions are handled by the same public `gxtxt_unit_convert`
helper when the framework supplies its derived runtime registry. See
`UNIT_REGISTRY_API_v1.md`.

## v0.9.7.60 elapsed-time requested-unit view

`value_kind=elapsed_time` has a stronger semantic contract than an ordinary numeric variable with a time-compatible unit: after source parsing, its canonical numeric representation is seconds. Consumers that want another temporal representation should call Elapsed Time Requested-Unit API v1 rather than selecting `from_unit` from Dataset source metadata.

The public Octave helper is:

```octave
out = gxtxt_elapsed_time_convert(values,target_unit)
```

It validates compatibility with `s` and delegates to `gxtxt_unit_convert(values,'s',target_unit)`. Unit Registry API v1 supplies the exact Julian-year (`a`), `ka`, and `Ma` scale definitions in normal `standard_octave` runtimes. See `ELAPSED_TIME_REQUESTED_UNIT_API_v1.md`.
