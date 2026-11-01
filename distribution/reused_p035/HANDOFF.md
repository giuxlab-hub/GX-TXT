# GX-TXT DEV111 P029–P035 — release handoff

P029–P034 are independently accepted and deposited. P035 is independently accepted by lanes A and B and accepted by MAIN for normal new-only SSD delivery. Publication and subsequent canonical readback are recorded separately in the deposition/readback receipts; release delivery does not activate the owner’s installation.

Accepted immutable sequence:

| Patch | Accepted source | Archive SHA-256 | Canonical delivery |
|---|---|---|---|
| DEV111-P029 | `3673ccc941fad9965d461c8b16ee1380a3e69173` | `d123201f6bdbea1b6002eb2379eec6905d19cb9a2950faeb48251ac124e83230` | /srv/gxtxt/releases/dev111/patches/0029-script-editor-menus-tabs |
| DEV111-P030 | `b61349890ff684510625bfc60d394c50fca1da43` | `71929d3999c2ede5b3d0a85b7fbc0de31cc6773a9834fa8cd6d280a2a3390850` | /srv/gxtxt/releases/dev111/patches/0030-markdown-contract-visualizers |
| DEV111-P031 | `c998fe69626834550164534e22131e9cb8810448` | `40886aa9b4ae88dab262e0a7ee8019b33023ed8ac3a36e4dfc14adfb0a3db827` | /srv/gxtxt/releases/dev111/patches/0031-uml-plot-preview |
| DEV111-P032 | `fc672ead2755c316025711b9915fdcd6beef4909` | `96ad229a771a519c8e45026dd70770581942ec2a3531915098d31c7f00d5f31b` | /srv/gxtxt/releases/dev111/patches/0032-extensible-acquisition-builder |
| DEV111-P033 | `c46767878984f04c4b2fc00fc223f1852a0aad53` | `b39eff6747900e4b0777d3a06ed5805e8142fda3c1d20edebeb9df2baf812776` | /srv/gxtxt/releases/dev111/patches/0033-scientific-scripts |
| DEV111-P034 | `7ae361d67c82f7fce44487a76927c36c846b78b1` | `12393a90c14ab511785763edcd114fc3c21587bc3323dfe32043b2b65509a48b` | /srv/gxtxt/releases/dev111/patches/0034-reusable-comparison-plot |
| DEV111-P035 | `ce34988db2c7500b60f7235b237b2fdb67e5d434` | `8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d` | /srv/gxtxt/releases/dev111/patches/0035-ir-viewer-teaching-cache-bridge |

P035 accepted source `ce34988db2c7500b60f7235b237b2fdb67e5d434`; CORE ZIP SHA-256 `8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d`. Exact accepted baseline P034 `7ae361d67c82f7fce44487a76927c36c846b78b1`. CORE overlay74 paths; guarded CORE baseline2541 files. Canonical delivery destination is `/srv/gxtxt/releases/dev111/patches/0035-ir-viewer-teaching-cache-bridge`. The deposition receipt and independent canonical readbacks establish publication completion.

P035 module companions:

| Module | Version | Original/normal ZIP SHA-256 |
|---|---|---|
| plot.dataset | 4.4.1 | `ef4434b3d4b367b74f50549691c366ecce117197ff05a9031459afc71050c529` |
| viewer.interface_builder | 1.2.13 | `ccbf65948ccc543c10a6ea57662525a5dc1e9963ee979cb7d3308624aacab181` |
| analysis.spectroscopy.ir | 1.2.0 | `03350045212f36de075d0141084728ee679e1770920d03e68771bfa31b316a80` |
| library.spectroscopy.ir.reference | 1.2.0 | `3e1701cf9cfd10bfd512ffbe0288cde591281219127633c38084f6d5913ad904` |
| viewer.ir_spectroscopy | 1.0.1 | `a6f3bd729e09c91a9dd2a458f2c5db475f48bedf84a240eb11684cadd45e0e37` |
| preview.curve_digitizer | 0.1.12 | `57a0ae932bef79c64d597299581f7319ed30548bc0c2a7846bcace34c436c5b2` |

The original supplied Preview is `preview.curve_digitizer_0.1.12_dev111_p032_REQUIRES_CORE_BRIDGE_022.zip`, unchanged. Qualification: `OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST`. Only the expressly authorized focused new CORE022 integration was exercised; the owner module’s full scientific/functional/GUI suites were not repeated. Viewer2.0.26 remains unchanged from accepted P034, original ZIP SHA-256 `ded07ad9a85c79f68fa53866edef9a4a186ef06546882940526b56d9894a1198`.

CORE Cache Bridge review input `GXTXT_DEV111_P032_CORE_CACHE_BRIDGE_022_MAIN_REVIEW.zip`, original SHA-256 `55085c8429eb42bbae89043ee4e3d1e45e74308a77bf0c1a44923d3bf1eb9aac`. Semantically integrated owners: `core/tcl/dataset_preview_cache.tcl`, `core/tcl/dataset_preview_gui_v1.tcl`, `core/tcl/dataset_preview_worker_v1.tcl`. The remaining P035 changes implement previously authorized IR/Library/Generator/API/GUI requirements; no Native2D renderer or unrelated optimization is included.

