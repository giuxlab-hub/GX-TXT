# Instrument Library API v1

GX-TXT 0.9.7.68 introduces a persistent Instrument Library for reusable descriptions of real laboratory instruments.

## Model

The framework keeps three concepts distinct:

```text
Instrument Module
= schema/type definition

Instrument Library Entry
= persistent description of a real instrument

Experiment Instrument Association
= historical snapshot of that instrument in one Experiment
```

A Library entry has a stable `instrument_id`, editable display metadata, an Instrument Module ID, category, manufacturer, model, serial number, firmware/version, default role, markup notes, timestamps, and any type-specific fields declared by its Instrument Module descriptor.

Library state is authoritative user state stored independently of Sessions and Projects under the normal GX-TXT user configuration root (`$XDG_CONFIG_HOME/gxtxt_pipeline` or `~/.config/gxtxt_pipeline`).

## Public Tcl procedures

The main API procedures are:

```text
instrumentLibraryIds
instrumentLibraryExists
instrumentLibraryGet
instrumentLibraryField
instrumentLibraryCreate
instrumentLibraryUpdate
instrumentLibraryDelete
instrumentLibraryExport
instrumentLibraryImport
instrumentLibraryApplyToExperiment
instrumentLibrarySyncExperimentInstance
instrumentLibraryLoadDemo
```

`instrumentLibraryCreate` accepts one dictionary. `display_name` is required; `module_id` defaults to `instrument.generic`. Type-specific values are supplied in the nested `fields` dictionary and are validated against the installed Instrument Module catalog.

## Historical Experiment snapshots

`instrumentLibraryApplyToExperiment` creates a normal Instrument Module instance in the current Experiment and copies Library metadata into that instance. The Experiment manifest therefore remains a historical scientific record even if the Library entry changes later.

The Experiment also records:

```text
library_id
library_snapshot_at
library_source_updated_at
```

These fields preserve provenance to the reusable Library entry but do not create a live synchronization relationship.

Editing a Library entry never rewrites old Experiment records. `instrumentLibrarySyncExperimentInstance` is the explicit synchronization action. It refreshes display name and identity/reference metadata while preserving Experiment-specific role, notes and setup fields.

## Portable entries

`instrumentLibraryExport` writes a UTF-8 portable `.ini` representation using Instrument Library Entry API version 1. `instrumentLibraryImport` creates a new Library entry with a new local stable ID; the source ID is informational only and cannot overwrite an existing local entry silently.

## Demo library

`instrumentLibraryLoadDemo` is explicit, never automatic. It seeds 20 clearly labeled `Example — ...` entries spanning multiple laboratory categories and uses conservative manufacturer/model/category facts only. A deterministic `demo_key` prevents duplicate seeding. Deleted or edited demo entries are not recreated unless the user explicitly invokes **Load Demo Library** again.

## Persistence and reset semantics

The Instrument Library is authoritative persistent state, not runtime/cache. Runtime reset must not delete it. Rendered note previews are derived and may be regenerated from their UTF-8 GX-Markup source.

## Embedded Session Library GUI (dev081)

**Session → Instruments → Open Library…** opens the existing Library interface
inside the Instrumentation right canvas. The Session instrument browser remains on
the left. **Close** returns to the previously selected Session instrument, retaining
its live edits. Library creation/editing, import/export, explicit sync, demo loading
and historical associations use the same public procedures above. Existing metadata
and scientific-notes dialogs remain available. Saving an entry refreshes the embedded
selection/details. Toolbar actions wrap at narrower application widths.

The GUI-only `instrumentLibraryBuildInterface w closeCommand` shares the original
widgets/callbacks across hosts. `instrumentLibraryOpenWindow` retains its zero-argument
entry point and returns the embedded widget host in the running main application;
a standalone Tk context retains the former window behavior. No Library persistence,
identity, snapshot or import/export contract is changed. Library editing never
rewrites past Session snapshots; synchronization remains an explicit action.
