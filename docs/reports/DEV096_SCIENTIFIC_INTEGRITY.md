# dev096 scientific and backward-compatibility evidence

SPDX-License-Identifier: GPL-3.0-or-later

All test Sessions are private copies or newly published controls. Acceptance
receipts use canonical Dataset/Variable identities, exact row ordinals, physical
coordinates and byte hashes; a plausible picture alone is not a scientific test.
Evidence paths below are relative to `_evidence_integrated_dev096/` in the
workspace, with selected immutable copies in `docs/reports/dev096_evidence/`.

## Preserved originals and intentional user edits

`integrity-prepublish2.json` passes all preservation checks. The original broad
Session inventory differs from its initial snapshot only in the state pinned by
`integrity-user-confirmation.json`. The user explicitly confirmed the idoc_0004
Workspace edits with “Yes, intentional user edits.” The original failed byte
comparison, `integrity-prepublish1.json`, is retained and is not relabelled.

`workspace-delta1.json` compares inert Tcl data without executing its contents.
Both original retained curves and the complete original 73-step History prefix
are exact. The additional 27-point Sylvania curve and 74th step are preserved.
All 31 recorded Dataset payloads remain byte-identical. No original Workspace,
recovery or preview file was restored over the user's edits. The acknowledgement
pins the current 733-file inventory; it does not waive later unexplained drift.

All 68 files in the separately recorded original STFT Session remain unchanged.
The installation identity and every recorded old ordered-section file are exact:
365233 framework files, 4078 external-plugin files and 572 Session Generator
files. The original 94/159/56 archive/expanded pairs remain matched. Accepted095
archive and restore SHA-256 is
`95e93f9b5f69238205a269ec764facb1bef13e336c9ca4819925ae11bae5e3fe`.
Publication verification is a separate final receipt, never inferred from this
prepublication audit.

## Executed numerical and identity comparisons

| Domain | Actual checks and receipts | Result / limits |
| --- | --- | --- |
| Retained Numeric operations | `numeric-baseline1/results.json`, `package-numeric1/results.json`: reviewed legacy interpolation/calculus/fitting/edge cases, foundation arrays/statistics/complex/units/expressions, hypothesis tests and ANOVA | Four suites pass on official095 and extracted096; no optional-package skips. This is the retained regression matrix, not a claim of every possible numerical input. |
| Native CORE | Fresh extracted-source configure/build and `package-native2d1-ctest.log` / JUnit XML | 26/26 tests pass, including geometry, identities, constraints, selection, composition and presentation. |
| Script Bridge, Supervisor and old APIs | `package-headless1`: nine core regressions and two extended suites, including 11 supervisor safety cases and Native2D Script Bridge | Actual Python/Octave execution and lifecycle checks pass; tutorial script04 remains excluded. |
| Positive translation | `package-headless1/translation.log`, native Fitter models/History/publication checks | AUTO/manual/OFF, physical axes, inverse mapping, signed outputs and invalid-domain recovery; retained/publication coordinates and units checked. |
| Large Fitter | `package-gui2/fitter-large/large-result.tcldict` | Every one of 131073 retained/published coordinates checked; independent maximum physical error 1.2501111257279263e-13. |
| Parametric fitting | `package-gui2/fitter-parametric` and model receipts | Closed periodic spline compared with independent SciPy values; exact original source row IDs retained. |
| Builder legacy behavior | `package-headless1/builder-contracts.log` and affected rerun | Automatic ordering OFF is compared directly with accepted095 across existing methods, including the 536-row control. Optional ordering preserves point/row bijections and explicit closure; temporal data are rejected for permutation. |
| Actual source overlays | `package-gui1/builder-overlay` | Complete Sylvania source 540 rows / 11 observed groups; selected 27/38-row characteristics and disjoint rows 0,2,4. Persistent PlotSpecs, backend prepared XY/ordinals and published training lineage compared exactly. |
| STFT HDF5 | `package-independent-hdf1.json`, `package-headless1/stft-matrix.log`, `stft-types.log`, `stft-cancel.log` | 8385 exact XYZ values / 129×65 grid, complex matrix 2048×513, reconstruction RMSE 1.497736388085181e-16; real 3D/2D GUI receipts in `package-gui2`. Provider/type/reduction/error/cancellation tests retain source bytes and close owned workers. |
| Legacy Workspaces/modules | `package-gui2/fitter-legacy`, `legacy-configuration`, `legacy-history`, `legacy-family`, `legacy-curve` | Official095 v2 and explicit controlled v1 Fitter fixtures restore; 444 Configuration fields / 103 modules, Workbench History and exact family publication regressions pass. |

The user accepts the existing 536-row `built_curve` as the intended fixture and
allows reuse of completed Sylvania/Builder evidence. Its separately named
Eridiana catalog identity remains unverified and non-blocking. No substitute
identity is asserted, and no additional identity-search campaign was performed.

## Material boundaries

Physical printer submission has not been performed: complete TXT/PDF section
exports and the unavailable-printer diagnostic are tested. The existing physical
printer TODO stays open. History keeps its existing 4096-step / 8 MiB bound;
rejection and rollback are tested rather than dropping old scientific steps.
Optional point-order proposals accept 2..4096 points; OFF fitting retains the
existing larger-source workflow. Exact Builder source traces use memory
proportional to their finite rows. Curve Viewer bounded display caches remain
non-authoritative: exact scientific access always reopens the canonical source.
