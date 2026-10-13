# GX-TXT Working Directory Profiles API v1

Version introduced: **GX-TXT Pipeline v0.8.8**.

## Purpose

Working-directory profiles are user-local convenience state. They let an operator switch between projects such as `REATTORE`, `IR_REMOTE`, or `FTIR` without repeatedly navigating to the same directories.

They do **not** change the currently open session and are not scientific metadata.

## Profile fields

A profile stores these directory roles:

| Role | Meaning |
|---|---|
| `acquisition_dir` | Initial directory for legacy and plug-in acquisition source choosers |
| `session_root` | Root under which new GX-TXT sessions are created |
| `session_open_dir` | Initial directory for `Open session...` |
| `manifest_dir` | Initial directory for configuration manifest load/save |
| `export_dir` | Default export/PDF directory |

Loading a profile applies `session_root` to `cfg(output_root)` and `export_dir` to `cfg(export_dir)`. It does not close, replace, or relocate `currentSession`.

## Persistence

Profiles are user-local and stored outside project/session data:

```text
$XDG_CONFIG_HOME/gxtxt_pipeline/working_directory_profiles.ini
```

or, when `XDG_CONFIG_HOME` is not set:

```text
~/.config/gxtxt_pipeline/working_directory_profiles.ini
```

Example:

```ini
[profile.REATTORE]
name=REATTORE
acquisition_dir=/data/reactor/incoming
session_root=/data/reactor/GXTXT_sessions
session_open_dir=/data/reactor/GXTXT_sessions
manifest_dir=/data/reactor/config
export_dir=/data/reactor/export
```

## GUI

Since dev082, Configuration → Storage provides a full **Storage Profiles** manager.
The former top-bar Workspace controls are removed. Sessions also support independent
[private Storage Profiles](SESSION_STORAGE_PROFILES_API_v1.md).

Since GX-TXT 0.9.7.85, final CORE chooser sites use the shared helpers:

```tcl
workspaceOpenFile role ?tk-options...?
workspaceSaveFile role ?tk-options...?
workspaceChooseDirectory role ?tk-options...?
```

They supply the role's initial directory unless the caller provides a valid
closer `-initialdir`, remember a successful selection, and leave cancellation
without side effects. `Open Session` uses the same centralized initial-directory
policy but commits `session_open_dir` only after `openSessionPath` succeeds.

Plug-in acquisition Browse, batch Add/Browse and Portable Session import/export
therefore inherit profile state independently of CORE source order.

## Descriptor opt-in

Descriptor-driven module and graph fields whose `type` is `file` or `path` may
declare an existing profile role explicitly:

```ini
[config.parameter_csv_path]
type=file
must_exist=1
extensions=.csv
workspace_role=acquisition_dir
```

A valid directory derived from a populated field remains the first choice;
otherwise the declared role supplies the initial directory. No role is inferred
for fields that omit `workspace_role`, and unknown roles are rejected.

## Compatibility

This API is additive. Existing manifests and sessions remain valid. Working-directory profiles are intentionally not required for headless operation. Loading the last-used profile automatically remains outside API v1; callers and the GUI continue to apply a saved profile explicitly.

## dev084: catalog editing and applied context

`workspaceProfileSave name values` saves all five values without applying them or
changing the open Session; blank values remain blank. Global paths must be absolute
and single-line. Save and deletion restore catalog memory after write failures.
`workspaceProfileApply name` retains its signature, applies and persists the named
context atomically in the existing INI; failed writes restore current directories.
Additive `[registry] current` and `directory.<role>` keys retain the applied name and
five global values across restart. Old catalogs need no migration. The host calls
`workspaceStorageRestore` after normal defaults when constructing the GUI. Profile
administration remains a host preferences action rather than a module-facing setter.

Configuration → Storage shows an expanding catalog. Selecting a row loads its saved
values for editing; the heading still identifies the applied global context. Save
updates only the catalog, Save & Apply changes directories, and Cancel / Show applied
discards editor changes. New uses a fresh name; an existing name requires explicit
row selection/Edit. Removing a profile confirms, retains every directory/file and
leaves current values as unnamed global directories if its applied name was removed.
Storage defaults/cache settings remain available through the fold button.
