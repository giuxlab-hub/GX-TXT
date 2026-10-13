# Portable Session Export / Import

GX-TXT 0.9.7.79 can move a complete scientific Session between compatible
installations without depending on the original absolute Session path.

## Export

Open the Session and choose **Session toolbar → Tools → Export Session...**. Save the generated
`*.gxtxt-session.zip`. The archive contains the Session state/artifacts plus a
small transport manifest with a SHA-256 inventory and module/plugin dependency
information.

The archive preserves scientific identities and existing calculated outputs.
It is the format to use for backup, transfer to another GX-TXT installation or
continued editing.

## Import

Choose **Session toolbar → Tools → Import Session...**, select the portable archive and choose a new
Session name under the configured Session root. GX-TXT validates the complete
archive before extraction, imports through staging and commits only after the
Session is valid. Existing Session directories are never overwritten silently.

Missing plugins are reported after data import. The Session remains available
for inspection where safe, but operations owned by a missing plugin naturally
remain unavailable until the required plugin is installed.

## Integrity

Each packaged file has a byte count and SHA-256. Unsafe ZIP paths, symlink
entries, duplicate paths and corrupt/missing files are rejected before commit.

## Included state

Normal Session metadata, Datasets and variable schemas, Dataset Metadata and
notes, Selections, Temporal Sets, analysis configuration, published/derived
Datasets, graph/report artifacts, provenance, Session documentation and
Interactive Document state are transported when present. Only unambiguous
transient files such as locks/staging fragments are omitted.

## External resources

A regular scientific input file explicitly referenced by an old absolute
acquisition path is copied into the package when possible. Machine-global
resources and plugin executables are not copied blindly; unresolved external
dependencies are recorded and reported.

## Compatibility

The source GX-TXT version is recorded in the package. The scientific Session
manifest remains authoritative. Import does not regenerate stable Dataset or
variable IDs and does not convert the Session to HTML.
