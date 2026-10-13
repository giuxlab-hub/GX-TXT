# NATIVE_3D_SCIENTIFIC_FIGURE_API_v1

SPDX-License-Identifier: GPL-3.0-or-later

Additive view-owned Native3D presentation. Header:
`core/native3d/include/native_3d_scientific_figure_api_v1.h`.

- `gx3de_view_scientific_figure_set/get`: copied fixed-size specification containing
  enabled, axes/grid and colorbar flags; aspect-scaled world box; original displayed
  scientific min/max for three linear increasing axes; UTF-8 names/units/title/legend;
  scalar limits, scientific label and exact 2..256 RGB palette.
- `gx3de_view_camera_roll`: rotate native camera up about viewing direction using
  the existing native camera rotation/validation operation. No object/data transform.

The existing VTK renderer supplies camera-aware calibrated cube axes, numeric ticks,
major grids and native scalar bar/title. The label camera expands the scene frustum
with an exactly equivalent world/pixel projection, leaving complete labels outside
the plotting rectangle. It follows orthographic/perspective camera and roll. Opaque
background and adaptive physical-resolution text are part of the scientific image.
A view's figure may be disabled; all figure props/rail are then removed. Updating
calibration changes presentation while retaining source objects. Default legacy
views have no figure and retain their existing rendering and navigation cube.

The shared Tcl worker exposes `scientific_axes visible PNG`, `viewport width height PNG`,
`navigate roll delta 0 PNG` and `export_png path width height ?graphics_policy?`.
Resize uses the same native scene/objects. Export uses current effective graphics
policy and native supersampling, bounded by existing pixel/GPU/process budgets.

Only linear increasing scientific coordinate mapping is advertised. Nonlinear or
reversed axes require a future explicit calibrated mapping contract. D3D11 has no
scientific-figure/cell-RGB support and diagnoses UNSUPPORTED. Generic direct RGB/RGBA
also accepts cell-associated colors in VTK; this preserves flat surface cells. Mixing
cell RGB with a point-opacity role is currently unsupported. No scientific smoothing
or publication is performed by this renderer API.
