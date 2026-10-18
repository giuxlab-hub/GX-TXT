# GX-TXT dev-102 — public validation case inventory

The following **19 original Tcl cases** and their three exact-byte shared helpers were selected from the accepted dev-102 archive. Files are intentionally unchanged relative to that source. This matrix records *intended coverage* and invocation prerequisites, not a new PASS result on the publication machine.

| Case | Scope | Requirements / execution policy |
| --- | --- | --- |
| `core_contracts.tcl` | Same-owner replacement, Dataset Metadata contributor identity and rollback | **Opt-in CLI runner**; exact dev-102 framework, HDF5/CSV services, fresh scratch Session |
| `legacy_publication.tcl` | Legacy Replicate publication and retained canonical data | **Opt-in CLI runner**; existing legacy scientific runtime, fresh scratch |
| `metadata_bridge.tcl` | Contributor provenance through Python/Octave and portable Session | **Opt-in CLI runner**; registered bridge runtimes, fresh scratch |
| `replicate_contracts.tcl` | Physical identities, statistical preflight, managed Job, atomic publication | **Opt-in CLI runner**; Numeric/Script Jobs, fresh scratch |
| `replicate_xy.tcl` | XY path, topology, calibration sensitivity and hierarchical statistics | **Opt-in CLI runner**; Numeric spline/reducer provider, fresh scratch |
| `worksheet_contracts.tcl` | Typed Workbook scientific semantics and binding | **Opt-in CLI runner**; Worksheet 2.1 and canonical source services |
| `automation_contracts.tcl` | Worksheet Script Job proposal, Filter Views and controlled adoption | **Opt-in CLI runner**; supervised Python scientific execution |
| `native_paths.tcl` | Native2D exact perimeter/area and topology rejection | **Manual**; absolute path to built compatible `gx2dtcl.so`, fresh output directory |
| `metadata_acquisition.tcl` | Acquisition metadata attribution | **Manual**; genuine supported synthetic PNG source fixture (not provided here) |
| `replicate_bridges.tcl` | Script Bridge Replicate interactions | **Manual**; prior controlled canonical Session and Python/Octave services |
| `replicate_equivalence.tcl` | Published Viewer results versus independently captured golden result | **Manual**; prior controlled Session and separate, approved golden scientific receipt |
| `deposited_gui.tcl` | Installed GUI acceptance and Replicate launch | **Manual GUI**; Debian local X11 and controlled prior Session |
| `grid_benchmark_gui.tcl` | Native Worksheet grid interaction/performance | **Manual GUI**; native C++/Cairo, xdotool, deterministic 20,000-row generator helper |
| `preview_gui.tcl` | Dataset Preview native retained visibility and plot bounds | **Manual GUI**; prior scientific source, xdotool/ImageMagick capture |
| `replicate_gui.tcl` | Replicate Viewer lifecycle, edits and Plot integration | **Manual GUI**; prior study, native Viewer, xdotool/ImageMagick |
| `replicate_xy_gui.tcl` | Returning/closed XY path interactions | **Manual GUI**; prior controlled results, xdotool/ImageMagick |
| `selectors_gui.tcl` | Contained selector UI and shared Viewer controls | **Manual GUI**; local X11, xdotool, ImageMagick |
| `worksheet_gui.tcl` | Native grid gestures and exact source preservation | **Manual GUI**; native Worksheet grid, X11, xdotool |
| `worksheet_workflows_gui.tcl` | Guided binding, native presentation, Python Jobs, Filter Views | **Manual GUI**; local X11, Python, xdotool, prepared controlled sources |

## Included dependency helpers

The directory names intentionally reproduce the original accepted validation tree:

- `validation/official_dev099/project_common.tcl` — starts GX-TXT against a fresh output directory and isolates XDG paths, Session resources and Jobs.
- `validation/official_dev099/workspace_common.tcl` — derives a synthetic Workspace Dataset and source reference from the project helper.
- `validation/official_dev100/worksheet_fixture.tcl` — deterministic synthetic Dataset generator used by native Worksheet tests. It is a **validation fixture**, not a Session Generator Library entry.

These files are not new code implementations. See the cryptographic source manifest for their precise release provenance.

## Test execution and results

The branch is an independently accessible **source distribution** for tests. The original official Debian release recorded bounded passing tests, along with unsuccessful earlier attempts and platform limitations; that report has **not** been copied here. At branch publication, the above cases are marked **NOT RERUN** in this separate worktree. Static checks verify provenance and completeness only.

