# Text Document Import — Architecture and validation scope

The text-document acquisition module uses a portable Python text inspector and a thin GX-TXT acquisition adapter. File contents are interpreted as untrusted data; source bytes and provenance are preserved.

## Portable text inspection

`portable/languages.json` defines language IDs, filename suffixes, interpreter aliases and ambiguity groups. `portable/text_probe.py` provides bounded recognition, encoding detection, language suggestions, full text validation, exact newline counts and safe previews, without loading GX-TXT, Tcl/Tk or Dataset internals.

```python
from text_probe import analyze_file

result = analyze_file(
    source_path,
    original_name="analysis.py",
    encoding="auto",
    language="auto",
    full=True,
)
```

With `full=False`, inspection is bounded to 256 KiB. The `complete` and `bytes_scanned` fields identify the actual scan scope. Full import uses `full=True`. Optional `progress(current_bytes,total_bytes,stage)`, `cancel()` and `on_chunk(original_bytes)` callbacks support streamed exact-byte preservation and controlled cancellation.

The returned Python dictionary contains source filename/size, encoding/BOM, scan completeness, language evidence and candidates, line/newline statistics, read-only preview and warnings. It contains no GUI, private Registry, Session path or Dataset authority.

## GX-TXT acquisition integration

- `runtime/text_worker.py` translates the portable inspector result to namespaced metadata and public Dataset descriptors, producing output only in caller-provided staging.
- `runtime/acquisition_handler.tcl` supplies the Acquisition Handler callbacks, framework Python lookup, worker lifecycle and safe public Session/Dataset preview access.
- `module.ini` declares formats and contracts such as `document.text` and `code.source`.
- CORE owns Dataset registration, atomic publication, metadata schema validation and rollback. The inspector never invents filesystem output paths or accesses unrelated Sessions.

Metadata remain data, not executable code. No source/encoding decision can grant permission to execute the imported document.

See [the module README](../README.md) and manual for supported formats, encoding choices, preview semantics and limitations.
