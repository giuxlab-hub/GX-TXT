# Acquisition / Import

Select an importer, add one or more files or a folder, inspect the pending queue, then import into the current Session. Successful items leave the queue; failed items retain their status for correction. The queue is an interactive work list and is not stored in the Session manifest.

Importer Builder creates reusable registered import definitions for tabular sources. Configure parsing, file matching, metadata and variable mapping against a representative file, test the definition, then select it in Acquisition. The definition is stored in the user configuration area, while every published Dataset records its importer identity and version.

Acquisition Handler plugins may also supply scientific or binary import paths. Their manuals describe expected file formats and interpretation options. GX-TXT preserves each source and records hashes and publication provenance.
