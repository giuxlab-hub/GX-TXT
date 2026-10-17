# Project Experiment management v1

SPDX-License-Identifier: GPL-3.0-or-later

Existing Project API signatures remain. Built-in `projectDefaultId` always resolves
to `project-default-unassigned`; `projectEnsureDefault` persists it once. It cannot
be deleted or edited as an ordinary Project. It is an organization record, not a
scientific store. Its normal creation/import/duplication root uses configured Session
root; every existing member retains its recorded path.

`projectExperimentResolve eid` checks membership, authoritative Manifest IDs, complete
Session shape and Resource Lifecycle protections. Actions always use the stable eid:
`projectExperimentRename eid name`, `projectExperimentReassign eid projectId ?expectedProject?`,
`projectExperimentDelete eid`, `projectExportExperiment eid archive`,
`projectImportExperiment projectId archive destination`.
`projectDetachExperiment eid` and `projectDetachCurrentExperiment` mean
reassignment to Default, preserving bytes and legacy text. Ordinary association never moves a Session directory. The optional expected source Project rejects stale membership; an already-current destination is a no-op.

Sessions created without a named Project obtain Default membership at authoritative persistence. Legacy Sessions
are associated only as encountered, with additive project_link fields, preserving
historical experiment.project text and legacy_project. Missing foreign Project links
are retained as previous_project_id and assigned locally to Default. No disk crawl or
mass migration occurs. A live duplicate identity at another existing path is refused;
use Portable import for an independent organizational identity. Moving a Session whose
old location no longer exists preserves its stable Experiment ID and refreshes index.

Rename changes experiment.name and membership name, updates current GUI labels, and
keeps acquisition directory name, bytes, stable ID and creator. Source scientific
registries are never rebuilt. Project create/update and Session creation failures restore
registry/Manifest and live preparation. Membership/Manifest changes use a host journal
with exact preimages, exclusive writer reservation, atomic file replacements and
fresh-start recovery of interrupted transactions. An active writer is not recovered
by another process. Malformed journals fail clearly. Physical Windows crash behavior
is not claimed verified. The host owner is an ordinary local process, not a daemon.

Deletion reuses Resource Lifecycle Session inspection/root/dependency ownership checks.
After explicit destructive GUI confirmation, CORE removes the Session from normal
navigation and its membership, atomically moving its complete tree to a unique
`.gxtxt-deleted-sessions/<name>-<generation>` recovery path beside its former parent.
It never recursively erases a source in place. API returns `recovery_path`; host status
shows it. Failure/interruption reverses quarantine and restores membership. External
RAW/sources are preserved. Recover by moving the retained tree to a fresh intended
Session path and opening it; its stable ID can be encountered again once the prior
location is absent. Named Project deletion reassigns members to Default and removes
Project metadata, retaining Session directories and scientific payloads. Default is
protected; unclassified Project resources and inconsistent membership block deletion.

Portable import/export calls the existing Portable Session authority. Import validates
before private hidden staging and membership commit. Existing destinations are never
overwritten; nesting an import inside a registered Session is refused. Each independent
import receives a fresh organizational Experiment ID and local Project link; original
organizational IDs remain lineage. Scientific Dataset/variable/Selection/document IDs
and payloads are preserved, since they are Session-scoped. No scientific IDs are
remapped. No Project is silently coalesced or overwritten. Missing/different modules
and external dependencies are returned in `diagnostics`, never substituted. A failed
import leaves no final destination or half membership; interrupted staging is hidden
and recoverable. Session → Tools uses the same authority and associates Default.

Read-only `projectExperimentInspect eid` returns summary, origin, Dataset counts by
contract/type/format, configured/enabled/Run modules, modules inferred from Dataset
source_module records, registered Session scripts, Markdown documents and diagnostics.
It never opens the inspected Session. Other module-use history is explicitly unknown.
`projectExperimentDocumentRead eid relative expectedSha` uses the public Session
resource resolver, rejects symlinks/escape/stale hashes and caps preview at 2 MiB.
`sessionInspectionMarkdownDocuments ?session?` is an additive existing Inspection
service: only Markdown files are hashed, avoiding scientific payload scans for browsing.
Dataset payload integrity checks use the existing canonical Dataset inspection API.

Original Format1 Session navigation/Default association remains supported without a
forced format conversion. Destructive deletion retains the existing Resource Lifecycle
Format2 safety gate; save an old Session normally before using that deletion route.

## Inspection ownership and browser

The `projectExperimentInspect` / `projectExperimentDocumentRead` public
contracts live with the CORE Project/Session services, usable without Tk. Inspection returns
`datasets` records with availability and uses the guarded Inspection location
reader to avoid hashing large payloads during a GUI click. Counts/provenance/scripts
and source_module use evidence remain available; availability never claims integrity.
Normal scientific readers and Portable transport still verify canonical hashes.

The browser has explicit single selection, full-row theme-aware highlight and a named
Export target. Each row action captures the stable ID; names and sorting do not own
identity. Import requires only a selected Project. One selected Experiment exports one
existing validated Portable package; multi-export is not offered. Info replaces the
same right canvas with resizable Overview, Datasets, Modules & Scripts, Documents and
Origin & Technical sections. Documents distinguish Session notes/module snapshots/
other files, label snapshots without primary hash paths, automatically render a note
through the existing scientific Markdown component, and verify content before preview.
Empty Sessions have explicit no-documents states. Missing resources show diagnostics
without replacing or modifying the active Session. Full paths/hashes are in details.

An empty historic display name uses the Session directory's last component in the
browser, Info, target summary and dialogs. This is presentation only: inspecting does
not rewrite the old Manifest or registry. Deletion completion displays the retained
recovery path. Portable completion explains missing modules, package/installed versions
and unresolved external sources in human-readable lines; successful import with missing
providers preserves science and asks the user to resolve providers before running.

## Complete Project transfer

[Project Portable API v1](PROJECT_PORTABLE_API_v1.md) provides whole-Project transport
using these existing membership, provenance and journal authorities.

## Explicit browser reassignment

Creating a Project and selecting a Project for browsing do not change any Experiment membership. **Move open Session here** deliberately changes the open Experiment. For a selected Experiment, **Move to Project…** lists every other available Project, including Default / Unassigned. Names are accompanied by stable IDs, so duplicate names remain distinguishable. The operation does not open the selected Session or move its directory. Rows already in Default omit the redundant **Move to Default** action.

Move commits only after the operator presses **Move**. Cancel/Escape leaves membership unchanged. The dialog rejects a changed source membership, moved Session path or current-Session switch and retains a visible error for correction or cancellation. An unavailable destination or transaction failure preserves the old membership and Manifest through the same public transaction owner; scientific Dataset bytes and identities are not edited by reassignment.
