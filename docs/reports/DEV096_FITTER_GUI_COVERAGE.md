# Dataset Curve Fit dev096 native control coverage

SPDX-License-Identifier: GPL-3.0-or-later

Archive-based acceptance: the complete main matrix ran on the first fresh
dev096 extraction. The final two scoped fixes affect Builder/Plot Dataset only;
Fitter and its CORE services retain exactly those tested product bytes.
Paths refer to `_evidence_integrated_dev096/`. Each named successful run has
its actual native input log and owned-window screenshots. Newer runs also have
`native-action-trace.tcllist`; earlier runs are not claimed to contain this newer
format. Test source is shipped in `validation/integrated_dev096/`.

This ledger groups controls that share a verified transaction. PASS is limited
to the actions and values explicitly named. A model's registration or a
headless numerical result is not counted as a native model selection.

| Visible control/action | Executed native path and checked outcome | Development evidence | Extracted-package evidence |
| --- | --- | --- | --- |
| Dataset, X/Y selectors, Show IDs | Long/duplicate labels resolve canonical IDs; source load is exact | `fitter-controls1`, `fitter-models-combined2` | PASS — controls, models |
| Source list activation and Ctrl multi-selection | Exact active owner; independent batch Preview/Accept across two sources | `fitter-sources2`, `fitter-interactions5`, `fitter-mixed2` | PASS — sources, interactions, mixed |
| Sources: Add Dataset curve | Actual menu loads complete canonical rows and frozen identity | Above, `fitter-large3` (131073 rows) | PASS — sources, large; supplemental1/fitter-inventory |
| Sources: Cancel; visible Cancel; Escape | Cancel during real source/fitting jobs, exact rollback and no live source-token leak | `fitter-lifecycle3`, `fitter-lifecycle-menu2` | PASS — lifecycle, lifecycle-menu |
| Sources: Show/Hide/Style/Remove/Reload/Reverse/Span | Menu actions and native style/span forms affect only the intended source; recorded selection/provenance remains exact | `fitter-interactions5`, `fitter-sources2` | PASS — interactions, sources; forms3 |
| Filter Variable/operator/value, Add/Remove | Native LIKE plus numerical bounds select exact canonical rows 200–499; remove restores 1001 rows | `fitter-controls1` | PASS — controls |
| Fit orientation | Actual Y=f(X), X=f(Y), parametric and experimental radial choices; enabled states and formula bindings | `fitter-models-combined2` (22 cases) | PASS — models |
| Model selector | Linear, polynomial, exponential, power law, Gaussian, PCHIP, smoothing spline, Fourier in both functional orientations; circular arc, quadratic/cubic Bézier, parametric polynomial/spline and radial linear | `fitter-models-combined2/model-results.tcldict` | PASS — models |
| Degree, initial guesses, Fourier period, smoothing lambda | Native edits reach appropriate models; unrelated fields disable; invalid degree recovers | `fitter-models-combined2`, `fitter-controls1` | PASS — models, controls |
| Domain, min/max, sample count | Source/range and parametric parameter domain; exact 11- and 17-point outputs; reversed bounds fail without acceptance | `fitter-controls1`, `fitter-parametric3` | PASS — controls, parametric |
| Parametric settings: topology/mode/Variable ID/period/tolerance, Apply/Close/Escape | Open row/path modes; closed Dataset parameter, explicit period 40/tolerance 1e-6, rejected period 20, cancel/recovery/reopen | `fitter-models-combined2`, `fitter-parametric3`; independent periodic error 2.220446049250313e-16 | PASS — parametric |
| Radial frame settings | Actual dialog defines polar frame and physical radial fit | `fitter-models-combined2` | PASS — models; forms3 |
| Fit-space translation: Auto/Manual/Off and axis constants | Native default Auto has no required manual C; manual/off settings, original physical Preview/CSV/Dataset output and frozen provenance | `fitter-history-gui29`, model matrix | PASS — history, models |
| Fit: Preview/Accept | Actual menu plus configurable F5/F6; one accepted physical curve, no redundant row or duplicate acceptance | `fitter-mixed2`, `fitter-history-gui29`, model matrix | PASS — mixed, history, models |
| Fit: Preview/Accept selected sources | Each accepted curve owns its actual selected source; mixed invalid batch rolls back exactly | `fitter-sources2`, `fitter-mixed2` | PASS — sources, mixed |
| Training scope and rectangle mode | All/selected input, point/Ctrl selection, rectangle Replace/Add/Subtract; selected-only Preview invalidation | `fitter-interactions5` | PASS — interactions |
| Selection: Clear and Remove last rectangle | Actual menu actions restore exact source-selection masks | `fitter-interactions5` | PASS — interactions |
| Plot wheel/pan; View Zoom in/out/Fit | View changes preserve accepted/scientific coordinates | `fitter-interactions5`, `fitter-view2` | PASS — interactions, view |
| Results: Publish Preview Dataset, Export CSV | Exact physical output and ownership; chooser/ID prompt cancel, duplicate Dataset rejection | `fitter-history-gui29`, `fitter-controls1`, `fitter-mixed2` | PASS — history, controls, mixed |
| Accepted list; Results Show/Hide/Delete/Publish | Stable accepted identity, independent visibility/deletion/Undo and captured-source publication | `fitter-interactions5`, `fitter-sources2` | PASS — interactions, sources |
| Built-in sample choice/Open/Publish | Native sample selection, source identity and exact canonical sample publication | `fitter-sources2`, geometric model matrix | PASS — sources, models; supplemental1/fitter-inventory |
| Residual visibility/split, First/Previous/Next/Last/page | Exact residual values and canonical IDs through all pager modes and 200-row pages; bounded display does not change full count | `fitter-controls1`, `fitter-large3`, `fitter-view2` | PASS — controls, large, view |
| View settings/grid tabs, Apply/Reset/Close/Escape | Grid visibility/spacing/line style/background edits and reset preserve scientific geometry | `fitter-view2` | PASS — view; forms3 |
| View Panels/Configuration and Restore default layout | Eight panels hidden/collapsed/visible; User/Session scopes, inheritance, reopen, conflict rejection and live F7 rebind | `fitter-panels2` | PASS — panels |
| Description/History strip, details and timeline | Real strip controls and history display; guarded historical view/branch/latest | `fitter-history-gui29` | PASS — history |
| History Undo/Redo/Previous/Next/Latest/Branch | Exact retained curves, selection, Preview and owned resources; read-only browsing and explicit branch | `fitter-history-gui29`, `fitter-interactions5`, `fitter-limit1` | PASS — history, interactions; retained fitter-limit1 |
| Workspace Clear History | Backup Yes/No/Cancel, import/recovery, retention limits and exact latest state; fresh edit/Undo/Redo | `fitter-history-gui29`, `fitter-limit1` | PASS — history; retained fitter-limit1 |
| Workspace New/Open/Save/Duplicate/Rename/Manager/Close/Delete | A/B isolation, duplicate-name error, native cancel/confirm, manager export/import and exact accepted geometry | `fitter-workspace3` | PASS — workspace |
| Historical Workspace restore | Official095-produced v2 and controlled v1 payload; exact original accepted values, row selection and unshifted provenance through Save/Close/reopen | `fitter-legacy-gui1` | PASS — legacy |
| Native close during load; missing/stale source; Session change; storage failure | Actual guarded dialogs, cancellation and subsequent usable recovery; exact accepted/durable rollback | `fitter-lifecycle3` | PASS — lifecycle |
| Keyboard/scroll/accessibility | 1100×700, 1280×840 and 1800×1000; enlarged fonts, Tab/Shift-Tab, arrow/Enter/Escape, wheel, mapped popup inside screen | `fitter-view2`, `fitter-history-gui29` | PASS — view, history |

