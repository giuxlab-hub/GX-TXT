# OCTAVE_SCRIPT_EDITOR_API_v1

Provider: `analysis.octave_script` 1.3.0. The API activates the lazy Tk **Octave Script Workspace** Viewer through Viewer Provider API v1. The editor writes executable Octave scripts to CORE Script Registry, using `session:<id>` or `user:<id>` as stable references.

`workspaceList` lists registered Octave scripts in the current Session and user library, followed by readable `legacy:<document-id>` Workspace Interactive Documents. `workspaceRead reference` returns registry source and metadata or a legacy document. `workspaceSave reference expectedSha scope scriptId name description code ?arguments={}?` creates or updates the exact Script Registry record and returns its receipt. An update preserves its ID, language, semantic version, required APIs and typed parameters, and checks the previous SHA-256. Optional `arguments` stores default argument text. `workspaceDelete reference expectedSha` checks the exact registered source SHA and returns an empty Tcl result after removal. For `legacy:<document-id>`, it returns the deleted Document ID; the legacy adapter accepts an empty expected SHA, otherwise it compares digests case-insensitively. These operations are module-owned adapters to the public Script Registry API.

The Tk Viewer exposes New, Save, Save copy, Delete, Import `.m`, Export `.m`, scope/ID, syntax editing and search. Saving a new Session script makes it immediately visible to Script Library, Session Script Explorer and the `analysis.octave_script` registered-script selector. A User script is a reusable Library record and can be assigned to a Session through normal Script Library actions.

Legacy `gxtxt.octave_script.document` Interactive Documents remain readable. Explicit **Register as Session Script** and **Register as User Script** actions create a registered copy; the original legacy document stays intact until explicitly deleted. The old `documentRead`, `documentCreate`, `documentUpdate` and `documentDelete` API methods remain for compatibility and migration only. New Workspace saves do not create Interactive Documents.

| Legacy signature | Actual result |
|---|---|
| `documentRead documentId` | Owned legacy Document record with decoded source and metadata. |
| `documentCreate name arguments description code` | Created Interactive Document record. |
| `documentUpdate documentId expectedSha name arguments description code` | Updated Interactive Document record. |
| `documentDelete documentId expectedSha` | Deleted Document ID. |

Legacy Update/Delete accept an empty `expectedSha`; a nonempty value must match
the current Document digest case-insensitively. This compatibility behavior is
distinct from registered-source concurrency checks.

The Viewer entrypoint is host independent; Tk widgets load only upon activation. Scripts execute through CORE Script Execution and `OCTAVE_SCRIPT_BRIDGE_API_v1`, not through the Viewer.
