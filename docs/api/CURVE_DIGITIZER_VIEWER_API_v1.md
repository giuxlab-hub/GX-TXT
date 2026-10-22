# CURVE_DIGITIZER_VIEWER_API_v1

Version 1, module `viewer.curve_digitizer` descriptor version 2.0.4 (loaded Tcl
adapter/internal publication version still 2.0.3), namespace
`::GX::CurveDigitizer`, entrypoint `api/curve_digitizer_viewer_api_v1.tcl`.
The actual public Viewer activation call is:

```tcl
::GX::CurveDigitizer::viewerDispatch action scene
```

action is exactly open or rerender; scene is accepted by the standard Viewer
backend signature but this dispatcher does not select a Dataset/Document from
its fields. It starts/focuses the installed Python desktop adapter, requiring
a current Session on a new launch. Unsupported actions raise an error.
The backend registration is curve_digitizer_tk. No direct Script binding or
typed C++ SDK call to this activation family is declared.

## Return and actual readiness

New process creation returns `{status opened pid PID_LIST}`. A live channel that
accepts CONTROL FOCUS returns `{status focused pid PID_LIST}`. Neither return is
a mapped-window or scientific-success receipt. Python later emits READY only
after widgets map; lifecycle events STARTING/READY/FOCUSED/FAILED/CLOSED are
handled by the owner. A 60-second startup timer reports missing READY. Pipe EOF
before readiness and uncaught transport errors are retained/reported. This
distinction matters when a launcher succeeds but a GUI fails during startup.

The launcher honors CORE's configured Python runtime when available, falling
back to python3/python. It probes Python >=3.10 with tkinter, NumPy and Pillow,
then starts installed python/gxtxt_curve_digitizer.py with unbuffered output.
Bidirectional UTF-8 line protocol is nonblocking, with at most 16 records drained
per event, a 100ms polling fallback and separate Python stderr. Logs are appended
under the current Session's logs/curve_digitizer_host.log and
curve_digitizer_python.log. Process/channel/timer state belongs to this adapter;
internal RPC records and underscore helpers are not generic public operations.

The app uses public CORE Dataset/Schema/Metadata/Notes/Namespace/Catalog, Unit/
Semantic Registry, Configuration, Interactive Document/resource, Numeric,
Statistical Semantics and Publication services. Canonical Dataset lookup and
configuration persist through those owners; no automatic source is selected by
the public dispatcher. Specific data-facing operations are separately documented:
[Companion](CURVE_DIGITIZER_COMPANION_API_v1.md),
[Calibration](CURVE_DIGITIZER_CALIBRATION_API_v1.md),
[Published semantic schema](CURVE_DIGITIZER_DATASET_SCHEMA_API_v1.md),
and the installed image/quality/uncertainty public references. Activating this
Viewer does not admit those services as arbitrary C++/Script calls.

## Loaded public uncertainty integration helper

The entrypoint loads curve_digitizer_numeric_core.tcl and its existing factor
guard. Their shared namespace `::GX::CurveDigitizerNumericCore` has these actual
non-underscore host helpers; they are not Viewer dispatch actions or independently
registered Script/C++ operations:

| Exact signature | Context / result |
|---|---|
| `covarianceUnit xUnit yUnit` | Bounded explicit unit-string product as described in Companion; no local unit registry |
| `propagate documentId rowsText measurementId rows sourceDataset sourceSha inline ?preflightFactors={}?` | Public Numeric propagation plus retained identity/resources; returns columns/resources/meaning, document_sha256, point_count, source_dataset_id/SHA |

propagate requires a digitizer-owned current Document, live Session, exact source
raster identity, producer rows and the current producer's bounded linearization
packet. rowsText is a retained formal but not independently read by this helper.
rows supplies count, x/y, curve_id/label, point_id/index and family_value lists
in original publication order. The Numeric result must reproduce x/y at each
row within 1e−10 + 1e−10*abs(expected). It requires N coordinate pairs, N standard-
uncertainty pairs and N three-component covariance blocks. The retained sigma_x,
sigma_y and covariance_xy values are explicitly checked finite; this adapter does
not independently finite-check the other two covariance-block components.
No consumer-side numerical solver executes here.

inline is exactly 17 tab-separated fields: CORE_LINEARIZATION_V1 tag,
measurementId, mode, base64 rationale, base64 distribution, comma pixel scales,
comma calibration sigmas, comma override sigmas, encoded coordinates,
point Jacobian, calibration Jacobian, base64 coordinate units, calibration IDs,
calibration units, mapping, Jacobian method, and condition number. Count is
1–4096. Matrix wire is rows:columns:base64(zlib(binary64 little-endian column-
major)), with exact N×2, 2N×2 and 2N×12 shapes, finite values and payload text
at most 1,600,000 characters. Unit/ID lists use base64 semicolon-separated
nonempty strings with counts 2/12/12. Rationale is required and at most 2048
characters. CORE Scientific Transport owns the typed operand schema.

Mode pixel_calibration permits only declared rectangular_full_width or
normal_standard_uncertainty distribution, two finite nonnegative pixel scales
and 12 calibration sigmas; zero is preserved exactly. physical_override excludes
pixel/calibration fields and requires two strictly positive physical sigmas.
Mixed/inactive/unknown models reject. Public Numeric digitization_uncertainty
owns scientific execution/state; result schema must be
gxtxt.digitization_uncertainty.v1. Optional preflightFactors is the producer's
bounded canonical full-factor record; the existing guard checks shape, raw SHA,
and every independent/shared factor, not just marginal sigma.

Before/after resource capture, the adapter checks Session token, Document SHA,
and source raster SHA. It retains the actual configuration, original point
identity bytes, Numeric state, five-column physical values and Statistical
Semantics interpretation using public managed-resource writers. The result
columns are x,y,sigma_x,sigma_y,covariance_xy. These are declared propagated
uncertainties, not independent accuracy/coverage validation. Resources remain
CORE-owned retained values; this helper does not itself publish the canonical
Dataset or checkpoint the Document. Do not invent whole-call rollback of every
already finalized resource when a later check fails.

## Source-backed activation example and limits

```tcl
# Normal host Viewer infrastructure supplies action/scene and owns Session/Tk.
set launch [::GX::CurveDigitizer::viewerDispatch open {}]
```

This illustrates the signature only and was not executed during manual authoring.
Missing Session/runtime/dependency/script, child startup failure, broken pipe or
owner/source change must remain errors/diagnostics. A launch/focus return alone
does not demonstrate actual native controls, calibration correctness, complete
CORE data-flow consistency, installed scientific validation or final acceptance.
Use the authentic Viewer manual for workflow controls and independent native
acceptance evidence for those gates; no implementation is changed by this reference.
