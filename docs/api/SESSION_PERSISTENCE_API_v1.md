# Session Persistence API v1

`::GX::sessionPersistenceCommit` commits the **current open Session's**
framework-owned Manifest Format 2 state. It takes no key/value input and
cannot write another Session. CORE serializes current module, graph, Viewer
and other registered state, validates the new Manifest, and atomically
replaces `metadata/manifest.ini`. It returns the Session path, Manifest path
and SHA-256.

Use the owning semantic API first: Dataset Publication for Dataset output,
Plot Dataset API v3 for plots, Viewer Provider for scenes, Configuration for
supported settings, Dataset Selection for selections, and Interactive
Document for provider documents. Call `sessionPersistenceCommit` when a
headless workflow needs to save the complete current Session state without
using the GUI Save action. Individual provider APIs may also commit after a
completed operation. This API does not expose arbitrary Manifest mutation,
registry arrays, or provider storage paths.

```tcl
::GX::PlotDatasetAPIv3::applySpec $plotRef $spec
set committed [::GX::sessionPersistenceCommit]
```

The caller must have opened a Session through the framework. Dataset
Publication and other transactional services continue to own their own
sidecar/registry commits and rollback boundaries.
