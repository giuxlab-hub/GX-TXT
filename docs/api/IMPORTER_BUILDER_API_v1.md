# Importer Builder API v1

The Importer Builder stores declarative user definitions under the user's GX-TXT configuration directory in `importers/<id>.ini`. Each definition has a stable ID and version, a Dataset contract, matching rule, parser settings, column mappings, units, optional numeric scale/offset, and optional filename/header metadata capture. Definitions are editable and can be duplicated, exported, imported, and removed in the Acquisition editor.

The editor's **Preview source** shows the representative RAW file. **Test parser** runs the same bundled `acq.generic_csv` canonicalizer used by normal imports and shows up to twelve canonical rows. Definitions may use comma, semicolon, tab, auto, or whitespace separators; leading/header/footer rows; comments; encoding; and dot/comma decimal conventions. RAW files are copied into the Session and are never edited.

Selecting `builder.<id>` on Acquisition keeps `acq.generic_csv` as the underlying execution module. A queued row carries the builder identity in memory; the Session Dataset registry records `importer_definition`, `importer_version`, source/canonical hashes, source path, and extracted metadata. The queue itself is temporary and is excluded from the interactive Session manifest. Folder import uses the definition's filename matching rule. The existing generic CSV Dataset publication transaction handles rollback and provenance.

Public Tcl functions include `importerBuilderDefaults`, `importerBuilderValidate`, `importerBuilderSave`, `importerBuilderGet`, `importerBuilderReload`, `importerBuilderTest`, `importerBuilderDuplicate`, `importerBuilderExport`, `importerBuilderImport`, and `importerBuilderRemove`.
