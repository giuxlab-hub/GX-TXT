# Project Portable API v1 — dev085

`::GX::projectPortableExport projectId archive` exports the complete **saved** Project
through existing Project membership and Session Portable APIs. Returns `archive`,
`sha256`, `experiment_count`, `dependency_count`, `file_count`. Export never overwrites
an existing file and must be outside the Project and every source Session.

`::GX::projectPortableValidate archive` validates the complete Project container and
all nested Session packages, hashes, source identifiers and reference consistency.
Returns the same package summary. No organization or identity writes occur.

`::GX::projectPortableImport archive ?name?` creates a separate Project below the
configured Session / Project root; an empty name preserves the source name. Returns
`project_id`, `storage_path`, `source_project_id`, `snapshots_path`, `origin`,
`experiments` (new ID → source ID/path/display name), `diagnostics` (new ID → existing
Session dependency diagnostics), and `package_info`.

These filesystem transport operations are host-only, as existing Session Portable
operations are. Python/Octave Script Bridge intentionally excludes arbitrary archive
paths and installation-wide Project creation. Existing PROJECT_API_v1 read discovery,
ORIGIN_API_v1 and Session inspection remain available to scripts; no bridge contract
changes. Future callers can use the public Tcl APIs directly from the trusted host.

## Interoperable container

ZIP format `GXTXT-PROJECT-1`, manifest `gxtxt-project.json`:

- `source_project_id`, `carrier_installation`, ordered `sessions` records with nested
  `archive`, `source_experiment_id`, display `name`, and required module identifiers.
- `files`: exact ZIP payload inventory (`relative path` → `size`, lowercase `sha256`).
- `directories`: retained empty Project resource / dependency directories.
- `source/project.ini`: original Project metadata; `source/transfer.ini`: existing
  CORE INI encoding of authoritative Project fields and `experiment.N` membership.
- `sessions/N.zip`: unchanged Session Portable format, one per registered Experiment.
- `resources/`: Project-owned files and directories outside registered Sessions.
- `dependencies/modules/ID/`: complete module snapshots, including transitive
  descriptor `meta.depends` dependencies, runtime files, docs and licenses.

Every Experiment must resolve to a real Session with matching Project/Experiment
links. Missing members, unavailable dependencies or unresolved external Session
resources fail export rather than producing an incomplete Project. Session Portable
embeds referenced regular acquisition sources and Session-owned scientific resources;
Project symlink trees must be materialized before export. Arbitrary machine-global
resources are never traversed. Save edited Session configuration before export.

Import validates the exact outer inventory and every nested Session SHA before any
registry mutation. It rejects unsafe/absolute/traversal/duplicate/symlink entries,
inconsistent identifiers, occupied destinations and receiving roots inside existing
Projects/Sessions. Each Session receives a distinct local organizational Experiment
ID and final relocated path. Dataset/resource IDs remain Session-scoped and scientific
bytes are preserved. Project/Session creator identity, timestamps, previous history,
and source identifiers remain origin/lineage; receiver import events include package
SHA and the local installation ID. No foreign installation identity is adopted. Persistent source identifiers live in
`origin.events`; `project_link.imported_*` convenience aliases present at import are
not required after the existing Session Save rewrites its known link fields.

The existing Project journal exclusively owns the registry preimage and one complete
Project-directory move. Under its writer lock, import reloads the current registry
before adding new members. Failure reverses the move and restores the exact registry;
startup recovery handles an interrupted transaction. Recoverable private staging is
retained if rollback itself cannot finish; the error identifies the existing journal.
Other failures remove only uniquely owned private staging. No partial Project is
registered as successful. Project resources retain their relative paths. Original
metadata and module snapshots are inert under
`.gxtxt-project-transport/LOCAL_PROJECT_ID/{source,dependencies}`; retransfers retain
previous snapshots and origin history without resource overwrites. Snapshot code is
never installed/executed during import. Existing Session dependency diagnostics report
missing/version-different runtime plugins; inspect/install them through the existing
plugin workflow before running those modules. SHA integrity is not authentication.

GUI: Projects toolbar **Import Project…** / **Export Project…**. Import has an optional
name and always creates a separate Project. The selected receiving Project is not
modified. Sessions toolbar **⌂ Project Home** selects the open Session's associated
Project and Experiment without switching or saving the Session.
