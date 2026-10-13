# Graph Metadata API v1

Available in GX-TXT 0.9.8.10-dev-051 as a headless CORE service. It stores user/scientific descriptive metadata independently of rendered `.gxtxt_plotmeta` geometry, PlotSpec, graph presentation, Dataset metadata and Markdown notes.

Use the provider/Variant/Clone reference contract in [Graph Notes API](GRAPH_NOTES_API_v1.md).

```tcl
::GX::graphMetadataInfo $ref
set metadata [::GX::graphMetadataRead $ref]
::GX::graphMetadataWrite $ref [dict create experimental.sample silver processing.method fft]
::GX::graphMetadataUpdate $ref [dict create validation.reviewer operator]
::GX::graphMetadataUnset $ref {validation.reviewer}
```

`write` replaces the dictionary; `update` merges keys; `unset` removes named keys. Keys follow Dataset Metadata API's restricted namespaced-key rules, values are single-line UTF-8 strings. Unknown namespaced keys survive. Invalid keys, multiline values, unknown graph identities and invalid Clone IDs fail before replacement. Empty metadata is allowed. Writes use atomic file replacement and synchronize the normal Manifest association.

Files are `metadata/graphs/<module>/<graph>/base/metadata.ini`, `.../variants/<variant>/metadata.ini`, or `metadata/graphs/clones/<clone>/metadata.ini`. The `[metadata]` dictionary is authoritative; `[graph_metadata]` records resource version/kind. Manifest `[graph_metadata]` / `[graph_metadata.N]` associates identity with the Session-relative file. Callers never edit those files directly. Graph Info displays the dictionary. Creating/duplicating a Variant or Clone copies it independently; deletion removes only the selected identity's resource.

Octave and Python Script Bridge expose `info`, `read`, `write`, `update`, `unset`; require `GRAPH_METADATA_API_v1@1:graph_metadata`. Arguments are the reference struct and a metadata struct or key list. No arbitrary destination path is accepted. Portable Graph ZIP export/import preserves the dictionary as transport JSON, then restores the normal Session INI authority. See [Portable Resource API](PORTABLE_RESOURCE_API_v1.md).
