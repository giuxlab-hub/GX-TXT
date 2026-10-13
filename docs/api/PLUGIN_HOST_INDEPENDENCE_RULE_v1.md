# GX-TXT Plugin Host-Independence Rule v1

SPDX-License-Identifier: GPL-3.0-or-later

## Rule

Scientific and acquisition plugins must not depend directly on Tcl/Tk or on the GX-TXT desktop host implementation. All interaction with the host must use documented GX-TXT public APIs, descriptors and runtime contracts.

This is an architectural rule intended to preserve transportability to other hosts, including GiuxLab-Calc.

## Plugins SHOULD use

- Standard Module descriptors (`module.ini`);
- Analysis Source Map / Metadata runtime;
- Dataset Registry and Dataset Publication API;
- Acquisition Handler API;
- Preview Descriptor API;
- Contract Registry;
- Unit/Dimension API;
- Selection APIs;
- Repeatable Config / Model resources;
- Progress API;
- Graph Provider / scientific plot APIs;
- Computed Data Annotation API;
- framework-provided runtime/output/session paths.

## Production plugin code MUST NOT require

- `package require Tk` / `Ttk`;
- direct `ttk::` widget construction;
- `tk_messageBox`, `tk_getOpenFile`, `winfo` or other GUI calls;
- `grid`, `pack` or `place` for plugin-owned application UI;
- sourcing or modifying `gxtxt_pipeline.tcl` internals;
- hard-coded desktop/session paths as a substitute for public runtime APIs.

Tcl itself is not forbidden. Acquisition handlers may be implemented in Tcl as long as they remain host-independent and do not call Tk.

Tests may use Tk to verify the desktop host implementation; tests are not production plugin dependencies.

Optional desktop adapters may live under a plugin's `ui/` directory when they
are loaded only by an explicit GUI call. The public/headless API entrypoint
must not source them during discovery, validation, rendering or rerendering.
Such an adapter does not extend or patch private CORE GUI procedures. The
conformance checker excludes `ui/` but continues to scan all runtime/API
sources; a GUI adapter must be tested separately under a desktop host.

## Conformance checker

GX-TXT v0.9.5 ships:

```bash
tools/check_plugin_host_independence.py plugins/modules/<plugin-id>
```

The checker catches common direct Tcl/Tk dependencies in production Tcl files. It is a conformance aid, not a security sandbox and not a substitute for architectural review.

CORE/official plugins are expected to pass this checker. Third-party plugins may still install, but direct host dependencies are considered non-portable.
