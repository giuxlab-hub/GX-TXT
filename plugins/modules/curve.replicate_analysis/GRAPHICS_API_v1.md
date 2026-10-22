# CURVE_REPLICATE_GRAPHICS_API_v1 — public host integration reference

SPDX-License-Identifier: GPL-3.0-or-later

The installed entrypoint `api/curve_replicate_graphics_api_v1.tcl` defines `::GX::CurveRepGraphicsV1`. Ordinary Module public API activation sources that entrypoint, whose final statement calls `activate`. Reading inert discovery metadata does not source/activate it.

| Exact Tcl signature | Actual effect / return |
| --- | --- |
| `::GX::CurveRepGraphicsV1::ensureSeries graphId ?variantId=""?` | Returns the empty Tcl result. With no current Session it returns without change. Preserves existing nonempty Series; otherwise copies actual base Series into the requested Variant, or seeds configured graph defaults only for actually available source Datasets. |
| `::GX::CurveRepGraphicsV1::activate` | Returns integer1 after registering the provider's existing Series Editor Extension. It replaces that provider's prior registration, if present. The entrypoint automatically invokes this hook. |

`graphId` is an actual declared graph ID for `curve.replicate_analysis`; `variantId` is the exact optional Variant ID, with empty meaning base. Module identity, graph identity, Variant identity and Series identity remain distinct. `ensureSeries` refreshes the existing Dataset registry when possible but does not manufacture scientific results. Source availability is checked by canonical Dataset identity. It does not reconstruct observations from graph pixels or recompute consensus/covariance.

The extension ID is `curve.replicate_analysis.series_presentation`, registered through the existing Series Editor Extension owner for the provider's overlay, consensus_uncertainty, uncertainty_components and family_summary graphs. Registration supplies its existing `seriesBuild`, `seriesLoad`, `seriesValidate`, `seriesSave`, `seriesClose` and `seriesTableValues` callbacks. Those prefixes are **provider-controlled UI callback contracts**, not independent scientific methods or arbitrary functions callable by a restricted author. The Series Editor supplies their actual host context/lifecycle. The provider's own presentation state is separate from canonical CORE Graph Series identity; it is not a new scientific Dataset store.

Normal trusted-host activation uses the existing owner:

```tcl
::GX::modulePublicApiActivate curve.replicate_analysis CURVE_REPLICATE_GRAPHICS_API_v1
```

This example has side effects (source activation/extension registration); discovery reads only the inert `public_contract` field. Neither operation grants Script Bridge or C++ access. There is no separately registered Python/Octave family or typed C++ method for this graphics integration. Actual numerical Replicate operations retain their separate `CURVE_REPLICATE_ANALYSIS_API_v1` contracts and scientific qualifications.

This reference documents the existing public host contract. It does not certify scientific or installed GUI acceptance. Historical integration details remain in `GRAPHICS_V151_IMPLEMENTATION.md`.
