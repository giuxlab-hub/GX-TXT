# Inspect an analytical calibrated family

This source is synthetic. It supplies50 analytical raster paths and five
declared alternative calibrations, not50 experimentally acquired curves or
five independent repeated measurements. It is a focused Preview fixture, not
one of TASK210's four complete generator tutorials.

1. In the normal framework Generate Session workflow, select the current
   registered `calibrated_curve_family` in the numerical-examples library.
   Create a fresh Session explicitly; preserve existing Sessions.
2. In Dataset tools inspect `calibrated.family.raw`:15000 rows,50 curve keys,
   point order0..299, original `raster_x`/`raster_y` in px. Inspect the synthetic
   image Dataset and its source integrity metadata.
3. Inspect `calibrated.family.source`:75000 rows,50 curves,5 calibration keys,
   250 curve/calibration groups,300 points per group. Check `x_s` in s, `y_V`
   in V and unchanged raw pixels. The same raw `point_id` occurs five times;
   each `realization_id` occurs once.
4. In the actual current Preview choose physical X=`x_s`, Y=`y_V`. Use the
   supported explicit filters/grouping to separate both curve and calibration;
   preserve `point_order`. Do not connect the end of one calibration/curve to
   the beginning of another. Controls and public generic overlay behavior must
   be rebaselined on the accepted build rather than assumed from this guide.
5. Where the accepted compatible provider exposes them, deliberately select
   curves/calibrations, Show/Hide, Fit/zoom/pan and resize. Check axes, source
   identity and original-row counts. A display point budget changes only
   presentation, never these canonical counts.
6. Compare source values with the independent equations and exact anchors in
   `reference/analytical_reference.json`. The source SVG overlay is an offline
   reference illustration, not proof of actual GX-TXT Preview operation.
7. Save/close/reopen through ordinary supported GUI controls and check source
   identities. Record real GUI latency/evidence only in MAIN-allocated context.

No Analysis module is enabled or run by this generator. An empty Plots result
list therefore does not mean a precomputed graph is missing. Source images,
reference equations and declarations must not be inserted as computed results.
Some transformed Y values are negative, so log-Y is not universally eligible.
The five maps alone supply no statistical uncertainty or calibration accuracy.

If a generic grouping/calibration/overlay operation is unsupported, retain the
source and report that exact public-owner gap to MAIN. Do not impersonate the
Curve Digitizer producer, fabricate a publication, or alter raw points to make
a GUI control appear supported.
