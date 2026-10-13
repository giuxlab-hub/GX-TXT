# GX-TXT Instrument Module API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Instrument modules describe **instrument metadata schemas**, not acquisition algorithms and not real hardware instances. Nothing is inserted into an experiment automatically.

An installed instrument module lives at:

```text
plugins/instruments/<stable-id>/instrument.ini
```

The user explicitly loads a module from **Session → Instrumentation → Instruments → Add Instrument…**. Loading it creates one editable instrument instance in the experiment manifest.

## Descriptor

Minimum descriptor:

```ini
[meta]
api_version=1
id=instrument.generic
name=Generic laboratory instrument
version=1
group=Laboratory instruments
description=...

[fields]
ids=type;role;manufacturer;model;serial;firmware;notes

[field.manufacturer]
type=string
label=Manufacturer
default=

[field.notes]
type=multiline
label=Instrument notes
default=
```

Supported field types in v1 are `string`, `choice`, and `multiline`.

## Instance identity

Every loaded instance has framework fields independent of the descriptor:

- `enabled`
- `module_id`
- `id` — stable experiment-local identifier used by Variables
- `display_name`

Descriptor fields are stored as `field.<name>`.

Example:

```ini
[instrument_module_instance.1]
enabled=1
module_id=instrument.oscilloscope
id=scope_main
display_name=Bench oscilloscope
field.role=Acquisition
field.manufacturer=Rigol
field.model=DS1104Z-S
field.serial=
field.firmware=
field.bandwidth=100 MHz
field.sample_rate=
field.memory_depth=
field.coupling=
field.notes=Used with short ground spring.
```

## Relationship with Variables

A canonical variable may refer to an instrument instance and channel:

```ini
[source_variable.1]
canonical=Va_V
instrument_id=scope_main
instrument_channel=CH1
```

The instrument module does not decide which variable a scientific analysis consumes. Analysis modules declare input roles through the Standard Module API and the framework resolves/binds canonical variables separately.

## Rules

1. No instrument instance is predefined.
2. Loading a module is explicit user action.
3. Instrument descriptors contain schema/defaults only; they do not claim an actual device was used.
4. Acquisition modules and instrument modules are independent. `acq.rigol_csv`, for example, can import a Rigol-format file without silently inventing a Rigol instrument instance.
5. Stable instance IDs are the only link used by Variables.
6. Future instrument-specific modules may add metadata fields without changing the core GUI or manifest parser.

## Session GUI host (dev081)

Instrumentation is a Session navigator section. Its left browser lists Session
instances; selection maps the original descriptor-driven configuration/editor into
the right canvas. Enable/disable, stable IDs, metadata fields and instrument notes
use the same variables, widgets and callbacks. The former top-level Instrumentation
tab is removed, while its real `.top.nb.instr` host and editor widget identities are
retained. No descriptor, instance, scientific binding or Manifest schema changes.

Section/instrument/Library view changes preserve unsaved configuration and notes.
Leaving the Session offers Save, Discard or Cancel for instrument edits. Saving uses
the existing Session and notes services; it does not introduce another store. Notes
windows close on an actual Session change or instance renumbering so stale callbacks
cannot update a different instrument. Headless Instrument APIs remain compatible.
