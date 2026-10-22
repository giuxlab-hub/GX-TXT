# Portable Resource API v1

These operations are headless host/plugin APIs. They are intentionally absent from Script Bridge: filesystem import/export does not have a script-safe destination policy.

```tcl
::GX::portableResourceValidate $archive
::GX::portableResourceInspect $archive
::GX::portableResourceExportDataset $datasetId $archive
::GX::portableResourceExportGraph $graphRef $archive
set imported [::GX::portableResourceImport $archive $options]
```

A source or target Session must be open. Graph export accepts a stable provider/Variant/Clone reference as described by Graph Notes API; a current Session PNG path is also accepted for host compatibility. Dataset export writes `*.gxtxt-dataset.zip`; Graph export writes `*.gxtxt-graph.zip`. The suffix is appended when the chosen path lacks `.zip`. An existing archive is never overwritten. A common resource `.zip` is identified by its manifest.

Import options are `dataset_id` for an explicitly renamed Dataset, or boolean `rendered_only` for a Graph. Unknown, malformed or wrong-resource options are errors. Default Dataset/dependency collision policy is error. No replace-existing operation exists. Variable IDs survive Dataset rename; Dataset-scoped self references are mapped, unrelated resources are untouched. Results include resource type, source/imported identity, ID mapping, archive SHA-256, integrity, package information, graph capture mode, imported dependencies and warnings. Validation/inspection also returns source version, resource identity, contract/provider, dependency IDs/count, variable IDs, file count, total bytes and role hashes.

## Transport JSON and files

The root file is `gxtxt-resource-package.json`, with `schema=GXTXT_PORTABLE_RESOURCE_v1`, `schema_version=1`, `resource_type=dataset|graph`, source GX-TXT version, UTC creation time, source Session name, resource identity, `files[]`, `dependencies[]`, SHA-256 integrity algorithm, warnings and external acquisition dependency descriptions. Each file has a canonical relative POSIX path, declared role, size, SHA-256 and media type. Unknown additive manifest fields are ignored for reading; unsupported schema versions and unknown file roles are rejected. Reexport constructs a new transport manifest from restored GX-TXT authority, so arbitrary unknown transport fields are not retained as scientific metadata.

A Dataset contains `dataset/payload/canonical.<ext>`, `registry.json`, `schema.json`, optional `metadata.json`, `notes.md`, and `schema_source/<snapshot>`. Payload bytes and storage format are unchanged, including CSV, HDF5 and opaque image/PDF/audio/mesh/CAD/chemistry files. Registry/schema preserve stable Variable IDs, enabled state, source column/header, canonical position/name, units, roles, kinds, formats, decimal/time semantics, labels, conversion formulas, dtype/rank/shape/dimensions/coordinates/components/groups and intrinsic provider locators needed to read the payload. Intrinsic HDF5 dataset paths are transport reconstruction details; they are not Variable identity. Machine-local raw paths and live provider handles are excluded. Raw acquisition sources are recorded descriptively and are not recursively embedded.

A schema-source snapshot is retained with its SHA-256 so CSV Use=no/Use=yes edits remain reversible. Semantic/unit strings and Dataset-owned conversion relations survive missing defining plugins. Package content never registers a global semantic or unit provider. Import validates custom formulas with the normal restricted CORE formula rules. Structured namespaced metadata and Markdown notes are restored through their existing public APIs.

A Graph contains `graph/graph.png`, `graph-state.json`, optional notes/metadata/annotations/render metadata, a scientific snapshot when available, and explicitly declared embedded Dataset dependencies under `datasets/<id>/`. State records source identity/version, USE, title, axes and series. Plot Dataset scientific snapshots preserve prepared values and presentation without reading changed source data. Imported graphs become new Detached Clones, never overwrite/recreate the source base graph or Variant. Scientific import verifies the frozen snapshot by rendering it in staging, then commits its normal Clone resources. A rendered-only import keeps the exact PNG, notes, metadata and annotation layer and has no scientific rerender capability. The package's source JSON is retained as descriptive `portable_source.json`, not as a second live graph registry.

Graph Dataset dependencies use the same Dataset transport rules. Scientific import errors on a dependency ID collision. Explicit rendered-only import skips Dataset imports and can be used when source plugins are absent or dependencies collide. Imported Clones retain title/USE and ordinary independent note/metadata lifecycle. Static Plot Dataset and explicitly owned native Plot Dataset snapshots are supported scientific reconstruction providers; other providers retain rendered output.

`portableResourceInspect` retains `dependency_ids`/`dependency_count` for outer
Dataset dependencies adopted into the destination Session, with their existing
collision rules. Its additive `native_snapshot_dataset_ids` (semicolon-separated)
and `native_snapshot_dataset_count` describe the independently validated canonical
Dataset ZIPs retained inside a native scientific snapshot. Those frozen resources
belong to the Clone and do not adopt their IDs into the caller's registry. The
import dialog reports these two scopes separately; zero Session imports does
not mean that a native scientific snapshot contains no Dataset resources.

Native snapshots use `native_v4_snapshot.tcldict` and complete canonical Dataset ZIPs under `resources/<dataset-id>.zip`. The bounded manifest is parsed as inert Tcl lists and dictionaries, never sourced or evaluated. Dataset IDs, declared paths, nested package type and every SHA-256 must agree. Nested Graph packages and undeclared scientific files are rejected. Existing metadata `renderer_owner=PLOT_DATASET_API_v4` selects the public native reconstruction provider. A caller-requested rendered-only import removes that owner marker because the resulting Clone has no scientific rerender capability. Full native snapshot capture and validation remain owned by public Plot Dataset API v4; portable transport does not create another data store.

## GUI and security

Dataset workspace **Dataset ZIP...** offers **Export Dataset ZIP...** and **Import Dataset ZIP...**. Plots offers **Export Graph ZIP...** and **Import Graph ZIP...** in its scrollable toolbar. Before import, the dialog shows identity/type, source version/Session, contract/provider, total bytes/file count, integrity, embedded dependencies and collisions. Dataset import permits a caller-chosen new ID. Graph import explains new Clone mode and disables scientific import when prerequisites/collision policy prevent it.

The helper reuses Portable Session path, SHA and symlink rules. Complete declaration/integrity validation precedes staging and commit. Absolute, parent, noncanonical and duplicate paths, directories/symlinks, undeclared resources/dependencies, unsupported schemas, corrupt JSON/payload and mismatched sizes/hashes are rejected. Limits are 10,000 entries, 4 GiB total uncompressed data, 2 GiB per member, 200:1 compression ratio for members over 1 MiB, a 2 MiB manifest, bounded resource JSON. HDF5 files are inspected without reading data and reject external links, external raw storage and external virtual sources. No archive code is sourced or executed. Private staging is deleted on failure; outer transactions restore registry/Manifest and remove imported payloads/resources.

| Package | Purpose |
| --- | --- |
| Portable Session ZIP | Whole Session backup/transfer into a new Session directory. |
| Portable Dataset ZIP | One Canonical Dataset with scientific schema/metadata/notes. |
| Portable Graph ZIP | One graph with presentation/resources and declared Dataset dependencies. |
| Plugin ZIP | Executable/installable plugin package. |
| HTML ZIP | Read-only presentation that cannot be imported as scientific Session state. |

See [Portable Session API](PORTABLE_SESSION_API_v1.md) and the [user guide](../guides/PORTABLE_RESOURCE_EXPORT_IMPORT.md).
