# Official dev101 integration and evidence

GX-TXT 0.9.8.10-dev-101 derives only from the immutable deposited dev100
archive, SHA-256 `8c47d721ac1fe79d8289ddd6cf588c13581a8dfc96a0f9031d2e36f1778ca7c9`.
The mutable user installation is a delivery destination, never a development
baseline or release-equality gate. The final release specification binds the accepted receipt allowlist, complete
changed-file ledger and manifest. [Per-file source owners](DEV101_CHANGED_FILE_OWNERS.json)
identify WHAT/WHY/OWNER/EVIDENCE; generated package/registry/manifest hashes are
recorded separately in the frozen-release receipts.

## Scientific execution, I/O and namespaces

`core/tcl/scientific_execution_api_v1.tcl` owns typed trusted-provider discovery,
preparation, submission and original-Session access. It delegates process and
resource ownership to the existing Script Job supervisor/guardian. The Python
adapter supplies fixed-argv tool execution and opaque output projection, not a
second scheduler. `scientific_io_api_v1.tcl` and its private local adapter own
authorized metadata browsing, copy/reference import and CREATE-only export.
Shared namespace grants persist in the existing Session Manifest. The ordinary
File Publication transaction remains the only canonical file commit authority.

Actual ngspice produced 528 waveform rows for the managed 1 kΩ/1 µF circuit.
Independent τ = 1 ms comparison found maximum voltage error
`2.718717693195316e-6 V`; the explicit test tolerance and full result are retained
in `execution-02/result.tcldict`. Actual native plot interaction, returning from
partial zoom/pan to full fit, resize and Graph/Session reopen passed in
`execution-gui-02/result.tcldict`. Original netlist and canonical waveform SHA
were preserved. No repeat solver run was needed for that GUI continuation.

The independent public Python client exercised actual 1/2/4-process concurrency,
queueing, cancellation isolation, failure, live complete-record reads and exact
private-supervisor restart/reconciliation. `execution-processes-04/result.json`
explicitly references retained successful earlier batches; earlier failures are
preserved. `execution-process-integrity-01/result.tcldict` independently checked
91 kernel PID/start identities absent and 23 managed scratch allocations removed.
There is no fixed speedup claim.

Retention, original-Session ownership, immutable freeze/publication and explicit
expiry passed in `execution-retention-02`. Source/revision/command boundaries
passed in `execution-boundaries-01`. UTF-8 log append/truncate/rewrite/rotation
passed in `execution-log-generations-02`. Metadata-only output schema/unit
changes now advance generation; stale reads, exact int64, incomplete records,
append/truncate/rotation and stable logical identity passed 11 checks in
`execution-output-schema-01/result.json`. Python and Octave actually exercised
the public Bridge in `execution-bridge-03`, including provider-owned Numeric
manual discovery and rejection of private file-import grant fields.

Scientific I/O passed in `scientific-io-01`; the affected immutable-copy and
portable external-reference boundary passed in `scientific-io-snapshot-02`.
Offline/changed source and symlink refusal preserve logical identity. Portable
snapshot export verifies original bytes and strips private physical locators.
The shared namespace test verifies CREATE-only authorization and Manifest reload.
These are local cooperating-plugin boundaries, not an OS sandbox or a remote
transport implementation.

## Domain and native integration

The electromagnetic owner ledger records original→revised provenance and each
C++/Tcl/Python responsibility. Actual Gmsh/GetDP performed three refinements for
each of electrostatics and magnetostatics (Gmsh 4.13.1, GetDP 3.5.0). Independent electrical field errors
are approximately `4.55e-15`, `7.29e-15`, `1.48e-14`; weak residual checks are
`8.06e-16..1.39e-15` for electrostatics and `1.12e-14..4.20e-14` for
magnetostatics. Area-weighted magnetic reference errors in annulus `1.3a..2a`
decrease `6.647 → 4.796 → 2.758%` against the infinite-wire reference, whose
interpretation is limited by the finite outer boundary. The single-loop Ampère error is nonmonotonic and is
retained honestly; no physical uncertainty is inferred from solver residuals.
Exact canonical nodes/connectivity/cell scalars, true nodal potential, native
cell hit identity and complete source bounds remain distinct. Portable Graph
capture contains complete node/cell sources and managed raw resources.

