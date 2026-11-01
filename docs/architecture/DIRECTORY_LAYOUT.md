# GX-TXT Pipeline directory layout — v0.8.4

SPDX-License-Identifier: GPL-3.0-or-later

```text
gxtxt_pipeline_v083/
├── gxtxt_pipeline.tcl
├── README.md
├── CHANGELOG.md
├── LICENSE
├── core/
│   ├── tcl/                    # orchestration, Module API, Progress API, runners
│   └── octave/
│       ├── analysis/           # Scientific Analysis API generic engine/primitives
│       ├── cache/              # optional Render Cache API v1 lifecycle/fingerprint helpers
│       ├── graphics/           # shared plotting/legend/axes infrastructure
│       ├── io/                 # datasets, INI/CSV, parameter/model-domain readers
│       ├── util/               # reusable validation/progress helpers
│       └── legacy/             # compatibility helpers, not discoverable plugins
├── plugins/
│   ├── modules/
│   │   └── <module-id>/
│   │       ├── module.ini
│   │       ├── runtime/
│   │       └── analysis_definitions/   # optional module-private definitions
│   ├── models/
│   │   └── <model-id>/
│   │       ├── model.ini
│   │       └── runtime/
│   ├── instruments/
│   │   └── <instrument-id>/instrument.ini
│   └── analysis_definitions/
│       └── <definition-id>/analysis.ini # reusable global definitions
├── services/
├── docs/
├── examples/
└── tests/
```

## Ownership rules

- `core/` contains only reusable framework infrastructure and generic operations.
- `core/octave/analysis/` must not know IR, FTIR, valve, reactor or other project-specific semantics.
- `plugins/modules/<id>/` owns the executable plugin/job boundary and any truly module-specific runtime.
- `plugins/models/<id>/` owns mathematical models; Model Plugin API remains distinct from Scientific Analysis Definition API.
- `plugins/analysis_definitions/<id>/` owns reusable declarative data-flow definitions.
- `plugins/modules/<id>/analysis_definitions/` owns definitions intentionally private to one module.
- adding a conforming plugin/definition must not require editing a central registry.

## Discovery

```text
plugins/modules/*/module.ini
plugins/models/*/model.ini
plugins/instruments/*/instrument.ini
plugins/analysis_definitions/*/analysis.ini
plugins/modules/<module-id>/analysis_definitions/*/analysis.ini
```

## Scientific helper ownership

Reusable operations such as expression evaluation, comparison, normalization, aggregation, crossing, masks and filtering belong to `core/octave/analysis/`. A scientific plugin should call these framework APIs rather than copying/forking the implementation.

Likewise, Graph Provider renderers use the common graphics APIs. v0.8.2+ applies final per-plot/per-panel Axes/Grid state transparently in the common PNG finalizer. `core/octave/cache/` is optional framework infrastructure; legacy module-owned render caches remain valid.

## GX-TXT v0.8.4 additions

```text
core/octave/analysis/        Scientific Analysis API v1 executor, operation registry and kernels
core/octave/units/           Unit / Dimension API v1
core/octave/cache/           Render Cache API v1 + provenance helpers
docs/reference/              generated installed plugin/contract reference
tools/                       framework maintenance/generation tools
```

Every new/updated discoverable plugin resource must provide Documentation API v1 metadata in its descriptor and a plugin-local guide. Normative API specifications remain under `docs/api/`; generated files under `docs/reference/` are informative snapshots of the installed plugin set.

## v0.8.8 user-local working-directory profiles

Working-directory profiles are intentionally outside the source tree and session tree:

```text
$XDG_CONFIG_HOME/gxtxt_pipeline/working_directory_profiles.ini
```

or `~/.config/gxtxt_pipeline/working_directory_profiles.ini`.

## v0.8.8 module dataset publication requests

A Standard Module API module may create transient publication requests under its own analysis output directory:

```text
<session>/analysis/<module-id>/dataset_publications/*.ini
<session>/analysis/<module-id>/dataset_publications/processed/*.ini
```

The framework consumes requests only after successful analysis execution and updates `<session>/metadata/datasets.ini`. Plugins must not edit the Dataset Registry directly.
