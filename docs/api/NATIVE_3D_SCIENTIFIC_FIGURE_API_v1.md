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

Numeric tick density uses the actual projected spacing of all four parallel box
edges and the native vector-text footprint. It first chooses two or three
calibrated interior values per numeric axis. Five significant digits are
increased when needed to distinguish adjacent values; compact text may use
three or four digits only if rounding is at most one tenth of the native major
interval and every displayed value remains distinct. The internal label array preserves VTK's
complete major-interval count, leaving corner and omitted slots blank. Its
calibrated values and tick phase start at the declared axis minimum; no source
coordinates are changed. A candidate still containing duplicate strings at
round-trip precision is rejected rather than presenting misleading repeats.
Explicit axis-label arrays and their order are preserved. Resizing, orbiting or changing labels may recreate only the cube-axes
presentation prop to refresh VTK's cached tick intervals; scientific actors,
coordinates, resources, camera and source identities remain under their existing
owners. If a foreshortened axis cannot fit two interior values, it displays one
interior value instead of overprinting two. No extra scientific samples or
geometry are generated to conceal limited display space.

The automatic legend occupies the top annotation band with pixel-based spacing
below the title. An explicit `legend_y` presentation setting retains its requested
position. Automatic top/bottom plot margins reserve pixel space for the current
axis-title, title and legend fonts, including compact viewports. Explicit margin
settings remain authoritative. Native rendering, pan and both world/screen
projection directions use the same rectangle. This does not override manual
legend layout or graphics-quality policy.

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
