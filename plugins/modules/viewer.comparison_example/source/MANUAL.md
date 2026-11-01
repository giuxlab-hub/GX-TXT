# Non-IR Comparison Example

Compare compatible one-dimensional scientific curves without changing their
canonical samples. This Viewer uses the shared Comparison Plot profile. Sources
remain pinned to their actual Dataset or read-only managed Library identities.

## Reproduce a small synthetic electrical example

The following numbers are **SYNTHETIC teaching data**, not instrument measurements.
Save the two complete files as UTF-8 comma-separated text:

`synthetic_voltage_a.csv`

```csv
time_s,voltage_v
0,1
1,2
2,4
3,3
4,5
```

`synthetic_voltage_b.csv`

```csv
time_s,voltage_v
0,2
1,4
2,8
3,6
4,10
```

1. In the ordinary Acquisition workspace select **Generic CSV dataset import**
   (`acq.generic_csv`). Add both files as enabled batch rows, one header row and
   comma delimiter. Assign distinct Dataset IDs `synthetic_voltage_a` and
   `synthetic_voltage_b`, with contract `table.generic`.
2. Use each row's **Preview** and **Variables** review. Keep canonical names
   `time_s` and `voltage_v`. Declare `time_s` in seconds (`s`), semantic role
   `independent`; declare `voltage_v` in volts (`V`), semantic role `measured`.
   Review any coordinate/time declarations explicitly. Names and unit labels do
   not imply a numerical conversion, time origin or instrument provenance.
3. Import into your own Session and verify its canonical Variables and RAW/source
   provenance. These two files remain synthetic even when their import succeeds.
4. Open **Non-IR Comparison Example**. In **Sources**, choose the first Dataset,
   then **Compare → Discover sources** to populate its actual Variable choices.
   Select `time_s` as X and `voltage_v` as Y, then **Compare → Add Dataset source**.
5. Repeat for the second Dataset. The Sources table shows explicit order, source
   kind, identity, units and current/stale state. Use the selected-source index
   and **Move source up/down** to change order deliberately. **Inspect selected
   source** writes its identity/provenance pin to **Source and result**.
6. Choose settings in **Method**, then **Compare → Prepare comparison**. The
   **Plot** tab presents the accepted frame; **Source and result** explains its
   method and invalid/gap count. Changing controls stages the next preparation.

For these exact sources and order A then B, raw Difference is
`{-1,-2,-4,-3,-5}` and raw Ratio is `{0.5,0.5,0.5,0.5,0.5}`. This is an arithmetic
check of synthetic data, not scientific identification.

## Five explicit comparison modes

| Method value | Meaning |
| --- | --- |
| `overlay` | All selected curves in one panel, retaining each complete source grid. |
| `top_bottom` | Separate ordinate panels with linked horizontal navigation and independent Y navigation/scales. |
| `stacked` | Ordered display curves; source index 0 has no offset, index 1 adds one offset step, and so on. |
| `difference` | Exactly two ordered sources: first minus second, using raw physical values. |
| `ratio` | Exactly two ordered sources: first divided by second, using raw physical values. |

Difference and Ratio use linear interpolation only on the intersection of the
source domains, at the first source's retained X coordinates. There is no
extrapolation. Reversing source order changes the operation and its evaluation
grid. Other modes preserve independent complete source grids rather than
silently interpolating or clipping them to a shared grid.

**Normalization** defaults to `none`. Explicit `minmax` is a display-only shape
normalization for Overlay or Stacked: finite values map to `[0,1]`; a constant
finite curve maps to zero. It neither rewrites samples nor establishes physical
equivalence. Top/Bottom, Difference and Ratio require `none`.

**Offset** is a finite display step used only by Stacked. For the example,
offset `10` displays B as `{12,14,18,16,20}` while A and both canonical datasets
remain unchanged. Other modes use zero display offset.

