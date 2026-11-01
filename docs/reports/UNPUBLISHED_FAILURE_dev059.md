# Historical checkpoint — superseded

The report below describes the earlier unpublished stop. Its curved-Join blocker and remaining scope were resolved in the same candidate. See CONSOLIDATION_dev059.md and ACCEPTANCE_dev059.json for current status.

---

# GX-TXT dev-059 — unpublished implementation failure report

Status: **STOPPED / UNPUBLISHED — mandatory implementation and GUI gates incomplete**.

This is the current stop report, superseding the earlier desktop preflight stop.
The desktop prerequisite was resolved. The failure is now incomplete product
scope, including the confirmed straight-only Join restriction. This candidate
must not be installed or described as an accepted dev-059 release.

## Baseline and desktop

The candidate `_work_gxtxt_dev059` was created from immutable published
GX-TXT 0.9.8.10-dev-057, Workbench 2.6.0 / Curve Fit 0.3.5. No dev-058
product source was merged. Architecture ownership/load/wrapper discovery preceded
refactoring; see `GXTXT_DEV059_DEV057_ARCHITECTURE_MAP.md`.

The decisive GUI work used the normal local Linux XFCE desktop on Xorg `:1`,
giu, seat0/tty2, session15029, Remote=no. Receipt and actual-input log are under
`TK_GIUXLAB/_dev059_physical_desktop`. The X server and Tk renderer ran on the
Linux server. No SSH/X11 forwarding or VcXsrv was used for these checks. Earlier
`:59` Linux-local VNC checks are supplementary. Credentials were not stored.

## Confirmed mandatory failure

In physical GUI06, the named `constraints059` workspace contains an Arc and a
two-control retained Path with a solved Tangent relationship. Real canvas clicks
selected the Path segment and Arc together. Modify > Join retained straight
paths displayed:

> Join in dev-057 requires retained straight paths/lines; curved composite
> constituents remain future work

Inspected screenshot:
`TK_GIUXLAB/_evidence_dev059_physical_gui06/14-confirmed-curved-join-rejection.png`.
Both logical objects remained present; no composition was produced. This proves
the family restriction is still exposed. It is not a claim that these particular
endpoints form a valid ordered junction, or a completed topology rejection test.

The cause is explicit in the candidate: Workbench `_pathJoinOpen` accepts only
line/polyline/path, and Native `path_linear_vertices` does the same. Native
`gx2d_path_join` still concatenates straight vertices. Exact heterogeneous Path
constituents, a truthful logical Compound container and their representation-aware
publication are **not implemented**. No Tcl grouping or sampled approximation was
substituted. Task G–I and release checklist16–19 therefore remain unaccepted.

## Changes present, with bounded validation

Workbench consolidation removed111 of the original199 executed rename wrappers
(88 remain). Explicit owners now cover workspace capture/restore, drawing,
persistence, pointer dispatch, UI opening/building, semantic selection and command
dispatch. Differential contracts passed9 state,11 persistence and30 pointer cases
at their recorded pre-UX checkpoints; these do not prove final GUI equivalence.

Candidate UX includes an object-list semantic selection projection, atomic bulk
commands, Ctrl-add/Shift-subtract, selected-row context preservation, empty-canvas
context, pictographic Select/transform icons, existing Native pivot/gizmo controls,
sticky creation and tool feedback. A command/shortcut registry uses existing CORE
configuration with conflict checks. Physical GUI04/05 demonstrate selected mixed
bulk duplicate/delete/hide/show and undo/redo cases, two consecutive Rectangles,
Escape cancellation, shortcut conflict/reassignment/reload and graphical pivot
placement. Migration of **all** command surfaces and complete UX coverage remain
unfinished; these are partial results, not checklist-wide acceptance.

Native scientific tangent evaluation was separated from presentation interpolation.
A physical Dataset segment/context failure also led to preserving segment kind
when its source-row ordinal overlaps a point index. Focused regressions fail057
and pass the candidate. All23 Native CTest cases pass in native02. Three existing
CORE/Workbench/Curve Fit adapter destinations match. No final sanitizer campaign
or full current-source acceptance suite was completed.

One real constraint journey passed: GUI-created Arc plus two-control Path,
segment/object selection, Constraints > Connections > Tangent, visible solve,
endpoint drag with relationship enforced, Undo/Redo, save and named-workspace
reopen. GUI05 and GUI06 show its glyph and retained relationship. Native residual
was approximately6.2e-13. This is **one case only**; incompatible-input acceptance,
multi-segment Path tangency and the rest of task J's matrix remain untested or
unimplemented. It must not be generalized to complete CAD solver acceptance.

Dataset private metadata extends the existing metadata INI/registry commit
authority. `_gxtxt.framework.*` and encoded module prefixes are filtered from
ordinary metadata reads/editor/export. CORE-issued ephemeral capabilities bind
module writes; Bridge ownership comes from runtime module identity. Existing Tcl
modules are trusted code, not OS-sandboxed. Private metadata is not a second store.

