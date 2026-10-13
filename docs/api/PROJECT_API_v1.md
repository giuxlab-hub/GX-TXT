# GX-TXT Project API v1

SPDX-License-Identifier: GPL-3.0-or-later

## Purpose

Project API v1 adds a persistent organizational entity above Experiment:

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

A pre-0.9.7.66 manifest with only `experiment.project` is **not** converted automatically into a Project. The old text is exposed as legacy project text and remains recoverable. When the user explicitly associates that Experiment with a persistent Project, GX-TXT stores the old text in `project_link.legacy_project` before setting the new Project ID.

Since dev083 detaching reassigns to Default / Unassigned and retains legacy text. It never deletes the Session, Dataset, RAW source, plot or analysis result.

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
projectAssociateExperiment
projectDetachExperiment
projectListExperiments
projectAssociateCurrentExperiment
projectDetachCurrentExperiment
projectCurrentId
projectCurrentDisplay
projectSynchronizeCurrentExperiment
```

`projectCreate` and `projectUpdate` persist metadata immediately. Current-Experiment association/detachment updates both the persistent Project membership registry and the Session manifest.

## GUI integration (Phase 1, dev077)

Experiment is an internal Session section, selected alongside Session files,
scripts, Workspaces, Configuration / Manifest and Parameters. The actual existing
Experiment panel, four View/Edit/Save note sections, Project display, New Project
and Edit Project controls are reused. The standalone Projects page is unchanged.
Dataset remains its independent page.

The Experiment row no longer constructs Associate current Session..., Experiments...
or Detach Session buttons. This deliberately removes GUI entry points only. Every
operation below remains callable and supported; absence of a button is not evidence
of dead code, deprecation or permission to delete an API.

| Exact command and arguments | Preserved contract / remaining purpose |
|---|---|
| `::GX::projectAssociateCurrentExperiment projectId` | Associate the current Experiment with a persistent Project; retain legacy Project text; save membership and Manifest without moving the Session. Used by the Projects page and programmatic callers. |
| `::GX::projectDetachCurrentExperiment` | Reassign current membership to Default / Unassigned and persist the link; no Session or scientific deletion. Used by Projects detachment and programmatic callers. |
| `::GX::projectAssociateExperiment projectId experimentId sessionPath experimentName` | Persist independent membership by stable Experiment ID. Also used by New Experiment with a fresh ID/path. |
| `::GX::projectDetachExperiment experimentId` | Reassign a specified membership to Default / Unassigned; retained by Projects and public callers. |
| `::GX::projectSelectDialog` / `::GX::projectSelectDialogAssociate w` | Supported host dialog/callback for selecting and associating a Project; no Experiment-row button in Phase 1. |
| `::GX::projectDetachCurrentExperimentDialog` | Supported nondestructive confirmation callback; GUI-detached from Experiment intentionally. |
| `::GX::projectExperimentsDialog` | Supported host selector over the current Project's recorded Experiments; GUI-detached from Experiment intentionally. |
| `::GX::projectOpenExperimentFromList w` | Validate a recorded Session path and open through the normal controller. Retained for dialog/programmatic callers. |
| `::GX::projectListExperiments projectId` | Return independent membership descriptors for existing Project navigation and automation. |
| `::GX::projectGuiOpenExperiment` / `::GX::openSessionPath path` | Existing Projects navigation and shared Session opening remain supported. |

The presumed apparently-unused-API ledger could not be located in the published
framework/tooling or project/server documentation during Phase 1. This preservation
list belongs to this existing API manual; it is not a replacement unused-API registry.
The exact negative search scope is recorded in the versioned technical report.

## Persistence and deletion semantics

Project state is authoritative user state, not runtime/cache. Since dev083, Resource Lifecycle deletion reassigns named Project members to the protected Default Project, retaining scientific Sessions. Session deletion retains a reversible recovery tree. See [Project Experiment management](PROJECT_EXPERIMENT_MANAGEMENT_API_v1.md) and [Object Origin](OBJECT_ORIGIN_API_v1.md).

## Scope

Project API v1 is generic. It contains no CFD-specific fields and no Instrument Library. Future CFD and laboratory workflows may use Projects as containers without changing the Project identity model.