Apply verified CORE first, then exact companion preflight, then ordinary Plugin Manager installation/update of the external IR provider, genuine IR Viewer and original Preview012. CORE overlay excludes independent core=0 modules and their registry. Preview stays visible, updateable, disableable and removable. Follow normal restart indications. Rollback requires ordinary removal/reversion of new API-dependent companions first. The owner’s live installation has not been activated or modified.

Five normal teaching Generator packages and additive normal Library:

| ID | Version | ZIP SHA-256 |
|---|---|---|
| ir_library_explorer_lab | 1.0.0 | `67db684511b8064789bf334748134bc3b0a1e7959f3de77910b36ecb1b4ee778` |
| ir_spectral_contracts_lab | 1.0.0 | `2d7e57fb2b21a353554e774e33a2aba7ab20b8dfce49d4aacf2767a27f9499f5` |
| ir_viewer_integrated_study_lab | 1.0.0 | `b88eefffdd7dc4a345747cd9f4beb254b690018005a240541f9aabe001e5c9a3` |
| refimp_full_training_ir | 1.1.0 | `7e5ff019daa71919a034bb49bb75881401f927ea5bbbe1c58a046c61a7c977a0` |
| nist_pnnl_ir_faculty | 1.1.0 | `ef1b72fd89e3224c4a0f802a48f46346cb11bd909aef5a344005f65f48287146` |
| org.giuxlab.gxtxt.ir_teaching_labs | 1.0.0 | `71338764583a5b644ce19101d7a923f9042bf0eeefb7e2c9adc8e4aceb08ed41` |

Existing accepted/custom/disabled Generator collections remain preserved. Install the additive teaching Library through its normal owner and select the new generator versions explicitly; no in-place Library Update API is claimed. Four required scientific Libraries remain normal separately managed scientific packages, including real RefIMP training9537.

Independent scoped results already sealed include all5 normal Generate workflows,17 canonical Datasets/96553 rows,19 exact RAW assets, warm/cold source/schema/namespace/HDF5 preservation; all46037 original NIST ordinates checked with separate standard FIRST/LAST/N and historical nominal-DELTAX grids. The historical Library grid difference is explicitly preserved. Known-source Item13 self-retrieval score1 is not independent chemical identification.

Owner-approved source residuals remain REAL_UNVERIFIED for authentic paired PRF, genuine Fluorophores exports and unqualified Andor SIF physical-calibration/2D variants where authentic authorized references were unavailable. Existing synthetic/uncalibrated scopes remain distinct. Synchronous native widget creation remains a documented limitation. No full scientific campaign for unrelated archived generators is claimed.

The genuine native RefIMP Analysis completed against the full 9537-item training Library: reported bulk scan9537, exact shortlist30, published candidates10. Independent A27 independently recalculated all635 processed samples,3 peak/prominence/halfwidth results,612 overlay samples and10 published scores/order:89 checks passed. These are known-source retrieval checks, not independent chemical identification or a claim of exact global ranking of all9537 candidates. All five genuine native teaching Analysis workflows completed; final teaching exports and cold native reopening are independently verified against the final source.

Independent exact A+B acceptance, all32 native GUI conditions, all five final named teaching native-cold checks and MAIN release acceptance are complete. The previous pre-IR public-Plot demos remain explicitly qualified and are not substituted for these final genuine workflows. New-only SSD publication, canonical readback and verified TODO bookkeeping are recorded by the final delivery receipts.

Original Sessions/RAW, accepted archives and owner packages remain unchanged. Minimal essential WIP copying totals13928586 bytes; no whole worktree/validation/build/cache/capture copies or storage-motivated tests. SSD work-agent and release paths share one physical SSD and are not independent off-host backups.


RC08 includes two focused corrections discovered in real acceptance. The existing Session Origin owner allows only lawful append-only receiving import audit events while retaining every creator, parent, scientific and source pin; the same original imported native Workspace subsequently opened without reselecting or rewriting its sources. The existing Tcl automatic-axis planner now refines an empty target-one tick plan and performs range arithmetic as double. Shared Graph presentation places full Comparison legends below the traces in one column, with footer space proportional to displayed series; no native renderer or binary change. Independent actual graphical retakes passed.

The mutable normal Plugin Manager registry is excluded from both CORE payload and baseline guards after complete accepted-P034 source/archive verification. Actual independent A69 applied, checked and rolled back CORE while preserving real normal-Manager registry changes; no registry restore, private adoption or owner installation change.


Final teaching originals are ready: five ordinary portable DEMO Sessions and five complete CurrentHTML ZIPs, 28,632,620 bytes combined. Their exact original filenames and SHA-256 values are in teaching/FINAL_TEN_TEACHING_ORIGINALS_24.json; its assembly-time pending flag is closed by teaching/FINAL_NATIVE_COLD_CLOSURE_25.json and the independent acceptance reports. The teaching README identifies the current complete-legend Workspace and persistent Plot variant for each lab; earlier saved presentation choices remain preserved. Extract each HTML ZIP into a separate empty directory and open its index.html. Import each portable Session through the normal Session owner. The declared scientific Libraries remain external normal managed prerequisites.

