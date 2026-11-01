# CORE request — optional conditional activation for Standard Module fields

SPDX-License-Identifier: GPL-3.0-or-later

## Context

`dataset.extract` intentionally uses only Standard Module API fields and bindings. It must remain host-independent and must not add Tk hooks or private GUI code.

The desired UI logic is simple:

- `selection` is relevant only when `row_mode` is `selected` or `unselected`;
- `trace_x` and `trace_y` are relevant only when `column_mode=trace`.

Standard Module API v1 currently describes static fields/bindings and has no public conditional enable/visibility metadata. The module therefore labels conditional fields explicitly but cannot disable/hide them without violating host independence.

## Minimal generic extension

If CORE wants to support this before `dataset.extract` is absorbed, extend the existing Standard Module descriptor with an optional generic condition, for example:

```ini
[config.selection]
enabled_when=row_mode:selected|unselected

[binding.trace_x]
enabled_when=column_mode:trace

[binding.trace_y]
enabled_when=column_mode:trace
```

The exact syntax should follow existing CORE conventions. Requirements:

- purely presentation/preflight behavior;
- absent condition means current behavior;
- no module-specific knowledge in CORE;
- runtime semantics remain unchanged;
- hidden/disabled fields must not be treated as required;
- host-independent descriptor contract.

This is a presentation improvement, not a blocker for scientific correctness.
