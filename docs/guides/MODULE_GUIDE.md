# Adding a module to GX-TXT Pipeline

GPL-3.0-or-later

1. Create `plugins/modules/<stable-id>/module.ini`.
2. Set `api_version=1` and a stable `id`.
3. Choose `kind=acquisition` or `kind=analysis`.
4. Declare the runner (`standard_tcl` or `standard_octave`).
5. Declare input dataset contracts and outputs.
6. Declare all user configuration under `[config]` / `[config.<key>]`.
7. For analysis modules, declare semantic input roles under `[bindings]`.
8. Put scientific implementation outside `gxtxt_pipeline.tcl`.
9. Add focused tests for descriptor discovery, configuration, manifest round-trip and runtime generation.
10. Do not add a module-specific branch to the core analysis queue.

A module that needs new framework capability should extend the API deliberately; it must not bypass the interface by reading unrelated legacy `cfg(...)` keys.

## Mandatory rule for scientific/numerical modules

Before adding mathematical code to an analysis or other scientific module, read **[GX-TXT architecture overview](../../ARCHITECTURE.md)**. Reusable mathematical primitives belong to the public `math.numeric` / `NUMERIC_API` service. Missing generic capability must be added there first; consumer modules keep domain-specific workflow and semantics.

## Persistent state and derived runtime

Treat persistent user configuration as authoritative and runtime/cache files as
derived operational state:

```text
authoritative persistent configuration
        -> derived runtime/cache
```

Runtime must be consistent, rebuildable and disposable. Prevent avoidable
inconsistency before writing it. If stale, missing or damaged runtime can be
reconstructed, regenerate it from the authoritative state. If it cannot be
reconstructed safely, stop with an explicit diagnostic and a concrete recovery
path; never silently ignore missing Datasets, variables, Graph Series,
Selections, Temporal Sets, panel assignments or other referenced objects.

A Module Reset clears only runtime/cache state and then rebuilds a clean
operational view. It must not delete persistent user-created state. In
particular, a plot reset preserves variants, Graph Series, panel and axis
assignments, styles, titles, labels and layout configuration. A user-created
variant disappears only after an explicit delete action.

In Modules → Runtime, **Reset Module Runtime…** validates the current Session
and active Script/Project references, removes only `cache/<module-id>` inside
that Session, then refreshes resource selectors and status views. Analysis
outputs and render caches under `analysis/` remain available; a later run can
rebuild any discarded module cache. This action preserves registered Scripts,
Session/Project records, Instrument and Experiment text, Interactive Documents
(including Scientific Worksheets), Viewer scenes, canonical Datasets and
Plot Dataset configuration. Missing active references produce a diagnostic
with the affected binding and a repair path before the cache is changed.

For variable_id, dataset variables, units, semantic roles, Use=no and stable plugin bindings, start with [GX-TXT Variables Guide](VARIABLES_GUIDE.md).

## Standard rendering for new analysis modules

When a graph can be represented by the standard GX-TXT renderer, prefer the public `PLOT_DATASET_API_v2` CORE service to configure Graph Series, render or rerender, and retrieve artifacts. This includes supported line plots, multi-series, multi-dataset, dual-Y, variants, and Level Scale. The service remains available when the user disables the `plot.dataset` interface. Check capabilities explicitly. A custom renderer is appropriate only when the required visualization is insufficiently supported by the standard API; existing modules remain compatible. See [the API v2 manual](../api/PLOT_DATASET_API_v2.md) and [the scientific analysis authoring guide](SCIENTIFIC_ANALYSIS_AUTHORING_GUIDE.md).

## Plot controls

Do not add module-specific plot widgets directly to `gxtxt_pipeline.tcl`. Declare the plot and its editable fields in `module.ini`; the Standard Module API creates the controls and runtime section. See `PLOT_MODULE_API_v1.md`.

## Instruments

Do not hard-code oscilloscope/generator/probe metadata into the experiment GUI. Add an Instrument Module API descriptor under `plugins/instruments/` and let the user explicitly load an instance. See `INSTRUMENT_MODULE_API_v1.md`.


