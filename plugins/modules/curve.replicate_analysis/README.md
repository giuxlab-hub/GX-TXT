# GX-TXT Replicate Curve Analysis

SPDX-License-Identifier: GPL-3.0-or-later

`curve.replicate_analysis` performs statistical characterization of repeated X/Y curve measurements or digitizations from one or more canonical GX-TXT Datasets. It produces consensus curves, uncertainty components, fit-ready data and reusable derived Datasets. It does not fit a physical model and does not implement a private plotting subsystem.

## Normal workflow

- Select the primary Dataset.
- Use the framework-owned **+ Add source** control for additional canonical Datasets.
- Bind X and Y, and Family when present.
- Leave **Repeated-data handling = automatic** unless a legacy ordered-row file is intentionally being used.
- Leave Replicate blank/automatic unless the Dataset has a real curve/replicate identifier.

The normal workflow treats CSV row order as non-semantic. If an explicit replicate/curve identifier exists, the trace-based statistical path is used. Otherwise each source/family is treated as an unlabeled repeated-point cloud without inventing a replicate count.

## Statistical paths

### Explicit replicate/curve identifier

The module preserves exact trace membership, normalizes each trace to unique ascending X, interpolates traces on the statistical common grid, calculates consensus and dispersion, and estimates within-source/between-source variance components with the established unequal-count one-way random-effects decomposition.

### Unlabeled repeated-point cloud

Every digitized point is preserved. A deterministic local regression estimates source consensus and local residual dispersion. Between-source dispersion is evaluated from the source consensus curves. No artificial `r1/r2/r3` traces are created and `y_sem` is not invented when the number of statistically independent repeats is unknown.

## Published Datasets

The module publishes three compact long-form Datasets:

- `curve.replicate.traces`
- `curve.replicate.profiles`
- `curve.replicate.family_summary`

These Datasets are the scientific source for all four graphs. There is no per-trace or per-profile Dataset fan-out.

## Files

The analysis produces:

- `consensus_for_fitting.csv`
- `uncertainty_profile.csv`
- `replicate_statistics.csv`
- `source_statistics.csv`
- `replicate_analysis_summary.txt`
- `render_cache.mat`

Graph artifacts:

1. `01_replicate_overlay.png`
2. `02_consensus_uncertainty.png`
3. `03_uncertainty_components.png`
4. `04_family_uncertainty_summary.png`

The visible graph owner is always `curve.replicate_analysis`.

## Uncertainty-band rendering for curve families

`plot.dataset` rejects an uncertainty band attached directly to a family-grouped Series. The module resolves this through public Dataset-family expansion, without modifying the shared renderer. When a replicate consensus Series has both `family_variable_id` and `band`, the bridge reads family membership through `TABLE_STREAM_API_v3`, expands the family into ordinary exact-value filtered Series, removes the family-grouping field from each expanded Series, and preserves the lower/upper band bindings.

No Dataset file path or CSV representation is opened to perform this expansion. The same Table Stream path is used to obtain family-summary tick labels. Saved Sessions with `family_index` and `secondary_variable_id=family_value` are translated at render time. New Sessions bind `family_value` directly as the family grouping variable.

## Provider-neutral Dataset access

Input data are resolved exclusively from Analysis Source Dataset IDs and read through `TABLE_STREAM_API_v3`. The module does not open canonical CSV paths, inspect CSV headers, or fall back to direct file parsing. Replicate-ID auto-detection uses Analysis Source variable metadata only. This supports provider-neutral Dataset access for CSV, HDF5, materialized and other framework-backed representations.

The Octave-to-Tcl graphics bridge uses `gxtxt_persistent_bridge_readline()` like the framework Plot Dataset bridge, preventing a temporary empty pipe read from being misinterpreted as EOF.

## Graphics architecture

The module contains no private scientific renderer. The module does not call `plot()`, `bar()`, `errorbar()`, `legend()`, `xlim()`, `ylim()`, `gxtxt_plot_new_figure()` or `gxtxt_print_png_atomic()` for result graphs.

The graphics path is:

```text
curve.replicate_analysis numerical analysis
        -> canonical derived Datasets
        -> module-owned Graph Series
        -> PlotSpec v2
        -> PLOT_DATASET_API_v3 / plot.dataset renderer
        -> producer-owned PNG + GX-TXT plot metadata
```

`plot.dataset` is only the rendering backend. Its backend Variant is hidden from the Graphs view; the producer artifact remains under `analysis/curve.replicate_analysis` and is addressed by the module graph ID.

### Graphics precedence

The intended precedence is:

```text
Global Graphics
  -> Module Graphics override
     -> Series override when explicitly set
```

The module exposes no module graph-level line-width field. The hidden Plot Dataset backend is reset to `line_width=inherit` on every render. A Series line width is blank by default. Therefore changing **Global graphics** or **Module graphics** line width changes the rendered graph unless the user deliberately sets an explicit Series line-width override.

### Shared graphical services

The module opts into and preserves the applicable GX-TXT public graphical services:

