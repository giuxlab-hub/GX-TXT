# GX-TXT `analysis.octave_script`

SPDX-License-Identifier: GPL-3.0-or-later

`analysis.octave_script` is the advanced scripting module for researchers who need ad-hoc or evolving scientific calculations without first packaging a complete GX-TXT analysis plugin.

Version 1.3.0 combines the following functions:

1. **Octave Script Workspace Viewer** — an editor that saves normal `session:<id>` and `user:<id>` Script Registry records, and imports/exports GNU Octave `.m` source;
2. **Script Library and Session Script Explorer** — register, revise, inspect and run user scripts and physical Session-owned snapshots;
3. **Octave Script analysis runner** — selects `session:<script_id>` in normal Analysis and executes the exact verified Session-owned source through CORE Script Execution and `OCTAVE_SCRIPT_BRIDGE_API_v1`.

Open a Session, create an Octave script in the Workspace, choose **Session** scope and Save. It appears immediately in Script Library, Session Script Explorer and the normal Octave Analysis registered-script selector. Choose `session:<id>` and run. **User** scope saves a reusable Library script that can later be assigned to a Session. Legacy Workspace Interactive Documents remain readable and have explicit Register as Session/User actions. Script Library Run, Session Script Explorer Run and registered Analysis runs use CORE Script Execution with immutable per-run source snapshots and provenance. A separate `external_file` mode retains standalone `.m` compatibility.

The bridge is generic. This module does not contain Dataset-, plotting-, Publication-, Project-, CFD- or numerical-API adapters.

See:

- `MANUAL.md` — complete module manual;
- `MANUAL.html` — standalone HTML manual;
- `OCTAVE_SCRIPT_EDITOR_API_v1.md` — Viewer/editor persistence contract;
- `examples/` — bridge-oriented script templates;

