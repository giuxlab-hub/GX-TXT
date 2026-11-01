# Multi-guide assisted tracing and numerical API boundary

SPDX-License-Identifier: GPL-3.0-or-later

This is the maintained adapter rationale for Curve Digitalizer's assisted
tracing. This file deliberately documents the external API interaction that
may require changes when GX-TXT math.numeric evolves.

- **Public provider:** `NUMERIC_API_v1` in `math.numeric`.
- **Public function:** `::GX::NumericAPIv1::interpolate x y xq options`.
- **Invocation:** `::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1`.
- **Location:** `api/curve_digitizer_viewer_api_v1.tcl`, `_assistNumericFit`.
- **Parameters:** ordered cumulative raster path lengths, raster X and Y at
  each guide, sampled cumulative lengths, `method=pchip`,
  `extrapolation=error`.
- **Contract:** valid strictly increasing input abscissas and >= 3 guide
  points for PCHIP; returned `yq` contains samples at `xq`.
- **Fault handling:** unavailable/disabled provider, missing GNU Octave,
  missing functionality, validation errors, worker failures and malformed
  output yield no fitted path. The Python GUI then uses explicitly reported
  local linear guide interpolation and pixel-image corridor optimization.
- **Scientific limits:** fitting is a suggestion, never an authoritative
  calibration or curve; all original guide coordinates are preserved. A CORE
  reference is accepted only when its samples are finite, inside the source
  raster and do not depart excessively from the local guide corridor. During
  segment corrections, the already generated path is NOT refitted globally.
- **Ownership:** the curve points are committed only by the normal Curves tab
  operation after the user presses Accept; Reject never changes the curve.

The bounded matcher in `python/assisted_tracing.py` performs image-based dynamic
programming per guide segment and is independent of the removed native C/X11
tracing interface. It cannot infer the correct curve at unresolved junctions;
users should place extra guides or reject poor candidate segments.

Do not call internal math.numeric workers or Tcl execution internals from
plugins. If NUMERIC_API_v1 changes, adapt only `_assistNumericFit`, retain the
transparent fallback and add a regression fixture.

## Current raster optimization (Curve Digitalizer 1.2.19)

`python/assisted_tracing.py` produces one complete, bounded dynamic-programming
path for each consecutive pair of guides. Each candidate is scored using:

- guide-relative grayscale and RGB similarity;
- signed-magnitude transverse ridge response, sampled normal to the expected
  tangent to discriminate thin traces from broad dark regions;
- a conservative grid penalty for sparse, long horizontal/vertical dark image
  structures (disabled for broadly dark photo-like backgrounds);
- displacement from the reference and penalties on lateral jumps.

The matrix is evaluated only within the raster corridor. Pixels outside the
image are excluded. Guide endpoints are exact constraints, including after
corrections. A segment flagged as ambiguous is a **heuristic warning**, NOT a
probability or a measured tracing uncertainty.

`TraceProposal.segments` retains each candidate interval independently. When
an operator adds a correction, only the split interval is regenerated. When a
guide moves, at most its two adjacent intervals are regenerated. Previously
accepted scientific points are never silently refitted. The proposal stays
transient and reversible; only Curves-tab Accept or Accept segment commits
points with `origin=assisted` into the authoritative configuration.

## Original versus processed source

The image selector offers `auto`, `original`, and `processed`. `processed`
requires a current, fingerprint-matched Image Processing preview; stale results
are rejected. `auto` uses the valid processed preview when it exists, otherwise
the canonical original. Filtering preserves the pixel geometry, so all accepted
points remain in canonical raster coordinates. Display opacity is NEVER used in
pixel analysis.

## Performance and scientific limits

The numerical fit can be unavailable (provider disabled, API changed, Octave
not installed). In that case only the fit reference is replaced with a local
straight guide reference. The image-based optimization remains active. When
crossings genuinely have no distinguishable pixel evidence, the algorithm
cannot resolve the intended branch reliably; users must add correction guides.

**Compatibility boundary:** The only direct numerical-provider dependency is
`_assistNumericFit` in `api/curve_digitizer_viewer_api_v1.tcl`. It calls the
PUBLIC operation `::GX::NumericAPIv1::interpolate` with `method=pchip` and
`extrapolation=error`. If that provider changes, update only this adapter,
its contract tests, and the explicit fallback. Do not call internal workers.

## 1.2.22 proposal correction interaction

**Add correction point** is a separate Curves-only mouse mode. Segment #
selects an unaccepted guide interval, and the next click adds a mandatory
operator guide even if hundreds of display pixels away from the proposed
path. The transient proposal is split and only the affected intervals are
recomputed. Other accepted intervals are never rewritten. A monotonic X/Y
configuration bounds the correction by the selected interval endpoints in
calibrated coordinates. The existing PCHIP numeric provider remains only an
optional advisory centerline; pixel path optimization is still local to the
plugin. No new private numerical API or native C/X11 dependency is introduced.

