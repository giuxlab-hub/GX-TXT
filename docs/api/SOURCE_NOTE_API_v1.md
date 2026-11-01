# SOURCE_NOTE_API_v1

Source notes use canonical `document.text` Datasets in the applicable Session.
This facade joins existing Dataset publication and Script Registry/C++ Project
owners; it creates no global Registry or alternate Markdown store.

`sourceNoteRead capability source_ref` describes an uncreated note, a local
no-Session draft, a pending explicit attachment or the canonical Dataset. Reading
never creates an identity, note or Dataset. `source_ref` has exactly `owner` and
`reference`: owner is `python_script`, `octave_script` or `cpp_viewer_project`;
the inert reference identifies its existing Registry/Project and relative file.
Stable owner/file UUIDs disambiguate same-basename files and explicit renames.

`cpp_viewer_project` is the historical stable identity of the existing
Development Workspace project owner. It also covers its genuine Acquisition
projects; it does not require a Viewer design or make the source a Dataset.
Its registered C++ files retain `language=cpp`. Registered Python runtime
helpers under `helpers/*.py` retain `language=python` and the exact project/file
identity and source CAS. They are not Script Registry entries. The source owner
must verify the actual registered roster before attaching or updating a note;
the portable association's structural validity alone grants no authority.
Tcl helper notes are unavailable in this version. Python/Octave Script Registry
owners and their existing association semantics are unchanged.
No caller supplies an implementation command or arbitrary filesystem selector.

`sourceNoteWrite capability source_ref request` requires the actual source
editor owner's capability and optimistic `expected_session`,
`expected_owner_revision`, `expected_authoring_revision` and
`expected_source_sha256`. The request carries exact `text`, optional managed
`assets`, and, for canonical replacement, `expected_revision` and
`expected_sha256`. Canonical Dataset IDs cannot be silently retargeted. Existing
producer/immutable/edit-grant checks and Dataset transactions remain authoritative.
Without a Session, only an explicit local Markdown draft is saved. With a Session,
an explicit Save creates or updates one canonical Dataset for that exact source.
Text is bounded to 4 MiB UTF-8; source bytes and scientific execution remain
unchanged. Stale saves fail and retain the editor draft.

`sourceNoteSnapshot capability source_ref request` is an explicit Save All or
portable project snapshot, guarded by the reviewed canonical revision/SHA and
source-owner revisions. Such local snapshots are transport material; Session
reads always use the canonical Dataset. A note using managed images reports
`assets_present`. Python/Octave source Projects preserve their exact PNG closure
in immutable source-owner attachments and their existing portable package.
The internal snapshot plan is a request-scoped ResourceManagement allocation,
bound to all source preimages and consumed once by the fixed source owner. It
never exposes an arbitrary path through the public source-note request. Omitted
image plans preserve local snapshots; explicit empty plans clear them.
Dataset, Session and Workspace transports use their existing managed-resource
owners. Imported source/project identities are
fresh, with inert lineage; portable Dataset imports never acquire a primary
source attachment or foreign edit grant by copying metadata.

On explicit attachment into a Session, verified inert source-image snapshots
are read through the fixed `sourceNoteAssetRead capability source_ref request`
host operation and adopted under a fresh ordinary managed-image carrier. Reads
require name, start, count, expected owner/authoring revisions and asset SHA;
each chunk is at most1MiB, each PNG4MiB and the canonical image map16MiB.
The temporary carrier closes after the canonical transaction commits or aborts.
An existing canonical note's explicit empty image map removes its images; an
older local snapshot never silently restores them. Pending/no-Session image
snapshots retain inert provenance and become editable managed resources only
through an explicit Session attachment or Publish New. C++ source-project
export/import uses the same bounded inert PNG closure through its existing
Project owner. Each source editor's fixed provider reads only the matching
snapshot, checks its identity and bounded chunk, and preserves exact note/image
bytes through fresh import identities. It never treats the snapshot as a second
canonical Session authority.

`sourceNoteAssociation dataset_id` and `sourceNoteSource dataset_id` are read-only
discovery/consultation operations. Missing, revised, renamed or invalid sources
return explicit diagnostics without substituting a similarly named file.
Only exact current code is returned. Python and Octave expose these two operations
through `SOURCE_NOTE_API_v1`; research scripts receive no Registry authoring hook.
Their normal Markdown Dataset I/O uses `DOCUMENT_SOURCE_API_v1`.

`sourceNoteOpen dataset_id ?resolution?` validates the current Dataset reference,
full revision and existing Contract Visualizer resolution before dispatching to
the actual source editor's Notes tab. If the original source is unavailable,
the admitted Documents Viewer opens that same canonical note Dataset. The
`source_editor_first` policy is declared by the installed visualizer descriptor.
Publish New creates a separate ordinary Markdown Dataset and preserves the
original source association. No new ownership grant is implied by opening it.
