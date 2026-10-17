# GX-TXT Project API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Project API v1 provides a persistent organizational entity above Experiment:

```text
Project
  -> one or more Experiments
      -> Datasets / analyses / plots / viewers / results
```

A Project groups Experiments. It does not own or duplicate their scientific payloads, and assigning a Project never moves a Session directory.

## Persistent identity and metadata

Each Project has a stable `project_id` independent from its editable name. Persistent metadata includes:

- `project_id`;
- `name`;
- `description`;
- `tags`;
- `author`;
- `created_at`;
- `updated_at`.

The user-local authoritative registry is `projects.ini` under the same GX-TXT XDG configuration root used by other persistent framework configuration. The file is UTF-8, deterministic and human-readable.

## Experiment identity and membership

Project membership uses a persistent `experiment_id`, not a Session path or display name. A membership records the Project ID and the last known Session path and Experiment name for navigation.

The Session manifest carries a `[project_link]` section containing:

```ini
[project_link]
api_version=1
experiment_id=experiment-...
project_id=project-...
legacy_project=
```

The Session path is therefore location metadata, not Experiment identity. Opening a Project-linked Session refreshes the user-local membership index by stable Experiment ID, allowing the recorded path to follow a moved Session when that Session is opened again.

## Historical `experiment_project` compatibility

Manifest Format 2 continues to write the historical `experiment.project` field for backward compatibility. For a persistent Project it contains a display-name snapshot only; `project_link.project_id` is the authoritative identity.

A legacy manifest with only `experiment.project` is **not** converted automatically into a named Project. The old text is exposed as legacy project text and remains recoverable. When the user explicitly associates that Experiment with a persistent Project, GX-TXT stores the old text in `project_link.legacy_project` before setting the new Project ID.

Detaching reassigns to Default / Unassigned and retains legacy text. It never deletes the Session, Dataset, RAW source, plot or analysis result.

## Public Tcl operations

The core API includes the following practical entry points:

```text
projectRegistryPath
projectLoadRegistry
projectSaveRegistry
projectIds
projectGet
projectField
projectExists
projectCreate
projectUpdate
projectExperimentReassign
projectAssociateExperiment
projectDetachExperiment
projectListExperiments
projectAssociateCurrentExperiment
projectDetachCurrentExperiment
projectCurrentId
projectCurrentDisplay
projectSynchronizeCurrentExperiment
```

`projectCreate` and `projectUpdate` persist Project metadata immediately. Creating a Project never assigns an existing Experiment. `projectExperimentReassign eid projectId ?expectedProject?` uses the existing organization transaction to update a selected Experiment without opening it. The optional expected source Project rejects a stale selection; an already-current destination is a no-op. Current-Experiment association/detachment updates both the persistent Project membership registry and the Session manifest.

## GUI integration

Experiment is a Session section alongside files, scripts, Workspaces, Configuration / Manifest and Parameters. The Projects page browses independent Project membership. Creating a Project or selecting a browser row does not move the open Experiment. **Move open Session here** is an explicit association command. Each Experiment row offers **Move to Project…** with named and Default / Unassigned destinations, without opening or relocating that Session. Default rows omit the redundant Move to Default command.

The Experiment section retains its View/Edit/Save notes, Project display, New Project and Edit Project controls. Additional public association/navigation operations remain available to callers even when the Experiment section has no corresponding button.

| Exact command and arguments | Preserved contract / remaining purpose |
|---|---|
| `::GX::projectAssociateCurrentExperiment projectId` | Associate the current Experiment with a persistent Project; retain legacy Project text; save membership and Manifest without moving the Session. Used by the Projects page and programmatic callers. |
| `::GX::projectDetachCurrentExperiment` | Reassign current membership to Default / Unassigned and persist the link; no Session or scientific deletion. Used by Projects detachment and programmatic callers. |
| `::GX::projectAssociateExperiment projectId experimentId sessionPath experimentName` | Persist independent membership by stable Experiment ID. Also used by New Experiment with a fresh ID/path. |
| `::GX::projectDetachExperiment experimentId` | Reassign a specified membership to Default / Unassigned; retained by Projects and public callers. |
| `::GX::projectSelectDialog` / `::GX::projectSelectDialogAssociate w` | Supported host dialog/callback for selecting and associating a Project; no Experiment-section button. |
| `::GX::projectDetachCurrentExperimentDialog` | Supported nondestructive confirmation callback; GUI-detached from Experiment intentionally. |
| `::GX::projectExperimentsDialog` | Supported host selector over the current Project's recorded Experiments; GUI-detached from Experiment intentionally. |
| `::GX::projectOpenExperimentFromList w` | Validate a recorded Session path and open through the normal controller. Retained for dialog/programmatic callers. |
| `::GX::projectListExperiments projectId` | Return independent membership descriptors for existing Project navigation and automation. |
| `::GX::projectGuiOpenExperiment` / `::GX::openSessionPath path` | Existing Projects navigation and shared Session opening remain supported. |

## Persistence and deletion semantics

Project state is authoritative user state, not runtime/cache. Resource Lifecycle deletion reassigns named Project members to the protected Default Project, retaining scientific Sessions. Session deletion retains a reversible recovery tree. See [Project Experiment management](PROJECT_EXPERIMENT_MANAGEMENT_API_v1.md) and [Object Origin](OBJECT_ORIGIN_API_v1.md).

## Scope

Project API v1 is generic. It contains no CFD-specific fields and no Instrument Library. Future CFD and laboratory workflows may use Projects as containers without changing the Project identity model.