For the seven opt-in CLI cases, `python3 tools/validate_suite.py run CASE --framework DIR --execute` creates isolated temp storage and preserves its output logs. Native/GUI/multi-stage cases require controlled preparation and have no one-click universal runner. Never point the test suite to an installed or live framework with real scientific Sessions.

Future suites should state meaningful independent reference values, input hashes, actual units and tolerances. A framework test and a Session Generator are separate deliverables, even if a generator can create a synthetic fixture for a validation case.

## Dev-103 — selected original source-only tests

**Source baseline:** `0.9.8.10-dev-103`, public [main commit](https://github.com/giuxlab-hub/GX-TXT/commit/e07376e0a62e0eecf1737da33c87bbbb41273f4b). All 11 files preserve their official source SHA-256. **Status: NOT RERUN in the validation branch publication workflow.**

| Original source | Coverage and prerequisites | Execution policy |
| --- | --- | --- |
| `cache_contracts.tcl` | Canonical Preview/cache invalidation and scientific provenance, fresh Session | Manual Linux synthetic-data test |
| `media_cache.tcl` | Supported media Preview and disposable cache lifecycle, fresh synthetic data | Manual Linux test |
| `catalog_inputs.py` | Original deterministic synthetic raster and NMRPipe fixtures; NumPy/Pillow | Input generator for controlled tests, not a Session Generator Library |
| `catalog_seed.tcl` | Fixture helper imports synthetic image/NMR to a new Session | Manual helper; requires `catalog_inputs.py` output |
| `catalog_workflow.tcl` | Viewer catalog/group icons, enable/disable and opening | Manual local Debian X11 GUI only, needs synthetic fixture |
| `catalog_persist.tcl` | Checks catalog selection/configuration persisted by prior GUI workflow | Manual check after an isolated GUI run |
| `digitizer_inputs.py` | Synthetic large digitizer publication payload, calibration provenance | Input fixture generator only; no private datasheets |
| `digitizer_publish.tcl` | Canonical synthetic Digitalizer source publication | Manual; needs synthetic input files and fresh Session |
| `remote_seed.tcl` | Builds an isolated canonical node Session for remote protocol tests | Manual fixture producer, no actual remote Node started |
| `remote_checks.tcl` | mTLS compute-node typed scientific range/Job protocol | Manual only; separate controlled test agent and credentials required, **not included** |
| `remote_security.py` | Negative TLS/protocol/authorization checks | Manual only; separately configured, authorized test endpoint required |

The source-only list intentionally omits dev-103 release delivery, rollback, installation, private GUI Session/2D21 case-specific studies and evidence-manifest generation. The public code here does not contain copied private Sessions, TLS keys, user data, or the PDF-based test generators previously excluded from `main`.

The **dev-102 19 cases and three shared helpers remain unchanged**. The Python source verification function now checks both cryptographic inventories while preserving its restricted opt-in **dev-102** runner behavior.

## Dev-104 original scientific validation sources

**Scope:** dev-104 [main commit](https://github.com/giuxlab-hub/GX-TXT/commit/d99268348aa55b62f3a1e21ec3672f04504a740d). **Status:** source only, NOT RERUN on Windows or in CI. All 16 original test/helper files have immutable SHA-256 entries in `source-manifest-dev104.json`.

| Original filename | Scientific or interface scope | Manual prerequisites |
| --- | --- | --- |
| `builder_contract.tcl` | Public Viewer design schema and safety checks | Fresh synthetic output, dev-104 |
| `builder_smoke_gui.tcl` | Designer/Preview layout, native interactions and Undo/Redo | Debian X11, xdotool and helper below |
| `p0_workflow.tcl` | Shared X11 UI automation and focus/grab checks | Manual GUI helper; not standalone |
| `project_contract.tcl` | Project grouping and atomic identity guards | New synthetic Project and Session |
| `project_scale.tcl` | Hierarchical Project navigation performance | Controlled large synthetic Project fixture |
| `print_recipe_contract.tcl` | Typed canonical Dataset printing recipes | Fresh synthetic Session |
| `print_pipeline_contract.tcl` | Graphs, annotation and PDF composition | Depends on print recipe helper |
| `print_media_contract.tcl` | Raster/media source fidelity and qualified modes | Pillow and print recipe helper |
| `print_native3d_contract.tcl` | Native3D scientific Print source | Compatible native renderer |
| `print_pdf_contract.py` | Independent PDF rendering/text checks | Poppler/qpdf and controlled synthetic inputs |
| `cups_contract.tcl` | Cancellable printer discovery and guarded submission | Fake backend only |
| `cups_fixture.py` | Synthetic printer process replies | Disposable fake backend; no real printer |
| `cups_fixture_setup.py` | Creates temporary fake-CUPS tools | Private synthetic test root |
| `preview_subscription_contract.tcl` | Preview subscription/cache lifetime | Script Jobs and recipe helper |
| `request_contract.tcl` | Managed request cancellation/lifecycle | Helper below |
| `request_fixture.py` | Bounded synthetic subprocess responses | Not a Session Generator Library |

These original sources may require other controlled fixtures not distributed here. They are documentation and reproducible test inputs, **not** newly measured runtime PASS results. Original scientific Sessions, confidential PDFs/generators, deployment scripts and printer credentials are excluded.

## Dev-106 — selected source-only scientific tests

Framework: 0.9.8.10-dev-106. Main commit: db10ef525670944f031bcb33b8d9968d6bcac312. Status: NOT RERUN. All source bytes correspond to archive validation/integrated_dev106/.

| File | Scope | Execution policy |
| --- | --- | --- |
| core_contract.tcl | Source import/public CORE and Session guards | Manual Linux only |
| debug_contract.tcl | Managed Python/Octave debugger and Job lifecycle | Manual Linux only |
| native_contract.tcl | Native document bridge and fresh output | Manual Linux/native ABI only |
| signal_contract.tcl | Signal public mathematical contracts | Manual Linux/Octave only |
| signal_negative.tcl | Invalid Signal request rejection | Manual Linux/Octave only |
| signal_reference.py | Independent Signal numerical values | Manual scientific Python only |
| statistics_reference.py | Independent statistics reference values | Manual scientific Python only |
| xml_bridge_contract.tcl | XML/Script Bridge public API | Manual Linux only |
| document_preview_gui.tcl | Bounded documents/source inspection | Manual Debian X11 GUI only |
| editor_close_gui.tcl | Editor clean/dirty window close | Manual Debian X11 GUI only |
| output_identity_gui.tcl | Output stream identity/selection | Manual Debian X11 GUI only |
| source_modes_gui.tcl | Document source mode handling | Manual Debian X11 GUI only |
| statistics_gui.tcl | Statistical Viewer synthetic Dataset | Manual Debian X11 GUI only |
| streams_gui.tcl | Separated logs and Unicode | Manual Debian X11 GUI only |

These original sources may need supplementary controlled fixtures and a version-specific bootstrap that are not distributed here. They are not universal standalone test commands, not automatic runner entries and not new runtime PASS evidence.

## Dev-107 — original source-only test selection

Reference release: 0.9.8.10-dev-107, main 2e404977430906f6bc711239d5d934b72f0a6080. Original location: validation/unified_dev107/. Status: NOT RERUN.

| Filename | Coverage | Execution policy |
| --- | --- | --- |
| cpp_policy_cases.py | Resolved Clang authoring policy and explicit refusals | Manual / controlled Debian fixture only |
| component_gallery_gui.tcl | Viewer component previews and lifecycle | Manual / controlled Debian fixture only |
| native_gui_helpers.tcl | Shared controlled UI test helpers | Manual / controlled Debian fixture only |
| native2d_temporary_gui.tcl | Session-free Native2D display and interactions | Manual / controlled Debian fixture only |
| native3d_component_gui.tcl | Independent Native3D GUI host lifetime | Manual / controlled Debian fixture only |
| plot_display_gui.tcl | RAM-only public Plot display | Manual / controlled Debian fixture only |
| debugger_gui.tcl | Managed Python/Octave debugging presentation | Manual / controlled Debian fixture only |
| debug_edges_gui.tcl | Debugger edge and lifetime behavior | Manual / controlled Debian fixture only |
| editor_layout_cases_gui.tcl | Script Workspace pane layout and persistence | Manual / controlled Debian fixture only |
| demo_command_ownership_gui.tcl | Viewer demo commands and ownership | Manual / controlled Debian fixture only |
| development_parity.py | Restricted Viewer development parity checks | Manual / controlled Debian fixture only |

No private debugger WordPress package, its tutorial images, original user Sessions, release install scripts, receipts or credentials were added. These source-only tests are not automatically executed; several require original supporting fixtures.
