# Core

Framework-owned code only. Scientific modules belong under `plugins/`.

- `tcl/`: Module API implementation, Scientific Analysis Definition discovery/runtime transport, Plugin Progress API transport/UI bridge, and standard execution wrappers.
- `native2d/`: portable C99 scientific curve and point geometry model, with renderer-independent IDs, layers, selection, transforms, snapping and lightweight constraints. See its `gx2d.h` and `README.md`.
- `octave/analysis/`: Scientific Analysis Definition API v1 generic executor and reusable operations.
- `octave/graphics/`: shared plot/legend/axes/rendering infrastructure.
- `octave/io/`: reusable readers/parsers, including shared INI/CSV-table, parameter-set and model-domain readers.
- `octave/util/`: reusable validation/classification helpers and public Octave Progress API helpers.
- `octave/legacy/`: retained compatibility helpers that are not discoverable plugins.
- `SCRIPT_ANALYSIS_SOURCES_API_v1.md`: static Python/Octave script declaration for normal Analysis Source Map Dataset selection; `python/script_source_declaration_v1.py` validates it without executing researcher code.

The core must not contain domain-specific scientific policy. New generic operations belong here only when they are reusable across independent plugins/problems.