Numerical comparisons are recorded alongside each model, publication, selection
and lifecycle fixture, including canonical source SHA. The 131073-point linear
case checks every accepted coordinate and records maximum physical error
1.2501111257279263e-13. The combined model matrix uses two explicit saved
Workspaces so it respects the existing 8 MiB complete-History bound. The separate
limit test verifies truthful rejection and exact rollback rather than raising
the limit or discarding history.

Evidence names in the last column resolve to `package-gui2/fitter-NAME`,
except explicitly named supplemental/form/retained-limit runs. The final archive
smoke also reruns the History-limit recovery fixture. That separate receipt is
required before publication and is not presumed by this table.

`package-supplemental1/fitter-inventory` records 52 mapped interactive controls
and eight menus, including labels, enabled state and accelerators. Its native
Add Dataset, Open sample, Publish sample, parametric/radial settings buttons,
scrollbar and pane-divider actions all pass. Inventory alone is not counted as
an executed action.

`package-fitter-forms3/form-coverage.tcldict` records all 45 actual form fields:
three source-style fields, 35 shared View fields and seven radial-fit fields.
Each field was operated through native input, with RGB/opacity, chooser Cancel,
Reset where present, invalid-spacing rollback and preserved exact geometry.
Radial clockwise/degree/cut settings were checked against independent physical
circle values. The 117 screenshots and action trace belong to that actual run.

The matrix asserts only the executed actions/values. It does not claim all
possible combinations of mathematical inputs. Earlier failed product or harness
diagnostic runs remain separate from the successful evidence listed here.
