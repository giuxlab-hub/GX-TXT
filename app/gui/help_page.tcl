# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildHelpPage_before_documentation_browser {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Help tab
    set f .top.nb.help
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.modules -text "Module catalog..." -command ::GX::moduleHelpDialog
    ttk::label $f.buttons.note -text "Description, inputs, outputs, and plots for every available module."
    pack $f.buttons.modules $f.buttons.note -side left -padx 4
    grid $f.buttons -row 0 -column 0 -columnspan 2 -sticky w -padx 8 -pady {8 0}
    text $f.txt -wrap word -font TkDefaultFont -state normal
    ttk::scrollbar $f.sy -orient vertical -command [list $f.txt yview]
    $f.txt configure -yscrollcommand [list $f.sy set]
    grid $f.txt -row 1 -column 0 -sticky nsew -padx {8 0} -pady 8
    grid $f.sy -row 1 -column 1 -sticky ns -pady 8
    $f.txt insert end {GX-TXT Pipeline v0.9.7.46 - Quick Guide

PHASE 1 - ACQUISITION / IMPORT
1. Choose one Standard Module API acquisition module. Built-in examples are acq.generic_csv and acq.rigol_csv; additional Acquisition Handler Plugin API v1 modules may be installed without core dispatch changes.
2. Select the source file and inspect Preview before importing. For handlers with supports_batch=1 the first normal Browse selection automatically becomes an enabled Pending batch row; use + Add source / Add sources... for more files.
3. Variables are canonical dataset variables. They inherit CSV headers by default and can be edited after import/reopen, including Use, units, semantic roles and value interpretation. RAW provenance remains read-only.
4. Instrumentation starts empty. Add only instruments actually used in the experiment.
5. PHASE 1 preserves RAW source(s) and registers canonical datasets in metadata/datasets.ini with provenance and SHA-256 information. Session files provides read-only inspection of text/CSV/log/config files inside the current session.

PHASE 2 - ANALYSIS
6. Only descriptor-conformant analysis modules appear in Analysis. Modules may use the historical single dataset selector or Analysis Source Map API v1 for N canonical datasets.
7. For a multi-source module, select Source ID -> Dataset ID rows in the framework-owned Dataset sources table. The framework resolves canonical paths; selecting sources does not align scientific data.
8. Bindings describe semantic roles. Multi-source modules expose qualified variables such as primary.Vg1_V or uncertainty.sigma_total; old unqualified bindings still mean the primary source.
9. Run PHASE 2, or use PHASE 1 + PHASE 2 to chain import and analysis only after a successful import. Scientific alignment/join/resampling remains explicit in Scientific Analysis Definitions.
10. Standard Octave modules are executed through a checked runner. A phase fails if Octave fails or if descriptor-declared output files are missing.

RESULTS / PLOTS
11. Results shows Canonical Dataset API entries and analysis outputs. Legacy Rigol-only import_result.ini and summary.tsv are not required for generic CSV sessions.
12. Curve Family Fitting produces fit_parameters.csv, fit_summary.txt, fit_predictions.csv, render_cache.mat and 01_curve_family_fit.png.
13. Rerender uses render_cache.mat and the same generic graphics settings without repeating the numerical fit.
14. Descriptor plots with legend_editor=standard use Plots -> Configure legend...; legend placement (inside/above/below/left/right/manual) is independent from entry layout (row/stacked/wrapped). Place legend center by click... selects manual placement. State is saved in the session manifest.
15. Descriptor plots with annotation_editor=standard use Plots -> Annotate... for non-destructive text/line/arrow/rectangle/ellipse overlays. Save writes JSON only; Export annotated... creates a derived PNG and Print/PDF applies saved annotations automatically.

v0.9.2 / v0.9.3 framework extensions:
- Scientific Analysis plots may opt into a second Y axis with series_axes=left;right; this is a framework API, not a plugin-local axes workaround.
- auto_units=1 scales display values from declared variable units while leaving scientific data unchanged.
- Basic line3/scatter3 plots are available for true X/Y/Z relationships; they are not a substitute for a third independent 2D Y scale.
- Graph Providers may opt into rectangle region selection with supports_region_selection=1; the selected primary-axis data bounds are delivered to the plugin runtime.
- Analysis Source runtime carries per-variable unit and semantic_role metadata from the Dataset Registry.
- Axes / grid now exposes independent X, Y Left and Y Right display units/ranges; time display scaling includes min, h and day.
- Dataset IDs may carry user-authored GX-Markup v1 notes without overwriting producer metadata.
- Plot regions may be rectangle or x_range and can be promoted to Dataset Selection API v1 resources in canonical dataset coordinates.
- Modules may declare config fields type=selection and receive the selected resource through runtime.ini.
- Repeatable Config API v1 provides descriptor-driven dynamic tables with typed variable/model columns and framework-owned Add/Remove rows.
- Mathematical model selectors are named resources and expose a standard Parameters... editor for initial/lower/upper bounds.
- Session files renders .md notes by default; Edit note... opens the GX-Markup source.
- Plugin Install API v1 installs, updates, versions and uninstalls descriptor-driven plugin packages using plugin-package.ini; packages cannot choose arbitrary install paths or execute installer scripts.
- Plugin Bundle API v1 installs a declared set of Plugin Install API packages atomically from one ZIP; any member failure rolls back the whole set.
- v0.9.7.26 adds CORE Storage Auto, capability-based access planning, and reusable Dataset materializations.
- v0.9.7.25 adds backend-neutral table streaming by Dataset and Variable IDs through Canonical Dataset API v2.
- v0.9.7.24 adds backend-neutral CSV/HDF5 dataset publication with atomic finalize and stable IDs.
- v0.9.7.23 adds explicit dual-Y grid ownership and backend-neutral CSV/HDF5 reads through Canonical Dataset API v2.
- v0.9.7.22 descriptor public APIs activate deterministically for Series Editor extensions; graph-addressed Axes and stable graph/variant USE are public CORE services.
- v0.9.7.21 Graph Providers can extend the standard Series Editor through a public, provider-owned callback lifecycle.
- v0.9.7.20 dataset.extract 1.2.0 is a protected CORE / OFF module; its row-filtering and column-projection implementation is unchanged.
- v0.9.7.4 CSV schema snapshots restore previously active columns after Use=no, including published datasets without a RAW provider.
- v0.9.7.3 Stable variable IDs preserve framework bindings across canonical rename; Table Stream v2 converts declared elapsed time and decimal conventions in CORE.
- v0.9.7.2 Curve Family Fitting and Sequential Table Join are protected CORE / OFF modules; their scientific algorithms are unchanged.
- v0.9.7.1 Unit/Dimension handling recognizes FS, dB and dBFS as identity-preserved semantic level units; the framework never infers a full-scale/reference conversion.
- acq.tektronix_current_log is protected CORE / OFF rather than permanently ALWAYS active.

SESSIONS / MANIFEST
16. The Session bar opens or creates sessions, shows the session name, reveals the full path on click, and saves configuration to metadata/manifest.ini.
17. Manifest Format 2 stores acquisition choice, experiment metadata, dynamic instruments, source variables, module state/configuration, per-module dataset-source maps, bindings, graphics, print settings and annotation-document references.
18. Project API v1 provides persistent Projects above Experiment. Project membership uses stable IDs and never moves or duplicates Session/Dataset content. Historical experiment_project text remains recoverable until explicitly associated.
19. Parallel Execution API v1 coordinates independent work items with a correct serial path, bounded process workers, deterministic result association, progress, cancellation and nested-parallel protection. Scientific consumers remain unchanged until they explicitly adopt the API.
20. A module is part of the application only when it has a conforming plugins/modules/<stable-id>/module.ini descriptor.

Documentation:
- API: docs/api/
- Guides: docs/guides/
- Architecture overview: ARCHITECTURE.md.
- Third-party licensing: THIRD_PARTY_NOTICES.md.

License: GPL-3.0-or-later.}
    $f.txt configure -state disabled

}
