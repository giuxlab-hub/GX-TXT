# Script Module Builder

Official GX-TXT Modules-page tool for packaging exact GNU Octave `.m` and Python `.py` research scripts as ordinary Analysis modules.

The Builder reads `GX-TXT-ANALYSIS-SOURCES-V1` comments statically, displays the declared sources, and emits the normal Analysis Source Map descriptor. Conflicting manual source settings require an explicit choice.

Open **Modules → Script Module Builder…**, or run `python3 tools/gxtxt_module_builder.py gui` from the framework root. The command-line `validate` and `build` actions use the same builder implementation.

See [MANUAL.md](MANUAL.md) and [the researcher guide](../../../docs/help/script_module_builder.md).

Optional public Experiment Duplication Policy authoring is available through the Builder. See [MANUAL.md](MANUAL.md). The capability requires the public policy v1 API; existing modules remain compatible without adopting it.
