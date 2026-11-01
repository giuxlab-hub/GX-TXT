# CORE integration blocker — Series Editor extension provider activation

SPDX-License-Identifier: GPL-3.0-or-later

## Status

GX-TXT 0.9.7.21 implements **Series Editor Extension API v1** and its callback
lifecycle is sufficient for `plot.dataset` provider-owned per-series state.
The remaining blocker is provider activation, not editor callback semantics.

## Reproduction

On a clean GX-TXT 0.9.7.21 startup, after normal defaults and module-catalog
loading, the `plot.dataset` public API entrypoint is not sourced and no Series
Editor extension is registered:

```tcl
set root /path/to/gxtxt_pipeline_v09721
cd $root
set argv0 __not_main__
source gxtxt_pipeline.tcl
::GX::defaults
::GX::loadModuleCatalog
puts "v2_api=[llength [info commands ::GX::PlotDatasetAPIv2::apiInfo]]"
puts "extension=[::GX::seriesEditorExtensionFor plot.dataset plot.dataset.xy]"
```

Observed result:

```text
v2_api=0
extension=
```

The standard Series editor resolves only providers that have already called
`::GX::seriesEditorExtensionRegister`. Module catalog discovery reads the
descriptor but does not activate the module's public API entrypoint or another
provider initialization entrypoint.

## Why the module does not work around it

Registering only when `PLOT_DATASET_API_v2` happens to be sourced would make
`Series...` behavior depend on unrelated consumer call order. Sourcing private
CORE files, patching the Series editor, or adding a second registry would break
the public API boundary. `plot.dataset` 2.1.0 registers `plot.dataset.presentation` when
`PLOT_DATASET_API_v2` is explicitly activated. This makes the provider area
fully functional for that process, but normal clean-start `Series...` behavior
still cannot depend on the registration. The standalone public `openEditor`
therefore remains available and no private activation workaround is used.

## Smallest CORE correction required

Extend the existing public module/provider loading contract with one generic
activation mechanism that is executed before Series Editor extension lookup.
For example, a descriptor-declared provider initialization entrypoint (or an
equivalent existing-loader extension) can be loaded once during module catalog
activation and call the already existing `seriesEditorExtensionRegister`.

Requirements:

- keep Series Editor Extension API v1 as the only extension registry/lifecycle;
- no `plot.dataset`-specific CORE fields or dependency;
- activation must work for any descriptor-based graph provider;
- activation must occur before the standard `Series...` editor resolves the
  module/graph provider;
- activation failure must be explicit and must not silently degrade provider
  persistence;
- headless use must remain possible without forcing Tk widget construction.

No CORE file is modified by this package.

## Framework resolution

Resolved by GX-TXT 0.9.7.22 Graph Workflow API v1. CORE now activates
descriptor public APIs advertising series_editor_extension before lookup.
The module remains version 2.1.0; no provider lifecycle or scientific code
change was required.
