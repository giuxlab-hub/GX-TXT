# CORE plot USE / NON USE state gap

SPDX-License-Identifier: GPL-3.0-or-later

## Status

Open against GX-TXT 0.9.7.21.

`plot.dataset` already honors Graph Provider enablement and Plot Variant
enablement. It cannot honor the separate Plots-viewer `USE / NON USE` state
during a later analysis run because that state is not part of a public runtime
contract.

## Existing public states that are already honored

For base graph offerings, Graph Provider API v1 exposes and persists the
provider enable/disable state and writes the enabled graph IDs into:

```ini
[graph_provider]
enabled=...
```

`plot.dataset` reads that public runtime list before calling the expensive 2D
or 3D preparation paths.

For variants, Plot Module API v1 exposes the variant `enabled` state. CORE
skips disabled variants before building/running their variant render command.

These states are not the Plots-viewer `USE / NON USE` state reported by the
user.

## Current USE / NON USE storage

In GX-TXT 0.9.7.21 the Plots viewer stores the displayed Use column in the
private Tcl array:

```text
::GX::graphUse(tree_row_id)
```

The key is a transient tree row ID. `selectedGraphPaths` consults this array
when choosing existing plot artifacts for viewer actions such as rerender or
export.

The state is not exposed as a public graph/variant API, is not represented by a
stable `module_id + graph_id + variant_id` key, and is not projected into the
standard analysis runtime file.

## Why the module cannot skip work from this state

The Octave renderer sees the public Graph Provider and variant runtime state,
not private Tcl GUI arrays. Reading `::GX::graphUse` from module code would:

- depend on a private desktop implementation detail;
- fail for headless/queued execution;
- use a transient UI-row identity rather than a stable graph identity; and
- bypass the normal Standard Module runtime contract.

Therefore `plot.dataset` cannot reliably distinguish viewer `USE` from viewer
`NON USE` during a later standard run with the public 0.9.7.21 APIs.

## Smallest generic CORE extension

If `USE / NON USE` is intended to control future computation, CORE must first
make it a stable graph state. The minimum generic contract is:

```text
module_id + graph_id + variant_id -> use_state
```

and then either:

1. CORE filters NON USE graphs/variants before scheduling their graph work; or
2. CORE projects the state into the standard graph runtime contract so the
   provider can skip preparation and rendering deterministically.

For a Standard Module renderer, a Tcl-only getter is insufficient because the
expensive work runs in the analysis runtime. Scheduling-time filtering is the
strongest option because it avoids starting unnecessary graph-specific work at
all.

The new state should remain distinct from Graph Provider `enabled` and Plot
Variant `enabled` unless CORE deliberately defines a migration that makes them
the same user concept.

## No module workaround

`plot.dataset` 2.1.0 does not inspect private viewer arrays and does not modify
GX-TXT CORE.

## Framework resolution

Resolved by GX-TXT 0.9.7.22 Graph Workflow API v1. USE/NON USE is persisted by
stable base/variant identity and participates in CORE scheduling/runtime while
remaining independent from provider and variant enabled state.
