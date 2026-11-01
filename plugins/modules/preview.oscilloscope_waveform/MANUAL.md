# Oscilloscope waveform Preview

Enable **Oscilloscope waveform** in normal Module/Plugin Manager. Activate a
canonical channel in the Dataset Browser and open **Dataset → Preview**. The
stock Plot/Table remain available. This independent Builder-authored Preview
adds **Oscilloscope waveform** controls and a small Fit/Zoom toolbar over that
same native Plot. It does not create a Viewer window or scientific Dataset.

The component currently matches `timeseries.table`, enabled time/signal roles
and registered source module `acq.rigol_csv`. It accepts every compatible importer
version; it has no generator, private importer API or physical storage dependency.
Its source-control API is generic and supports CSV/HDF5 through canonical Dataset
and Curve Source ownership. Other acquisition producers can use the same declared
scientific variables, metadata and public component contract in future compatible
provider declarations. No exact importer version is a scientific contract.

The initial pane reads registered metadata and actual Dataset Group membership;
it performs no numerical sample scan. It shows canonical time/signal Variable IDs
and units, actual channel/sample count and available source start/interval/rate/
duration/sequence diagnostics. Manufacturer/model are shown only when recorded.
Metadata rows state their actual contributor qualification. No absent instrument
setting is inferred. **Recording details / channels** refreshes those facts.

Choose one Group channel to activate its own independent canonical Dataset in the
normal browser. Group revision changes require an explicit details refresh.
Missing/degraded members are not silently reconstructed or substituted.

**Full recording** prepares all original source samples through CORE's bounded
individual Curve Source. The screen envelope retains first/last and ordered
extrema with exact original source-row identities; it preserves narrow spikes and
nonfinite gaps. Display points are a disposable presentation, never analysis data.
Raw/canonical full-resolution values and SHA remain unchanged. This also works
above the old grouped two-million-row limit; the guarded grouped collector is
not used for a single explicit waveform request. The stock Preview routing fix
is independent of this module.

**Show row window** uses zero-based original canonical source rows and a positive
exact Count. Invalid/noninteger/out-of-range drafts are refused before preparing.
**Show time interval** uses From/To in the canonical time Variable's units, before
optional display calibration/magnification. Both endpoints are included. It
selects actual source observations through the existing Transform/Curve Source
owner; it does not interpolate or replace samples. A window without observations
reports the real preparation error and retains the previous successful frame.
Returning to Full recording explicitly clears the window. Range requests are
read-only viewing state and use normal Preview cache/invalidation.

Fit/Zoom, wheel zoom, pan and point/source-row hit mapping stay with the existing
native Plot v4 controller. Fit covers the current prepared source/window bounds.
Zooming an envelope changes the view; choose a row/time window to prepare finer
source detail. Exact numerical inspection remains available in the standard Table
and canonical Dataset APIs. No mean/statistics are estimated from reduced points.

Use normal **Cancel preparation** during a pending request. The prior successful
frame stays qualified until a new source-bound result is admitted. Source/Session
changes, module disable/update and pane closure retire old controls and callbacks.
Re-enable or restart and open the canonical channel again to mount a fresh pane.
Small windows and large fonts use the shared native control scrolling and Tab
focus. The source remains available when the component is disabled or unavailable.

Requires P028 `PREVIEW_COMPONENT_GUI_API_v1` source-request/selection operations
and presentation-only Builder initial-action support. The declared framework base
version does not distinguish incremental patches; final operator preflight must
check these actual public capabilities. No runtime compiler or private renderer,
stream reader, numerical reducer, Dataset registry or persistent selection is
included. All product science and rendering remain with existing CORE owners.
