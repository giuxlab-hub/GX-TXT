# NOTE_DOCUMENT_API_v1

Generic workspace notes reuse Dataset Notes UTF-8 I/O, GX-Markup rendering and
the existing editor. A note belongs to a registered Session workspace, of any
provider. Its actual `.md` file is managed under `notes/workspaces/<ID>.md`; CORE
checks owner identity and symlinks and records an associated content hash. This
is not a Workbench-private store. Existing Dataset/Experiment Notes are intact.

Python and Octave call `read(workspace_id)` or `write(workspace_id, text)` through
`gxtxt_api_call("NOTE_DOCUMENT_API_v1", operation, arguments)`. Receipts contain
workspace identity, text and hash association. Writes are bounded to 1 MiB and
restore prior bytes if the Document association transaction fails. Workspace
export/import includes the note and verifies its hash.

Host `noteDocumentOpen ID view` renders markup. `edit` opens the established
GX-Markup source editor with rendered preview. Widget creation/editor opening
stays host-side; scripts read/write only managed UTF-8 content. No new editor,
markup language or arbitrary path operation is introduced.
