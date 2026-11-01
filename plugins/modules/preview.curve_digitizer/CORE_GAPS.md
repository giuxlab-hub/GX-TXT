# Focused CORE gaps for full Preview replacement

1. Canonical Table: DATASET_PREVIEW_API_v1/page exposes start/count and
   Variable projection, but no read-only row-predicate parameter. The
   module shows the complete canonical table (up to the normal bounded page).
   A curve/calibration selector for that Table would need an explicit
   public read-only filtered paging contract that preserves source_rows and
   source identity. Do not parse CSV/HDF5 or duplicate table storage.

2. Legacy CORE specialization: DEV111 always keeps the older built-in
   Curve Digitalizer Preview as a specialized view. A presentation-only
   component remains complementary and cannot suppress it or claim primary.
   No CORE changes until this module has real integration acceptance.
   Later migration should replace only presentation-specific routing,
   keeping canonical Dataset/Curve Source/Plot v4/Preview paging services.

3. Native rendering: this module invokes PLOT_DATASET_API_v4 widgetCreate
   inside a Builder-created Preview UI_FIELD section. It is a source-bound
   trusted Tcl GUI callback and uses the existing C++ native Plot engine;
   no independently compiled C++ Viewer binary or private native renderer
   is required. Test real native mount and lifecycle before declaring it
   integrated.

4. Existing PlotSpec v4 with row_filters/ordering_variable_id invokes the
   public Dataset Transform route and the installed DEV111-r3 host currently
   refuses it with a Script Bridge binding-ownership mismatch involving
   CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1. This Preview does not modify CORE
   and avoids the failing transform by preparing a disposable view from the
   existing canonical DatasetPreviewPage service, then rendering exclusively
   through the public PLOT_DATASET_API_v4 prepared-model contract. This is a
   presentation workaround, not proof the underlying Dataset Transform issue
   is repaired.


5. The standard Preview's periodic metadata-matching path used to call
   datasetMetadataContributors() for every published field on each
   observer pass. In the working GX-TXT copy this has been optimized
   separately in CORE to authenticate only match_metadata keys. The
   Preview module cannot override CORE owner checks. Work-copy changes
   have their own audit diff and do not ship in this module package.
6. True off-thread native widget allocation/rendering is not exposed by
   PREVIEW_COMPONENT_GUI_API_v1. The module uses cooperative page reads
   plus Plot v4's existing C++ Native2D presenter. A standalone worker
   must only be added through the existing CORE Managed Job/Preview API.

## Persisted scientific group cache — proposal, not implemented

There is **no missing generic Preview cache API**. Existing public
DATASET_PREVIEW_API_v1 offers source-verified persistent
datasetPreviewCacheRequest, datasetPreviewCacheSubscribe, CacheRead,
CacheInventory and CacheCancel/Unsubscribe. The owner stores Native2D
models and related quality/raster overlays under Session/cache.

A Preview module cannot insert its own arbitrary, versioned 9-group
presentation into that store through a public general-purpose
cachePut operation. The preferred safe approach is to construct an
explicit, canonical, unfiltered selection of all published curve and
calibration keys and ask the existing cache/Job Supervisor for that
standard preparation. On an authenticated hit, reuse its prepared
Plot v4 model, checking source SHA, renderer/source identity, nine
groups and row coverage. On miss, keep the current bounded cooperative
read and use the existing service in a future implementation after
testing the time spent in subscription admission.

If an extension proves necessary, introduce a typed
`datasetPreviewCacheComponentRequest` / `ComponentRead` interface
for provider-owned derived display presentations, with CORE-owned
persistent storage, atomic commit, digest validation, session/source
revision checks, schema/renderer versioning, cancellation, eviction,
and a strict GUI lifetime and callback discipline. **Do not use
private module paths, private Plot buffers or disable provenance.**
No extension patch is generated until the design is reviewed.