## Controlled accepted-point density

The viewer optionally applies a deterministic, non-parametric arclength
resampling step **after** the image-optimized trace has been reviewed. This is
implemented in `python/assisted_sampling.py`, without invoking a new curve
fitting operation. Given `M` guide intervals, the user-selected total `N`
requires `N >= M + 1`, and `N - 1` edges are distributed by the largest
remainder of each interval's arclength share. At least one edge per interval
is mandatory. Each guide endpoint is kept exactly once in the stitched
output, even when segments are accepted in a different order. `N = 0` retains
the native proposal sampling.

The **Resample accepted** action applies only to points generated by the live
proposal and tracked by exact point identifiers; it is never applied to other
manual or assisted work. A confirmation precedes replacement, and Undo restores
the previous scientific state. This operation neither reconstructs nor refits
the curve, and has no dependency on a private implementation of `NUMERIC_API_v1`.

## Far correction and interval selection

The correction tool must accept a new operator guide **without any proximity
limit to the automatically estimated raster path**. This is different from
Edit proposal, which still begins a drag by selecting a nearby visible point.
When an axis monotonicity policy is active, the new guide is assigned to the
unique guide interval containing its calibrated X/Y coordinate, even when
Segment # had a stale or unrelated value. Free-form curves use the selected
segment; invalid legacy values fall back to the nearest **guide chord**, not
the already-wrong proposed pixel trace. The segment selector is always bounded
to the current proposal's actual interval count, and grows when splitting.
Short two-vertex candidate spans can be divided by a far correction as well.
No proposal edit commits measured points until explicit Accept.

## Proposal guide topology under scientific ordering

When the user configures Monotonic in X/Y, or explicitly chooses Sort by X/Y,
the same scientific-coordinate ordering governs both the persistent curve
points and the temporary operator guides. A generated proposal vertex may be
selected in one segment but dragged across a guide boundary to a different
interval. Its **release coordinate** is authoritative when choosing the
destination segment. Inserting in the original segment would make the labels
G1..GN appear out of coordinate order, silently modifying the wrong path.

The correction step therefore resolves the unique destination interval from
the declared scientific X/Y calibration, recalculates its two subintervals,
renumbers guide labels by their actual list positions, and updates Segment #.
The proposal edit is rejected when the coordinate lies outside the guided
range or inside an accepted segment. Free-form insertion-order curves keep
the explicit originating interval and do not silently impose X sorting.

No Dataset points are committed by this operation; the old proposal is
recoverable through transient proposal Undo. The numerical interpolation API
boundary and the path-finding algorithm are unchanged.

## 1.2.25 — exact density per acceptance and Session safety

`python/gxtxt_curve_digitizer.py::_sample_assisted_segments` now accepts the
actual interval selection and uses arclength quotas only within those
intervals. For an explicit N, `Accept segment` contributes N new points to
the selected segment; the earlier algorithm erroneously allocated N across
all proposal segments, which could produce only 8 accepted points for N=100.
Previously accepted adjoining guide endpoints are excluded from the new count
and never duplicated; unchanged manual points remain authoritative.
`Resample accepted` recalculates N only over committed intervals from the live
proposal, not across unaccepted intervals. This is not a fitting change.

CORE Session identity is checked using the new read-only `SESSION_TOKEN` host
request with `::GX::interactiveDocumentSessionToken`, independently of the
Dataset catalog auto-update setting. On change, the adapter blocks editing,
requests `BOOTSTRAP`, discards transient proposals and pending callbacks,
then reconstructs the viewer from the newly authoritative Session. No direct
Session path or private state file is used. Retired image-processing worker
results retain their original result queue and cannot apply across Sessions.

## 2.0.5 user-directed shape prior and exclusion paths
The original image constrained unary objective combines local luminance/RGB/ridge and grid costs plus the quadratic reference-offset prior. With Smooth curve prior enabled, a second-order, banded dynamic program additionally minimizes λ*(offset_i - 2*offset_(i-1) + offset_(i-2))^2; λ is a documented ordinal preference (Gentle/Strong), not a physical uncertainty or fitted law. Guide endpoints are exactly fixed and the original first-order DP is used without change for Off.

User-defined exclusion paths are source raster (x,y) red X control nodes connected by chord-length monotone Hermite splines. A separate grayscale penalty raster is rendered from an adjustable-width spline tube and sampled along the same candidate points; the source Dataset pixels never change. Exclusions are soft image costs, so physical intersections remain possible. Both shape and exclusions are applied during initial Propose and all targeted recalculation operations (repair, insert/remove guide). Previously accepted scientific points are immutable until explicit edit/Undo.

The calibration context remains selected by the current active measurement. UI labels do not alter scientific calibration mapping. Validate on exact-referenced raster traces, including close neighboring curves, tight turns, grids, Pch=100W crossing, alternate source, Session reopen and zero-regression Off mode; do not treat local synthetic tests as host acceptance.