**Denominator floor** is nonnegative and applies to Ratio after the declared unit
conversion. If the denominator magnitude is at or below the floor, that result
is a gap. With floor zero, exact zero denominators are gaps rather than infinities.
Nonfinite Y values remain explicit gaps; interpolation does not bridge a missing
bracket. A valid exact source knot remains available even if its neighbor is
missing. Invalid-result counts are reported in Source and result.

X must be finite and strictly ascending or descending, with no duplicates.
Each source must have 2–65536 real rank-one numeric samples. Preparation refuses
unsupported sizes, unavailable/stale sources, incompatible coordinate meaning,
units or time declarations. It does not silently truncate sources or infer an
alignment. Unit conversions use declared units and the shared coordinate owner;
canonical values and identities remain intact.

Comparison arithmetic uses the existing Numeric binary64 floating-point semantics.
Int64/UInt64 Dataset samples outside the safe exact-integer range
`[-9007199254740991, 9007199254740991]` refuse before conversion rather than being
silently rounded. A float64 source retains its declared floating-point semantics;
this display is not an arbitrary-width integer arithmetic service.

## Plot navigation and source review

- Wheel over a Plot panel to zoom; drag with the middle mouse button to pan.
  In Top/Bottom the X interval follows across panels, while Y changes only in
  the panel under the pointer. Double-click the Plot to Fit.
- Use **Sources** to review/remove/reorder pending selections. **Clear comparison**
  clears that selection, not the datasets. A failed Prepare retains the last
  accepted Plot, so check Source and result before interpreting a staged change.
- Managed Library consultation requires its installed, enabled read-only provider
  and an admitted bounded scientific curve representation. Discover lists at most
  200 entries per current selection; it does not publish a Dataset or modify a
  Library. Absent providers or incompatible entries refuse explicitly.

## Workspace, History and reopening

**Workspace → Save** stores the source pins, settings and prepared Plot state in
the existing Session Workspace. Use **Save As…** for a separate Workspace copy.
Close normally after saving. In a later process, open the same Session and open
that entry from **Session Workspaces**; its registered Viewer and current source
identities are validated again. A changed or missing source is not silently
retargeted. Keep the actual source datasets/providers with the Session.

The ordinary **History → Undo/Redo** restores comparison selections, settings and
prepared states. Older History is read-only; return to the latest state before
making changes. Plot pan/zoom is presentation state, not a canonical-data edit.

This Viewer is a consultation client. It does not fit a model, identify a sample,
claim spectral authenticity, publish derived datasets, or write canonical samples.
A Difference or Ratio is a transient raw-derived display. Any alignment or
scientific transformation requiring new canonical results must use its explicit
normal scientific owner and publication workflow.


## Plot presentation menu (1.0.2)

After Compare → Prepare, use the primary Plot menu. Fit and Zoom in/out operate
on the current native Plot. Wheel zoom, middle-button pan and double-click Fit
remain native controls. Top/Bottom retains synchronized X and independent Y.

Pick display value arms a pointer inspection of an actual displayed/computed
point. It does not identify a canonical source row or publish a measurement.
Clear cursor removes that display selection. Reverse X changes display direction,
preserving source order and scientific samples. Properties edits the bound axes
and labels; Legend controls existing native presentation; Series style edits the
actual display traces. These controls do not open the canonical Dataset-series
editor or change the comparison method/source identities.

Copy plot copies the displayed image as PNG through the X11 image clipboard;
it does not copy scientific samples. Export PNG… uses the normal Save dialog
and File Publication owner. Cancel leaves the current Plot and sources intact.
Save Plot Variant… / Load Plot Variant… use the existing Graph/Plot variants,
with current source/lifetime checks, rather than an extra comparison store.

Normal Workspace Save, History Undo/Redo and cold reopening retain their existing
owners. Missing or stale source/provider/backend and unavailable presentation
operations must refuse explicitly; the previous valid frame remains inspectable.
Independent acceptance of these newly declared controls is separate from the
earlier five-mode numerical and source-integrity evidence.
