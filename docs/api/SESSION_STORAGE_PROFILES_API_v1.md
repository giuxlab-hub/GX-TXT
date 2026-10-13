# Session Storage Profiles API v1 (dev082)

SPDX-License-Identifier: GPL-3.0-or-later

The existing global `WORKING_DIRECTORY_PROFILES_API_v1` remains compatible with
`working_directory_profiles.ini` and all five chooser roles. Its GUI lives in
Configuration → Storage → Storage Profiles. Load/edit selects saved fields; Save
creates/updates; Apply saves and applies; New clears fields; Remove deletes.
Session choice is unaffected. The shared CORE chooser helpers retain their contracts.

Sessions → Configuration / Manifest → Storage Profiles manages independent private
profiles, persisted in `metadata/storage_profiles.ini`. This is directory convenience
state, separate from the scientific Workspace registry. Global copy snapshots values;
subsequent global changes do not alter a private copy. There is no live inheritance.
Private CRUD APIs: `sessionStorageProfilesRead ?session?`,
`sessionStorageProfileSave name values ?session?`,
`sessionStorageProfileCopyGlobal global name ?session?`,
`sessionStorageProfileApply name ?session?`, `sessionStorageProfileDelete name ?session?`.
`sessionStorageProfileEffective role ?session?` returns its effective override.
Read returns `version`, `active`, `profiles` (name → five-role dictionary).

Values are absolute directories, empty values or `@session/relative/path`. Relative
traversal is rejected. An active private role takes precedence over the global role;
blank or unavailable private directories fall back through the existing chooser policy.
Use global directories clears the private active choice. Applying a global profile
through Configuration does the same. The choice survives reopen. Private application
updates the current creation/export settings without changing global saved profiles.

Duplicate Experiment retains private definitions, omits absolute references inside
the source Session, and preserves explicitly portable @session paths. Arbitrary paths
are never silently rebound. Portable Session transport includes this file losslessly.
Old Sessions need no migration or private profile file. Writes replace atomically;
invalid private registries return errors instead of silently falling back.

## dev084 operator state and scope

The initial page displays the five **effective** chooser directories in read-only
fields. Its heading reports Global (named or unnamed), Session private, or mixed
per-role fallback. Each field names its source. Selecting a private row does not
apply it; Use selected private applies the saved snapshot, Edit private copy opens
its raw values (`@session/...` or blank included), and Save & Use private is explicit.
Save private saves without switching; Cancel / Show effective discards the draft.

Choose the global selector and Use global profile to use it directly. Create
independent private copy proposes the source name when the private editor is blank
or showing effective values. It never overwrites an existing private namesake:
select/Edit that row or New private with another name. Identical names across
global/private scopes are valid. The copied profile is saved immediately, then
opened for editing; Use/Apply is a separate explicit action. Cancel does not remove
an already-created independent copy. New/Edit never writes through to global values.

Applying rejects nonblank unavailable directories with a readable contextual error;
blank private roles intentionally fall back. Existing active profiles with later
unavailable roles continue to show the actual fallback values/source. Read-only
effective display does not mutate preferences. Removal confirms and keeps scientific
files; removing the active private profile restores global behavior. The API's existing
explicit `sessionStorageProfileCopyGlobal global name` contract is unchanged.

Saving an already-active private profile updates that private definition's effective
values, as in the existing API; the editor labels this before Save and returns to
actual effective fields afterward. Saving an inactive private profile does not switch
it into use. Global/private copies stay independent. Configuration defaults do not
replace a named applied global root during Session initialization; all creation/export
runtime mirrors use the same effective chooser resolver. Configuration → Storage
shows the global values even when a private profile is active.

Clean duplication also omits absolute directories inside any recognizable earlier
carrier Session (ancestor contains channels/ and metadata/manifest.ini). This prevents
an imported private snapshot from reconnecting a new preparation clone to an earlier
carrier's scientific directory. Shared storage roots outside Sessions are retained;
@session references stay relative and unavailable targets fall back normally. Portable
lossless import/export retains original private definitions and never applies this
preparation-only cleanup. Save may retain an unavailable directory as a draft;
Use/Apply validates availability before changing the applied context.
