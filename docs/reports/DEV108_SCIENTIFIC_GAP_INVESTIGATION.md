# GAP-SPICE-005 scientific provider investigation — in progress

The separate author tried scientific submission and inspected the actual API
catalog, finding no admitted runtime operation. Its follow-up proposal retains
existing UI Field forms, Script Job identities, Scientific Execution preparation,
registered destinations, Parallel Execution admission, canonical Dataset
publication and Plot v4. No arbitrary scripts, process commands or library imports
are requested or granted. GAP004 separately covers public Numeric vectors and
analytical comparisons; scalar C++ arithmetic is not a waveform oracle.

Existing owners inspected at sealed dev107 / candidate dev108: Scientific
Execution API v1 and its remote dispatcher, durable Script Job API v1, Parallel
Execution API v1, Interactive Document v1, Dataset Publication v2, Plot Dataset v4,
and math.numeric's public operation catalogs. The existing registered
core.ngspice.rc_transient 1.0.0 requires an exact five-line fixed R1000/C1u
netlist. Its integration-step campaign cannot represent an edited circuit or
physical-parameter sweep. This limitation was reproduced by the real local and
authenticated loopback protocol tests; their results do not cover the Viewer.

Preferred compatible addition: another typed provider under Scientific Execution
v1 for bounded electrical.basic canonical diagram snapshots and op/tran/ac/dc.
The provider translates explicit port/wire/junction/label topology into a
reviewable deterministic deck; it never accepts authored .control, .include,
filesystem paths or raw solver commands. A public circuit prepare/inspect facade
uses the same canonical Document/resource owner and unchanged existing Job,
remote transport and output protocols. The fixed RC provider remains unchanged.
External ngspice performs the SPICE solve. All analytical comparisons and derived
vector arithmetic must use public Numeric/Mathematical/Statistical operations;
the new provider only validates/translates and publishes raw solver observations.

No new API family, queue, scheduler, persistence registry, remote transport,
renderer or numerical library is justified. Restricted SDK admission follows
verified owner contracts, with exact declared component indices and explicit
capabilities. Preparation tokens and Job references belong to the trusted host,
never to double-valued native State slots. Stale snapshots, cancelled/failed Jobs,
offline destinations and unsupported provider options must fail explicitly.

This decision authorizes development, not a scientific acceptance PASS. Required
follow-up includes actual solvers and units for all analyses, rejection of unsafe
or floating circuits, local/remote parity, genuine physical sweeps/concurrency,
canonical Dataset/Plot and independent installed authored GUI cycles.

## GAP004 unit compatibility found during installed scientific review

The actual authored1.2.0 local/remote op/tran/ac/dc GUI produced canonical
Datasets, but `authored_numeric_gui.tcl` failed in public Numeric
`expressionDataset`: `Unsupported nonlinear, semantic, opaque or invalid unit:
ohm`. The authoritative spelling is already `Ohm`; the primary fixture and
new shared catalog label are corrected, without accepting arbitrary aliases.
Inspection of both existing unit parsers also proved `F` and `H` absent, although
new electrical.basic attributes expose those actual physical units.

An existing alternative is `A*s/V` and `V*s/A`. It is dimensionally valid, but
leaves the public circuit controls' standard SI labels opaque to their own unit
selectors/expressions. The compatible addition recognizes F/H and their existing
SI prefixes in the same Tcl and Octave unit owners, and offers bounded standard
selector choices. It does not change existing symbol meanings, serialized values
or API versions and creates no new numerical service. Reusable consumers include
impedance instruments, sensor models and generic Dataset unit conversion.
Expected tests: actual canonical waveform expression residuals, prefix/composite
compatibility, rejected incompatible dimensions, and existing semantic-unit
behavior. Earlier failed receipts are retained; release acceptance remains open.

## GAP005 physical sweep/matrix preparation decision

The author inspected the public circuit provider and proved only the optional
single override_component/override_value pair exists. It can sweep one value
but cannot represent a real R-by-C matrix without mutating the canonical source.
The existing Scientific Execution typed schema supports bounded inert string
parameters, managed snapshots, provider normalization and durable child Jobs.
The existing Parallel Execution callback coordinator intentionally runs callbacks
in process; its worker_count1 must remain explicit. The Job Supervisor already
provides actual admitted process concurrency and durable progress/cancellation.

Compatible additions under these same owners: optional component_values inert
map of at most8 stable component IDs to finite base-SI scalar values (R/C/L/V/I
only), rejecting absent/duplicate/conflicting targets before prepare. An existing
single override remains accepted unchanged. Public circuit sweep preparation
validates every bounded explicit item before any admission, shares one original
Document-managed resource, and returns existing preparation handles plus exact
source/item/provider identities. Submission callbacks admit ordinary Script Jobs
and return immediately; the existing Supervisor alone schedules their processes.
Submission completion is not simulation completion. No duplicate campaign registry,
queue, process pool, private netlist or mutation of the authoritative circuit is
justified. Source/parameter digest, partial admission and cancellation/reconnect
receipts must be retained and actual overlapping Jobs proved independently.

Restricted Builder/SDK controls and genuine local/remote matrix/scientific GUI
acceptance remain pending; this decision does not claim those implemented.

## GAP004 bounded vector capture owner decision

Actual installed reference tests prove Numeric expressionDataset/interpolation/
array/reduction operations exist; the remaining gap is restricted typed access
and safe vector lifetime/publication, not missing mathematics. Inspected current
Numeric expressionDataset, callOperationCaptured, ScientificTransport withCapturedColumns,
Statistics numericModel/FieldMap/fromProviderColumns, and existing Managed Resource
write_numeric/read_numeric contracts. Statistical capture intentionally requires
registered descriptive/inferential meanings; a pure pointwise expression is not
a statistical estimate and must not be forced into a fabricated profile.

Preferred additive Numeric wrapper: expressionDatasetCaptured takes the same
canonical bindings/units/row bounds, captures only its actual values vector via
the existing Scientific Transport binary path, imports through existing
gxtxt.numeric_matrix_le_v1 Managed Resource, and returns an ordinary typed
managed_array plus exact expression/source/unit receipts. One column has identical
C/F byte order. A single-row result is its actual scalar, never a prototype standing
for an uncaptured vector. Source Dataset revision and owning Document generation/
revision/SHA are checked before and after. No new format, binary transport, vector
store, numerical service or Statistical profile is needed. Existing Statistics
captured calls remain responsible for valid reductions/comparison semantics.

Builder/restricted GUI form exposure must retain only resource/source identities
in existing canonical Document/Workspace state, never C++ double-array buffers or
another Dataset registry. Explicit publication uses the existing Dataset writer
and Plot source identities. All author unchanged-scenario/native GUI retests,
invalid units/rows/stale/cancel tests remain required; implementation is not PASS.