## Analysis workspace selection semantics (v0.7.9)

The **Modules** tab selects experiment membership for Analysis. Installed-plugin administration belongs to **Configuration → Modules → Plugin Manager…**. The **Analysis** tab is a working surface, not a catalog: it creates configuration panels only for analysis modules explicitly enabled in the experiment. Disabled modules are not greyed out or collapsed there; they are absent.

Analysis is vertically scrollable. A module may therefore expose descriptor-generated graph selection, calculation fields and input bindings without depending on the desktop height. `Run / recalculate now` remains independent from experiment membership. Disabling a module preserves its saved configuration in the session/manifest; re-enabling it reconstructs the panel from that state.

## GX-TXT v0.7.8 additions

- For user-selectable files/directories, declare `type=file` / `type=path`; do not create module-specific Browse widgets.
- If the module selects a mathematical model, use `model.descriptor_path` and `model.plugin_dir` from `runtime.ini` when optional model-plugin capability data is required. Do not hard-code `plugins/models/...` paths.
- Use the shared Parameter-Set and Model-Domain helpers instead of local copies.
- For long jobs, use `gxtxt_progress_start/stage/update/complete/fail`; do not manipulate Tk widgets and do not overload the normal log.
- A plugin that does not use progress requires no changes.
- No generic External Process API exists in v0.7.8; do not add tool-specific process code to the core.

## Experiment Duplication Policy authoring (dev080)

New or substantially updated GX-TXT modules MUST declare an Experiment Duplication Policy using the public CORE contract when they introduce module-owned Session-persistent state. Modules with no additional privately owned persistent state SHOULD use the minimal explicit empty policy supported by the API.

This MUST is an authoring requirement, not an installation or execution gate. Existing and third-party modules without a policy remain installable and runnable. Their custom configuration may be completely reset in a duplicate; safe omission and fresh configuration are intentional outcomes.

```ini
[experiment_duplication]
api_version=1
```

The minimal policy authorizes no custom configuration copies. Only explicitly classified, independently reusable preparation is eligible. CORE controls mandatory Dataset, Workspace, graph, observation, output and cache exclusions, validates dependencies/ownership and handles transactions. Existing Dataset, Metadata, Publication, Provenance, Script Registry, Interactive Document and Managed Resource APIs remain authoritative. Standard registries provide coarse legacy ownership; arbitrary private keys, filenames and source code are not classification authorities.

Do not implement private filesystem copying or ask CORE to recognize a module by name. Use capability/version discovery and the public `EXPERIMENT_DUPLICATION_POLICY_API_v1` validation contract. Generic scientific field types and declared bindings are excluded even when named `input`. Unlisted configuration resets; selectors and paths start empty. Module execution is explicitly reconfigured on fresh data.

See [Experiment Duplication Policy API](../api/EXPERIMENT_DUPLICATION_POLICY_API_v1.md) and runnable `examples/experiment_duplication_policy/` Python/Octave Builder projects. Builder 1.2.0 uses the same flat descriptor policy contract, preserves schema-version-1 A/B/W project fields and unchanged script bytes, and supplies a minimal policy on rebuild. Old generated ZIPs remain valid without rebuilding.

## dev086 module selection controls

**Module State** provides Enable / Disable / Toggle for the selected ordinary
module; right-click provides the same operations and double-click still toggles.
Search, Type and Group filters compose with **All / CORE / Non-CORE**.
Non-selectable (`selectable=0`, shown historically as ALWAYS) modules stay installed
and enabled, are hidden here, and remain inspectable in Configuration.

The three independent controls to the right of the filters are **Plot**
(`plot.dataset`), **Script Octave** (`analysis.octave_script`) and **Script Python**
(`analysis.python_script`). They replace those rows in this browser. All three
remain CORE installation resources even when disabled for Analysis. Disabling
preserves saved configuration and scientific data. **Tools → Script Module Builder…**
opens the existing Builder; runtime reset uses the existing Session cache lifecycle.
