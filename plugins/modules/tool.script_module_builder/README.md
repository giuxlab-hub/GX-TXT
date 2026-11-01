# Script Module Builder 1.1.0

Official GX-TXT Modules-page tool for packaging exact GNU Octave `.m` and Python `.py` research scripts as ordinary Analysis modules.

The Builder reads `GX-TXT-ANALYSIS-SOURCES-V1` comments statically, displays the declared sources, and emits the normal Analysis Source Map descriptor. Conflicting manual source settings require an explicit choice.

Open **Modules → Script Module Builder…**, or run `python3 tools/gxtxt_module_builder.py gui` from the framework root. The command-line `validate` and `build` actions use the same builder implementation.

See [MANUAL.md](MANUAL.md) and [the researcher guide](../../../docs/help/script_module_builder.md).

Version 1.2.0 adds optional public Experiment Duplication Policy authoring. See MANUAL.md. Requires policy v1 capability (earliest known dev079); legacy modules do not require adoption.

Whole registered Python/Octave Projects now retain their saved relative main and
all helpers. Source files/Public APIs pages show automatic CORE static PROVIDED
operations separately from CONSUMED requirements; primary menus route source
edits to the existing language Workspace and run asynchronous Validate/Build.
The exact operation manifest and typed source-derived declarations are packaged
for the normal managed function runtime. See MANUAL.md for stale-source, draft,
capability and cancellation boundaries; this tool does not install or grant APIs.
