# Unit Selector API v1

SPDX-License-Identifier: GPL-3.0-or-later

**Introduced:** GX-TXT Pipeline v0.9.3.3  
**API version:** 1 (additively extended in GX-TXT v0.9.7.1)

## Purpose

`type=unit` is a framework-owned, descriptor-driven display-unit selector. It never changes canonical Dataset values. The framework resolves the selected variable's source unit from Dataset/Analysis Source metadata, presents only dimensionally compatible choices, persists the selected mode in Manifest Format 2 and exports resolved metadata to `runtime.ini`.

## Descriptor syntax

Preferred form, tied to a normal module binding:

```ini
[config.x_display_unit]
type=unit
label=X display unit
binding=x
default=auto
required=0
```

The `binding=` value names a `[bindings]` role. The binding may resolve to an unqualified primary variable or `source.variable`.

Alternative forms are available for generic orchestrators:

```ini
source=primary
variable_config=x_variable
```

or a fixed canonical variable:

```ini
source=primary
variable=time_s
```

Resolution priority is `binding`, then `variable_config`, then `variable`.

## Values

- `auto`: framework display scaling.
- `source`: keep the canonical/source unit.
- an explicit dimensionally compatible display unit.

For time, the standard choices include `ns`, `us`, `ms`, `s`, `min`, `h`, `day`. SI-prefixed compatible choices are offered for supported dimensions such as current, voltage, frequency, capacitance (`pF` through `F`), inductance (`nH` through `H`), power, energy, length and mass. Farads and henries use the same intrinsic dimension rules as Numeric expressions; circuit values are stored in base SI units.

GX-TXT v0.9.7.1 also recognizes the semantic level units `FS`, `dB` and `dBFS`. They are offered only when the source metadata already use the same semantic unit. The selector never offers or performs implicit `FS -> dBFS`, `dB -> dBFS`, or dimensionless-to-full-scale conversion.

A runtime request such as `A -> V` is rejected. Unknown source unit metadata does not authorize conversion; the selector can still preserve `source`/`auto`, but a plugin should publish valid unit metadata for scientific use.

## GUI

The standard module config frame renders `type=unit` as a read-only combobox. Choices are refreshed from the current canonical Dataset binding when the control is opened. Plugins must not maintain private unit tables.

## Manifest

The selected value is stored through the normal module configuration persistence. GX-TXT also declares:

```ini
[unit_selector_api]
version=1
```

## Runtime

For each `type=unit` field:

```ini
[unit_selector.x_display_unit]
api_version=1
mode=h
source_role=primary
dataset_id=reactor.current.complete
variable=time_s
unit=s
semantic_role=time
```

Consumers should use `mode` for presentation and `unit` as the canonical source unit. The Dataset is never rewritten.

## Plot-axis relationship

Common Axes/Grid controls use the same Unit/Dimension compatibility rules for X, Y-left, Y-right, Z and C/color. Their values are transported in `[axis.<graph-id>]` as `x_unit`, `y_unit`, `y2_unit`, `z_unit` and `color_unit`.

## Compatibility

Existing string/config fields and historical `time_unit` remain valid. `none` is accepted by the Octave display helper as the historical synonym for source/no conversion, but new descriptors should use `source`.

## v0.9.7.3 semantic metadata units

`ppm` and `pH` are accepted as identity-only semantic units, like the existing level units. The framework does not infer concentration references or logarithmic pH conversions.
