# Scientific bulk transport (dev093)

SPDX-License-Identifier: GPL-3.0-or-later

This page records the dev093 implementation. For the current additive dtype
contract, see [CORE scientific binary descriptor v2](SCIENTIFIC_BINARY_TRANSPORT_v2.md).

The dev093 Script Bridge retains its public v1 calls and numeric float64 array contract.
Python float32 inputs still widen to float64; integer scalars retain their existing
exact scalar transport. Complex Signal values use the documented split real and
imaginary fields. No native complex ndarray contract is introduced.

Signal provider bindings and the seven Numeric array operations now use one local
Octave worker per Bridge/job. The worker calls the unchanged public
`gxtxt_signal_v1` and `gxtxt_numeric_v1` functions. It does not implement scientific
algorithms, share interpreter state across jobs, or create a worker pool. Other
Numeric operations and direct Tcl clients retain their existing routes.

Control requests remain small structured JSON. Arrays cross the bulk channel as
private binary resources with descriptor version 1, dtype, shape, element count,
little endian, column-major order, byte count and a CORE-generated resource ID.
Shapes are limited to sixteen dimensions and each buffer to 512 MiB. The reader
rejects mismatches, oversized counts, unsupported dtypes/order/endian, traversal,
symlinks and foreign ownership. The worker receives only its private workspace
and CORE-approved provider function identities. Existing v1 client binary files
remain accepted, with scope checks for current clients.

The resource manager owns each new Python client and scientific worker directory.
Octave client directories are observed and remain client-owned. Normal completion
releases owned allocations; cancellation and parent exit let the job/resource
authorities reconcile them. The worker exits if its parent disappears. It retains
the supervisor's process group and obeys OMP/BLAS/FFTW thread budgets. A dead
worker fails the call; an explicit job rerun creates a fresh context. Algorithm
errors return stable provider errors without substituting empty results.

Signal typed inputs add `kind=uniform, start, step, count`. It produces
`start + (0:count-1)*step`; the caller remains responsible for sample rate and
physical units. Explicit irregular arrays remain supported. Typed options may
include `result_fields` as a text node containing comma-separated result field
names (or a typed cell of text nodes). Only explicitly requested fields are
returned; the default remains the complete original response. These additions
also work through the existing Tcl ScientificTransport facade.

Dataset Publication retains its existing typed binary block and HDF5 writer.
Bridge ndarray writes/append now select that block, converting to C order where
required. Base64 remains on the existing HDF5 control channel; eliminating that
bounded encoding was deferred because removing float/list serialization already
addresses the measured bottleneck without a new HDF5 protocol.

Bridge context adds `output` and immutable job `inputs` (semantic alias, Dataset
ID, visible label and authoritative revision). Every API call validates submitted
input revisions through `datasetRevisionToken`; changed input fails explicitly.
Changing the current GUI namespace does not retarget a job. Publication bindings
record committed receipts in `published_datasets.json` under the run output
directory. Requested outputs are not success receipts.

An output-aware script uses `ctx["output"].get("dataset_id", original_default)`
and the explicitly supplied `replace_owned` policy in its normal Publication
definition. Arbitrary existing source is never rewritten at runtime. The private
tutorial copy under `validation/async_dev093_transport` demonstrates this adapter.

The future Windows port must replace local process/liveness details at the common
CORE backend boundary, using the same job/resource authority and Windows Job
Objects when appropriate. No remote execution, Windows service dependency or
Windows implementation is included here. The supervisor's required future tray
strategy is documented with the common Job API.

Validation scripts and their arguments/side effects are catalogued in
`validation/async_dev093_transport/CATALOG_ADDITIONS.txt`. Numerical tests compare
seeded noise exactly and compare signal values with an explicit tolerance: legacy
JSON coordinate decoding can differ by one ulp from exact binary coordinates,
which propagates through high-frequency phase. Scientific functions, frequencies,
amplitudes, sample rates and seeds remain unchanged.
