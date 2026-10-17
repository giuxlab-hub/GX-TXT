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