Independent final teaching acceptance A33+A35 covers all five closed originals:37 canonical Datasets,109038 rows,eight saved Workspaces and all five HTML closures. RefIMP science retains the A27 independent oracle; NIST additionally verifies both grids/all46037 source ordinates,6636 processed k samples,four peaks/prominence/widths,three published scores and800 overlay points. Tied plateau coordinates are accepted only at an exactly equal-height source maximum; no widened X tolerance or unique-peak claim. Explorer/Contracts use their actual published TUM15 references for score/overlay oracles, never the distinct full9537 grid. Integrated's actual nondefault sequence was independently recalculated in A34:degree1 least-squares baseline,moving_mean9 with declared shrinking endpoints,actual-spacing gradient,mean/L2 normalization;635 processed samples agree to maximum absolute error4.72e-16. Final67's eight scientific members exactly match the closed oracle input before evidence reuse. These are scoped scientific checks, not thousands of independent campaigns inferred from repeated HTML-link assertions.

Independent clean-source gate A30 imports the genuine IR1.0.1 source from its original package, validates/builds/exports through the public Builder, verifies repeat export and all25 normal installed members, and opens the rebuilt native Viewer. Rebuilt native SHA-256 f94cea9fb7064b6dd0c75c4c632f89304f495b06dda79b3be6a12032325179ea exactly equals the original delivered binary. The separate rebuilt ZIP does not replace the delivered original. Intermittent active-child installer refusals were preserved; a subsequent normal install succeeded without guard bypass or lifecycle source modification. The unobserved child state is not classified as a zombie.

Independent final RC08 mechanical scope A37 verifies74 actual postimages,2541 baseline guards,all six module and six Generator/Library originals,35 actual mechanical checks and12 fresh cold public Catalog/native checks. All original companion and teaching ZIPs remain unchanged. The sole new runtime owner sinceRC07 is the existing read-only Description/History Details popup, now using shared UI_FIELD dialog placement; the other37 owner procedures and History text/state reads remain unchanged. Actual independent B11 verifies full popup/Text/scrollbar bounds,copy,Escape and normal close at1024/font18. Candidate Catalog has2799 records/fingerprintc921062c02f52b182f0e1dba0877b5ec467dbf3d52fb2ed21fe6b2999df3e26a.

No accepted P029–P034 artifact, original scientific Session/RAW, supplied Curve package or owner installation has been changed. Existing scientific source verification residuals and unrelated historical debts remain in the unfinished-work register; release identity does not claim those missing-source cases passed.


Final independent GUI evidence is closed:32 unique physical/font/theme conditions across8 startup actors,160 generated five-mode frames,actual native page/field endpoints,numeric axes and source/data preservation. Review combines contact and selected full-size inspections;160 frames is not160 independent full-size glyph inspections. Startup theme is classic;other themes are controlled transitions;the compact1024 cases use their actual maximized state. Scrolling/focus and horizontal table pan/full-row copy remain part of normal use. The compact generic footer may wrap a long internal action ID;the tested full Description inspector is read-only,copyable and now physically bounded.

The independent five-lab native gate reopens the exact final named portable originals,selects the documented current Workspaces and verifies meaningful plots,source identities,native Fit and normal closure. It includes actual normal original A6 installation(all25 members0644),the four normal managed scientific Library prerequisites,35 HDF5 and27 Analysis-member preservation checks,and no new Analysis or9537 scan. Source-stage GUI evidence and exact final applied-CORE/normal-install mode evidence remain distinct;lead audit found all25 A6 bytes and0644 modes exact in its three runtimes.

One NIST cold read-only readiness observation completed at44.5999 seconds after exceeding a30-second harness expectation. This is a retained cold-latency limit,not a passed30-second bound or a claim of responsive startup. An early RefIMP Fit image preceded settled menu repaint and is excluded as settled Fit pixel evidence. Known private GUI/infrastructure cleanup and earlier failed fixtures remain explicitly qualified in formal B.

Formal independent A PASS: `ACCEPTANCE_A.json`, SHA-256 `6419bdf4c92d60a74ff65fc35bc6022127a93b0bb172d2b963179ea5c54f2322`. Formal independent B PASS: `ACCEPTANCE_B.json`, SHA-256 `aa572552cc8504b908d549a538bd8af87759f3d116f2bd08e932b162ad71a68a`. Both bind the exact accepted source, CORE archive, six module companions, six Generator/Library packages and original Preview qualification. MAIN acceptance is included in the evidence.

The small Description/History Details popup correction uses the existing shared UI_FIELD placement owner. Its complete disabled Text, entire scrollbar, native copy, Escape and normal-close lifecycle fit the actual1024/font18 viewport. No scientific state, source identity, native renderer or supplied module was changed.