Fitter retains its numerical engine, eight existing logical panels and User/
Session configuration authority. Actual headings, conditional controls, resize,
settings persistence, independent Help/F1 and rendered Statistical/Numeric links
were exercised. Shared Documentation Browser resolution now recognizes safe
provider-declared public API manuals without activating scientific modules.

Mathematics uses existing Numeric expression grammar, Unit Registry, root and
optimization operations and actual Python/Octave Bridge. The independently
supplied Explorer is preserved as an original ZIP and adapted separately as
opt-in version 0.1.1. The owner acceptance records two 13-check headless/public groups and
20 real GUI checks, finite-search limitations and every retained failed attempt.
No arbitrary expression execution, implicit scientific alignment or uncertainty
estimate is introduced.

Editable Native3D embedding and Native2D Curve Source reuse the existing native
worker, ViewportHost and canonical row mapping. Actual suspend/resume, physical
heterogeneous axes, exact point hits, bounded 20K display and lifetime guards
were checked. Planar return commits through the actual original Workspace owner
with idempotent retry and independent destination History. It is not claimed to
be one atomic transaction across two different Documents.

Raster composition uses native image-local ROI/layer/attribute authority and
managed ImageMagick Jobs. Known blend/alpha references, mask inversion, feather,
ROI-limited effects, stale/foreign/cyclic/locked/missing resource guards and
Document/Session persistence have focused receipts. The real GUI exercises
source-pixel selection, transforms, layer visibility, existing History, responsive
preview and cancellation. Original Image Inspector and Digitalizer packages are
unchanged. The actual creative workflow retained source-pixel RGBA alpha `0/255`
and 6062 matching gray source pixels after appearance assignment and Session
reopening, versus zero before assignment. The real rectangle-minus-hole shallow
`0.2 mm` extrusion independently gives STL area `14.04000054 mm²` and volume
`1.176000279 mm³`, matching analytic `14.04 mm²` and `1.176 mm³`. Exact STEP
reimport preserves native topology, volume and area with explicit millimeter
units. Direct STL from BRep remains unsupported; the proof uses the existing
explicit complete mesh conversion. Final native ABI and GUI receipts are indexed
with the owner acceptances; no new geometry or texture engine is introduced.

## Honest limitations and unfinished input

- The requested independently developed Replicate scientific-service package is
  **PENDING USER SOURCE**. The available supplied 15.3 Analysis is preserved,
  default-off, selectable and CORE-protected; no unpublished newer package,
  replacement engine, Viewer→service science result or Digitalizer statistical
  interop is fabricated. This missing-input exception is expressly allowed by
  the dev101 task.
- Mathematical finite sampling does not prove completeness of all roots or
  extrema. The initial FEM service covers linear planar static 2D only. Finite
  outer boundaries and actual mesh convergence remain explicit.
- Source I/O scopes/preparation handles are host-lifetime authorizations; no
  future SSH/HPC/cloud adapter is implemented. Live coherent CSV reads do not
  imply arbitrary coherent multi-file CFD snapshots.
- CAM remains architecture/design only. Decorative texture does not imply
  relief geometry, scientific optical material properties or machine programs.
- Inherited dev098 Inspector modal-confirmation interaction and exact cited
  signed-source replay debts remain recorded. The positive located Digitalizer
  source and separately verified signed fixtures are not conflated.
- The dev099 Session-open scale design and dev100 dirty-tile-only grid painting
  remain deferred. Whole-viewport coalescing and its actual measurements are
  retained; no regional-paint or general memory-improvement claim is made.

## Release preservation and delivery

The final package records full source SHA manifest, WHAT/WHY/EVIDENCE coverage,
revised source-matched external packages, real receipt allowlist and native build/
promotion identities. Old Plot v1/v2/v3 API/binding/runtime, independent supplied
Digitalizer/Inspector/Signal Viewer and unrelated native artifacts are compared
with the immutable predecessor. Original user ZIPs and the historical master
task retain their exact SHA values.

The established release procedure creates the framework archive, exact expanded
copy and restore points, tests isolated install→dev100 rollback→dev101 restore,
deposits matching central section pairs, then saves tested files to
`/home/giu/script-ag/current/gxtxt` with a full rollback copy and preservation of
independent user files/scientific resources. The final consolidated handoff lists
all four releases, archive checksums, actual acceptance and unresolved work.
Execution stops after dev101; no dev102 work is started.