- Graph Provider API v1;
- Graphics Inheritance API v1, including size, DPI, typography, background, grid defaults and line width;
- common Plot layout controls, including automatic/manual margins, panel gap state and Y-label spacing state transported through the axis override runtime;
- common Axes/Grid controls and display-unit/range state;
- common Legend editor and placement/layout state;
- Graph Series API v1 and the standard Series editor;
- Series Editor Extension API v1 for representation, line/marker presentation and explicit per-Series overrides;
- Level Scale API v1;
- Plot Annotation API v1;
- Plot Region Selection API v1 (`rectangle`) for every graph offering;
- Plot Module API v1 Variants/Clone state;
- Graph Workflow API v1 USE/NON USE and rerender scheduling;
- Render Cache API v1;
- standard export/print/annotation workflows operating on the producer-owned artifact.

For Region Selection, the graphics bridge copies the renderer-generated `.gxtxt_plotmeta` sidecar to the producer artifact, so the framework can convert preview pixels to data coordinates without guessing margins.

### Plot layout and axes

The plugin does not own X/Y limits or layout margins. Those values are owned by the shared GX-TXT axis/layout state. Before the backend render command is created, the graphics bridge projects the current producer graph axis state—including `layout_*` fields—onto the backend graph key. This is what makes the Plots-tab layout sliders and Axes/Grid editor affect the rendered result.

### Legend

Legend content may remain graph-specific when scientifically meaningful, but legend placement, layout, alignment, typography and manual position are common GX-TXT state. The graphics bridge projects the producer legend runtime state to the backend before rendering.

### Series presentation

Scientific identity remains in CORE Graph Series: Dataset, X/Y stable variable IDs, family/secondary variables, filters, ordering, axis, label, enable state and order.

The provider extension stores only additional presentation that is not part of generic Graph Series state: representation kind, explicit color/line style, explicit line width, marker, marker size/fill and opacity. Blank/inherit values do not override Graphics.

### Variants and rerender

All four graph IDs declare `supports_variants=1` and `variant_data_model=series`. Variant Graph Series remain independent. Axes, legend, level scale, graphics and Region Selection remain scoped by the producer graph/variant.

A normal analysis requests a backend `render`; a GX-TXT rerender requests the public backend `rerender` path instead of forcing a new full render. The backend Variant remains non-scheduled and is used only when the producer asks the public rendering service to render.

## Compatibility

Compatibility is governed by the current `module.ini` descriptors and public API contracts.

Required public interfaces include Standard Module API v1, Analysis Source Map/Access APIs, Dataset Variable Schema API v3, Table Stream API v3, Dataset Publication API v2, `NUMERIC_API_v1`, Graph Provider API v1, Graph Series API v1, Series Editor Extension API v1, Graphics Inheritance API v1, Plot Module API v1, Graph Workflow API v1, Plot Annotation API v1, Plot Region Selection API v1, Level Scale API v1, Render Cache API v1, Scientific Plot Framework API v1 and Plot Dataset API v2/v3.

See [the current graphics reference](GRAPHICS_REFERENCE.md) for the supported plotting interfaces.

## dev097 / 15.3 scientific integration

Compatible X, Y and Family units are converted through CORE Units to the first
source's actual units before alignment. Mixing a declared unit with an undeclared
one, incompatible dimensions, or different time origins/references rejects with
an explicit message. Canonical input payloads are unchanged. An absent Family
stays absent; plot preparation no longer treats its NaN placeholder as required
finite auxiliary data.

Public Numeric owns local-cloud fitting, aligned source/replicate moments and
spread envelopes. CORE owns quantity identities, units, availability and report
definitions. Select `sampling_model=independent_traces` only when that assumption
is appropriate for labelled curves; the default leaves SEM unavailable. Clouds
never infer independent repeat counts. Single-curve dispersion is undefined.

The existing three Dataset IDs and their existing Variable IDs remain stable.
Profiles additionally expose counts, component eligibility and variance-truncation
facts. Typed publication streams blocks without building a second concatenated
copy of every profile. CORE metadata uses bounded Dataset-local column bindings;
descriptive trace/source/component summaries use compact tables. CSV and text
reports reuse captured reductions. Unsupported component summaries contain NaN,
not fabricated zero bars. The historical v152 graphics-bridge filename remains a
compatibility path; it now verifies the published CORE records before rendering.

A pre-15.3 cache cannot establish this statistical contract. It is preserved and
requires an explicit analysis recalculation before rerender. New caches retain
captured CORE results; cache-only rerender preserves their payloads. The package
requires dev097 CORE and Numeric APIs.

Each graph writes a matching `*.status.ini` output with its render status,
omitted Series and reason. A Series with no finite observations under its actual
bindings and filters is omitted from that render. Its producer Graph Series
identity remains stored. If all Series are unavailable, no replacement plot is
fabricated: any previous PNG, extra-format export and plot metadata are moved
into `previous_graphs/`. Captured CORE records remain the authority for why a
statistical quantity is unavailable; the graph receipt describes presentation.

Targeted labelled multi-source, single-curve, single-cloud and mixed-family tests pass,
including actual plots, unavailable components, unchanged source payloads and
legacy/tampered cache rejection. A mixed-family test also verifies that two-source
cloud components remain available while a single-source family's components and
SEM stay unavailable, including cache-only rerender. The final frozen consumer
acceptance and package delivery remain pending.