Dataset organizational namespace uses a reserved framework metadata key. Current
namespace persists in the Session Manifest; missing old fields follow current
without eager rewrites. V2 and file publication implement module/current/explicit
defaults. The new tree is a catalog projection. Variables/Preview selection names
alias one existing variable, not independent selection stores.

Supplementary results:22 private-metadata authority checks,24 namespace/publication
checks, and actual registered Python and Octave Script Execution/Bridge runs pass.
The two languages run under distinct module identities and verify own writes,
cross-module reads/preservation and rejected foreign/framework writes. These
tests do not complete the API surface/importer audit.

Physical GUI06 verified tree selection, context access, namespace move, current
namespace change, old-Dataset fallback, generic Metadata filtering and Preview.
Fresh GUI07 verified namespace persistence and corrected default workspace name.
Pending-import, all rename/delete/export actions, Session switching and realistic
catalog load remain acceptance gaps.

## Evidence and invalid attempts

Paths below are relative to `TK_GIUXLAB`:

| Evidence | What it establishes |
|---|---|
| `_evidence_dev059_architecture01`, `02`, `11`, `12` | Baseline/discovery and incremental/current procedure ownership |
| `_evidence_dev059_native02` and `_evidence_dev059_native02.log` | 23 passing Native fixtures and adapter build |
| `_evidence_dev059_private_metadata04/result.txt` | 22 authority checks |
| `_evidence_dev059_namespaces02/result.txt` | 24 namespace/publication checks |
| `_evidence_dev059_dataset_bridge01` | Genuine Python/Octave child results and private Session/runtime logs |
| `_evidence_dev059_physical_gui01` through `07` | Source-stamped local GUI checkpoints, partial passes and failures |
| `_dev059_physical_desktop/actions.jsonl` | Timestamped real-input actions through the logged local desktop |
| `_evidence_dev059_release_unchanged.json` | Final release/package/handoff immutability check, not candidate acceptance |

Rejected exploratory evidence stays rejected. GUI03 had a Treeview argument error
that was corrected. GUI04 exposed the Native segment reference bug. GUI06 shots11–13
do not establish curved-family rejection: insufficient selection and a modal
dialog blocked input. Shot14 is the corrected, inspected reproduction. Shot09 was
captured before its new window mapped (one-pixel image); shot10 is the valid visible
named reopen. GUI06/07 `open_journey.py` raced the file-dialog mapping; explicit
subsequent visible interaction opened the Session. No failed helper action was
counted as success. Capture now rejects an unmapped/trivial target. The earlier
in-place adapter replacement process failure is also excluded; adapters are now
replaced by a new inode and acceptance uses a fresh host.

## Remaining mandatory gates

| Task area | Blocking remaining work |
|---|---|
| A/O | Complete dev057 parity for images, comparison, recovery, Bridge and realistic mixed-scene fluidity; final current-source checks |
| B–F | Complete registry migration and all menu/toolbar/context/shortcut surfaces; complete selection modes/modifiers, lock/unlock rejection, shortcut reset/case handling, every sticky creation family |
| G–I | Exact heterogeneous Native Path and Compound; atomic topology, sub-entity semantics, undo/persistence, reviewed promotion integration and truthful explicit publication policies |
| J | Entire mandated family/negative-input matrix; solver-versus-GUI exposure audit and all supported tangent families |
| K–M | Finish private-context coverage, importer/default pinning and Dataset public/Bridge completeness audit, especially lifecycle, notes and export decisions |
| N | Remaining tree lifecycle/pending-import/Session-switch/context workflows and realistic catalog performance; snapshot currently repeats per-Dataset registry reads |
| O | Full save/reopen/recovery, mixed-object responsiveness and final real local GUI acceptance |
| P | Release versions, CHANGELOG/manuals, final API/Bridge docs, source inventories, packages and publication handoff only after all gates pass |

## Publication and stop boundary

No dev-059 framework archive, deployment, external plugin release or Session
Generator was published. Candidate release versions and packaged inventories are
intentionally unfinalized and must not be used as installable release metadata.
Published dev057, active/alias/restore and previous versioned/current release
handoffs remain authoritative. The three server package sections have no new
package pairs to synchronize because no release/package was added.

The final integrity receipt must be PASS before this stop is reported complete.
GUI validation hosts were closed; the user's normal local desktop remains active.
The private candidate, Sessions and evidence are retained for review. The old
preflight report is preserved as `_evidence_dev059_preflight_report_superseded.md`.

Stop here under the task's failure rule. Do not publish this partial candidate or
start another cycle. Any later authorized continuation should resume this same
unpublished cycle, re-read this report/checkpoint and revalidate changed runtime
source on the normal local Linux desktop.
