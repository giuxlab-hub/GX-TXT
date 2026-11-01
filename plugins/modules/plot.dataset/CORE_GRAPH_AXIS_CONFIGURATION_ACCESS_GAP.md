# CORE graph-axis configuration access gap

SPDX-License-Identifier: GPL-3.0-or-later

## Status

Open against GX-TXT 0.9.7.21.

`plot.dataset` 2.1.0 does not add a private axis editor to the Analysis graph
configuration dialog. The existing 2.0.1 axis-authority rules remain in force.

## Requested workflow

The Analysis `Configure...` workflow for one stable graph or variant needs an
`Axes...` action that edits the same framework-owned axis state already used by
the Plots viewer. The stable target must be expressible as:

```text
module_id + graph_id + variant_id
```

with an empty `variant_id` for the base graph.

## Current CORE storage and UI

GX-TXT 0.9.7.21 already stores axis overrides separately per graph key and
persists them for base graphs and variants. The existing Plots-tab `Axes...`
dialog edits that state.

However, the callable `axisConfigDialog` derives its target from the currently
selected Plots artifact. It is not a public graph-axis service addressed by
`module_id + graph_id + variant_id`.

The Analysis `moduleGraphConfigDialog` is descriptor-generated. Its public
configuration field model provides ordinary values such as string, choice and
boolean fields; it does not provide a provider action that can open the
framework axis editor for the graph currently being configured.

## Why the module cannot solve this privately

A plugin-side solution would require at least one prohibited behavior:

- reading or writing the private `axisOverride` Tcl array;
- wrapping or replacing the private Analysis graph configuration dialog;
- making the Plots viewer select a particular artifact as an indirect way to
  address the axis editor; or
- adding another set of min/max/unit fields to PlotSpec or descriptor config,
  recreating the dual-authority defect fixed in `plot.dataset` 2.0.1.

None is acceptable. The scientific axis state already exists in CORE and must
remain the single authority.

## Smallest generic CORE extension

Expose the existing axis configuration service through a public stable graph
reference. One minimal form would be a public operation equivalent to:

```text
openGraphAxisEditor module_id graph_id ?variant_id?
```

where the operation edits the existing CORE axis state and persistence; it must
not introduce another registry.

To place that action inside Analysis `Configure...` without module-specific
CORE branches, the descriptor-driven graph configuration UI also needs a small
generic action-extension mechanism, or an equivalent standard `axes_editor`
capability that invokes the public operation for the graph/variant being
configured.

A lower-level public get/set API could also satisfy programmatic consumers, but
the user-facing requirement still needs a generic way for the Analysis graph
configuration dialog to invoke the existing editor for an explicit stable
graph reference.

## No module workaround

`plot.dataset` 2.1.0 does not create a second axis state and does not modify
GX-TXT CORE.

## Framework resolution

Resolved by GX-TXT 0.9.7.22 Graph Workflow API v1. Analysis graph Configure and
the variant editor can call the standard graph-addressed Axes service. The same
CORE axisOverride state remains authoritative.
