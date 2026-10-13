# Implementation references

The authoritative integration baseline is the supplied GX-TXT 0.9.8.09 source
archive, especially:

- `docs/api/ACQUISITION_HANDLER_PLUGIN_API_v1.md`
- `docs/api/ACQUISITION_HANDLER_CAPABILITIES_v1.md`
- `docs/api/DATASET_METADATA_API_v1.md`
- `docs/api/PREVIEW_DESCRIPTOR_API_v1.md`
- `docs/api/CONTRACT_REGISTRY_API_v1.md`
- `docs/api/PLUGIN_INSTALL_API_v1.md`

Python behavior is based on its standard library documentation:

- https://docs.python.org/3/library/tokenize.html#tokenize.detect_encoding
- https://docs.python.org/3/library/codecs.html#incremental-encoding-and-decoding
- https://docs.python.org/3/using/cmdline.html#cmdoption-I
- https://docs.python.org/3/using/cmdline.html#cmdoption-B

`tokenize.detect_encoding` reads the first two lines for the Python encoding
cookie/BOM; it does not execute or syntax-validate a program. Incremental
strict decoding validates bytes across chunk boundaries without replacement.
The worker runs in Python isolated mode and disables `.pyc` writing.

Language heuristics are intentionally plugin policy, not an implementation of
all language specifications. The catalog gives hints; extensions such as `.m`
and `.h` are not proof of a unique language. This importer does not claim that
a recognized program is syntactically valid or safe to execute.
