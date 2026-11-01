# Future CORE extraction boundary

This package deliberately keeps all new text-specific behavior inside the
plugin. The GX-TXT 0.9.8.10-dev integration adds one generic
`session_path` field to the existing Acquisition Handler Dataset preview
request; it does not rename, override or add dispatch branches to CORE.
No private Dataset registry or metadata sidecar format is introduced.

## Components

| Component | Responsibility | Framework dependence |
|---|---|---|
| `portable/languages.json` | Versioned language IDs, suffixes, special filenames, interpreter aliases and ambiguity groups. | None. |
| `portable/text_probe.py` | Bounded recognition, encoding detection, language hints, full streaming text validation, exact newline counts and safe preview text. | None. Uses Python standard library. |
| `runtime/text_worker.py` | Exact-byte output in caller-owned staging; portable result → namespaced metadata and Dataset contract; process protocol. | Knows metadata names/contracts, not Session storage or Registry implementation. |
| `runtime/acquisition_handler.tcl` | Public Acquisition Handler API v1 callbacks; framework Python lookup; cooperative worker orchestration and public Dataset Metadata/Session Inspection read for preview. | GX-TXT adapter. |
| `module.ini` | Installer/discovery declarations, common import settings, `document.text` and `code.source` contracts. | Public descriptor API. |

`portable/` is the primary extraction unit. Language-table entries never refer
to a framework release, plugin version, specific filesystem location, viewer or
Session generator. Content signatures are small and isolated in
`content_hint`; their assumptions are explained in comments.

## Portable call

```python
from text_probe import analyze_file

result = analyze_file(
    source_path,
    original_name="analysis.py",  # Important if the RAW snapshot was renamed.
    encoding="auto",
    language="auto",
    full=True,
)
```

`full=False` bounds inspection to 256 KiB. `result.complete` and
`result.bytes_scanned` prevent a partial scan being mistaken for a full-file
validation. Full import must use `full=True`.

Optional callbacks are `progress(current_bytes, total_bytes, stage)`,
`cancel() -> bool` and `on_chunk(original_bytes)`. `on_chunk` supports streaming
preservation of exactly the bytes being inspected. The caller owns the output
file and must discard it when validation or cancellation raises an exception.
The portable layer never invents output destinations or touches Dataset state.

The result is a plain Python dictionary containing filename/size, encoding and
its source, BOM, scan scope, language and its evidence/confidence/candidates,
line/character/newline statistics, a bounded read-only preview and warnings.
It has no Tcl dict, UI widget, module ID, Dataset ID or Session path.

## Proposed migration

Move `portable/` into a generic text-inspection service, preserving its result
contract and tests. Centralize the namespaced metadata mapping in
`runtime/text_worker.py` only if CORE is also taking ownership of that public
text-Dataset schema. The Tcl acquisition adapter can then call the new service
instead of `_launch`; its ordinary import callbacks remain responsible for
returning descriptors, not registering Datasets directly.

Move the two contract descriptions from `module.ini` into a generic registry
only as part of that separate change. Preserve their current IDs and the
`code.source → document.text` relationship. There is no `table.generic` parent.

Saved Datasets already use public Dataset Metadata API v1. They require no
private-file migration: original names, encoding, language and all counts are
ordinary namespaced metadata; source bytes and RAW/Registry hashes remain
managed by the framework. Importer-specific metadata is descriptive, not a
prerequisite for storing or retaining the file after plugin uninstall.

## Existing CORE limits found in this baseline

1. Source `inspect_proc` now receives descriptor `config` in GX-TXT
   0.9.8.10-dev. Source Preview and import apply the same current overrides,
   without reading private configuration state.
2. The final shared Preview binary guard intercepts NUL-containing inputs
   (including UTF-16/32) and long files with no early newline. Such inputs receive
   CORE's safe metadata preview rather than the plugin's decoded source snippet.
   Import and persistent metadata are independent of that guard. No bypass is
   installed. A future generic improvement would let the appropriate text
   provider return a safe decoded preview after source classification.

These notes are migration guidance, not required CORE edits for this plugin.
