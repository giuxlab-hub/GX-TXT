# 3D Surface Visualization Demo

Current plugin version: **1.0.3**.

`demo.visualization.surface3d` is a small external GX-TXT demonstration plugin. It validates one complete rectangular XYZ Dataset and renders the same scientific field through persistent public Plot.dataset 3D variants as:

- `surface` → `01_surface.png`
- `mesh` → `02_mesh.png`
- `contour3` → `03_contour3.png`

The plugin uses the original canonical Dataset without republishing a copy. The shared plot window owns the viewpoint, colors, axes, export and rerender settings. The cache holds only Dataset identity and small validation metadata. Analysis Source bindings, Table Stream v3, NUMERIC_API_v1, Graph Provider API v1 and Render Cache API v1 remain in use.

A deterministic Session Generator package, `surface3d_thermal_field_1.0.0.zip`, is bundled under `bundled/` and is also distributed separately. Import it into the existing **GX-TXT Numerical Examples** library with **Session Generator Libraries → Import Generator...**.

See `MANUAL.md` for the complete workflow and validation notes.

## Stable variable identity

Analysis Source selections are resolved through the runtime Variable Schema metadata before Table Stream is opened. Display/canonical names such as `x_mm` are never assumed to be the Dataset `variable_id`; the plugin reads through the stable `dataset_id + variable_id` identity required by GX-TXT.
