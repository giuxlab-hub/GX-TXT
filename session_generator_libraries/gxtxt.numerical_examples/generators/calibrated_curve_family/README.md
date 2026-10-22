# Analytical calibrated curve family

This registered Session Generator supplies a deterministic synthetic source for
TASK210 Section2.4: **50 source curves ×5 declared affine calibrations ×300
ordered points =75000 calibrated rows**. There are15000 unique raw observations,
not75000 independent measurements. No random noise, fitting, tracing, Analysis
Job, Graph or computed-module result is manufactured.

Use the numerical-examples library's normal Generate Session workflow and select
`calibrated_curve_family`. Library descriptor, distribution hash manifest and
official registration/release integration belong to MAIN. This source directory
does not add a second registry or alter the original `calibrated_digitizer`.

## Source and calibrated coordinates

For curve c=0..49 and ordered point i=0..299, let t=i/299. Source pixel-center
index coordinates are u=100+1000t and v=900−14c−8(2t−1)² in a1201×1001 raster.
Pixel centers use zero-based index coordinates; SVG display positions add0.5.
Subpixel u/v remain unchanged in all five realizations. The PNG is their
deterministic rasterization, not an experimentally acquired or image-extracted
source. Its rounding affects presentation only.

For declared calibration k=0..4:

    x[s] = (u−100)(1+k/1000)/100 + k/100
    y[V] = (900−v)(1−k/2000)/100 − k/200

The five invertible affine maps have distinct scales/offsets. Each mapping is
shared across all points and curves with that calibration key; it is not
independent per-point noise, a repeated acquisition or an estimated uncertainty.
Calibrations are intentionally declared alternatives, not fitted results.
See REFERENCE.md and reference_spec.json for independently checkable exact forms.

## Generated source products

| Dataset ID | Contract | Source meaning |
| --- | --- | --- |
| `calibrated.family.raw` | `table.generic` |15000 unique analytical pixel observations,300 per curve |
| `calibrated.family.source` | `curve_family.table` |75000 transformed source rows,300 per curve/calibration pair |
| `calibrated.family.image` | `image.raster` | Synthetic PNG of50 analytical raw paths |

`curve_key` and `calibration_key` jointly partition the250 physical-coordinate
traces; `point_order` is integer0..299 within each pair. `point_id` identifies a
raw point and repeats exactly five times; `realization_id` is unique per
calibrated row. `family_parameter` is the dimensionless curve index, not a
measured current or hidden physical quantity. Labels never replace keys.
Time and voltage are declared synthetic coordinate units, not instrument claims.

CSV numbers use float64 round-trip text. Every semantic identity is a stable
ASCII string; point order and indices are declared int64. No sorting by X,
averaging, jitter, decimation or reordering is applied to source coordinates.
The generator-owned `session_recipe.configure` creates ordinary Dataset and
Session declarations, using the same route as existing numerical examples.
Its local additions allow explicit coordinate/dtype/source metadata only; no
CORE or Viewer implementation is copied or changed.

## Preview boundary and honest evidence

Use existing explicit Dataset filters/grouping to separate curve+calibration,
and select `x_s`/`y_V` for physical-coordinate Preview. Use `raster_x`/`raster_y`
for original pixel coordinates. A raw point shared across five calibrations is
one source observation; do not infer independent precision from duplicated rows.

The source overlay SVG in `reference/` links the synthetic PNG and exact raw
paths. It is a reference illustration, **not a GX-TXT Preview screenshot or a
rendered scientific-module result**. Actual common Preview raster-overlay and
calibration controls require the accepted public generic CORE contract. The
current Digitizer-specific reader's producer guard must not be bypassed: this
generator never sets `curve_digitizer.plugin_id` or claims Digitizer publication.
Any remaining generic-consumer gap goes through MAIN to CORE1.

Source/API tests can prove generation, identities, units and analytical parity.
They cannot establish installed-GUI responsiveness or acceptance. MAIN allocates
the real GUI and validation queue; there is no authorized GUI operation here.

All source code, synthetic source definitions and original illustrations are
GPL-3.0-or-later. No external download, module dependency or proprietary input is
needed. Runtime generation uses Python's standard library and never compiles code.
