# GX-TXT Acquisition Handler Capability / Format Registry — v1

**Introduced:** GX-TXT Pipeline v0.9.0  
**Status:** public additive framework API  
**License:** GNU GPL v3 or later

This document is the compact reference for optional acquisition-handler capabilities. The normative import callback contract remains in `ACQUISITION_HANDLER_PLUGIN_API_v1.md`.

## Capability names

| Capability | Meaning |
|---|---|
| `batch` | Framework can present N Pending sources and import enabled rows. `supports_batch=1` also enables it. |
| `progress` | Handler can publish Progress API v1 events through request callbacks. |
| `preflight` | Descriptor supplies `preflight_proc`. |
| `dataset_preview` | Descriptor supplies `dataset_preview_proc` for non-CSV canonical output. |
| `multi_file_group` | Descriptor supplies `group_proc`; many RAW files may represent one logical acquisition. |
| `multi_file_group_inspect` | Descriptor supplies `group_inspect_proc`. |
| `cooperative_async` | Descriptor supplies `begin_proc` and `step_proc`; framework event-loop scheduling is available. |
| `streaming` | Handler is able to process a source incrementally; currently implied by `cooperative_async`. |
| `cancellation` | Descriptor supplies `cancel_proc`; synchronous handlers may also poll `cancel_callback`. |
| `instrument_suggestion` | Inspection may return `instrument_suggestions`. |

Unknown capability names are preserved as declarations but have no framework behavior until defined by a future public API.

## Public queries

```tcl
set handlerId [::GX::acquisitionHandlerLoadModule acq.vendor]
set caps [::GX::acquisitionHandlerCapabilities $handlerId]
if {[::GX::acquisitionHandlerHasCapability $handlerId preflight]} { ... }
```

## Format registry

Stable format IDs are declared in the module descriptor, not hardcoded in the core:

```ini
[acquisition_handler]
formats=vendor.log_v1

[acquisition_format.vendor.log_v1]
description=Vendor log format v1
mime=text/x-vendor-log
extensions=*.log
canonical_formats=csv
```

Queries:

```tcl
::GX::acquisitionFormatRegistryIds
::GX::acquisitionFormatField vendor.log_v1 description
::GX::acquisitionFormatField vendor.log_v1 mime
::GX::acquisitionFormatField vendor.log_v1 extensions
::GX::acquisitionFormatField vendor.log_v1 canonical_formats
```

The format registry is metadata. It never creates a format-specific core dispatch branch.

## Variable-mapping mode (v0.9.6)

This is a handler contract field rather than a capability name:

```ini
[acquisition_handler]
variable_mapping=required|optional|none
```

`required` is the default and keeps existing tabular behavior. `optional` accepts zero or more variables. `none` declares an intentionally opaque source/dataset, allowing the framework-owned batch lifecycle to operate with zero source variables.
