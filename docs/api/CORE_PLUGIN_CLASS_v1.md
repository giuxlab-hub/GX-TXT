# GX-TXT CORE Plugin Class v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

CORE is an explicit distribution/protection class for plugins that are part of the GX-TXT framework distribution. It is **not** a synonym for enabled, default-enabled, non-selectable, or scientifically privileged.

A module is designated CORE by the framework distribution with:

```ini
[meta]
core=1
```

## Semantics

- CORE plugins remain physically normal plugins and must use public GX-TXT APIs.
- CORE status is independent from `selectable` and `default_enabled`. A CORE analysis module may be shipped disabled by default and enabled only when needed.
- CORE plugins are distribution-protected and cannot be removed through Plugin Install API v1.
- The Modules catalog visibly reports `CORE / ON` or `CORE / OFF`.
- A non-selectable acquisition module is merely `ALWAYS` available unless it is separately declared `core=1`.
- CORE status does not relax Plugin Host Independence Rule v1.

## v0.9.6 designated CORE modules

- `plot.dataset`
- `analysis.fft_spectrum`

Additional plugins become CORE only when explicitly designated by the framework maintainer.

## v0.9.6.1 designated CORE modules

- `plot.dataset`
- `analysis.fft_spectrum`
- `acq.wav`
- `analysis.audio_decode`

All four remain normal host-independent plugins. The audio plugins are also disabled by default and protected from uninstall.


## v0.9.7 designated CORE modules

- `plot.dataset`
- `analysis.fft_spectrum`
- `acq.wav`
- `analysis.audio_decode`
- `acq.image_binary`

All remain normal host-independent plugins. `acq.image_binary` is disabled by default and protected from uninstall; it imports opaque binary raster-image datasets without moving image decoding into the framework.

## v0.9.7.1 designated CORE modules

- `plot.dataset`
- `analysis.fft_spectrum`
- `acq.wav`
- `analysis.audio_decode`
- `acq.image_binary`
- `acq.tektronix_current_log`

`acq.tektronix_current_log` changes distribution status from non-selectable `ALWAYS` to selectable protected `CORE / OFF`. It is not enabled by default; users enable it only when Tektronix current-log acquisition is needed.

## v0.9.7.2 designated CORE modules

In addition to the v0.9.7.1 list:

- `curvefit.family_global`
- `sequence.table_join`

Both remain normal host-independent plugins, selectable and disabled by default (`CORE / OFF`), and protected from uninstall. Their scientific implementations and public APIs are unchanged.


## v0.9.7.20 designated CORE module

In addition to the previous CORE set:

- `dataset.extract`

`dataset.extract` 1.2.0 remains a normal Standard Module, selectable and disabled by default (`CORE / OFF`). Its public API usage and scientific/runtime implementation are unchanged; CORE status makes it part of the GX-TXT distribution and protects it from uninstall.
