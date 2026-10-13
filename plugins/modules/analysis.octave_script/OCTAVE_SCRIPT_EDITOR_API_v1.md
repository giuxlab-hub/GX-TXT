# OCTAVE_SCRIPT_EDITOR_API_v1

Provider: `analysis.octave_script` 1.3.0. The API activates the lazy Tk **Octave Script Workspace** Viewer through Viewer Provider API v1. The editor writes executable Octave scripts to CORE Script Registry, using `session:<id>` or `user:<id>` as stable references.

`workspaceList` lists registered Octave scripts in the current Session and user library, followed by readable `legacy:<document-id>` Workspace Interactive Documents. `workspaceRead reference` returns registry source and metadata or a legacy document. `workspaceSave reference expected_sha scope script_id name description code` creates or updates the exact Script Registry record; an update preserves its ID, language, semantic version, required APIs and typed parameters, and checks the previous SHA-256. `workspaceDelete reference expected_sha` removes the selected record with the same concurrency check. These operations are module-owned adapters to the public Script Registry API.

The Tk Viewer exposes New, Save, Save copy, Delete, Import `.m`, Export `.m`, scope/ID, syntax editing and search. Saving a new Session script makes it immediately visible to Script Library, Session Script Explorer and the `analysis.octave_script` registered-script selector. A User script is a reusable Library record and can be assigned to a Session through normal Script Library actions.

Legacy `gxtxt.octave_script.document` Interactive Documents remain readable. Explicit **Register as Session Script** and **Register as User Script** actions create a registered copy; the original legacy document stays intact until explicitly deleted. The old `documentRead`, `documentCreate`, `documentUpdate` and `documentDelete` API methods remain for compatibility and migration only. New Workspace saves do not create Interactive Documents.

The Viewer entrypoint is host independent; Tk widgets load only upon activation. Scripts execute through CORE Script Execution and `OCTAVE_SCRIPT_BRIDGE_API_v1`, not through the Viewer.
