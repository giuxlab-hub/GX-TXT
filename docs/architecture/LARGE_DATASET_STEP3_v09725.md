# Large Dataset Step 3: Table Stream API v3

GX-TXT 0.9.7.25 adds only the table-shaped streaming facade above the
0.9.7.23 Canonical Dataset read layer and 0.9.7.24 publication layer.

Canonical Dataset API v2 owns Dataset IDs, provider dispatch, backend
detection, CSV parsing, HDF5 workers, range reads, implicit-axis synthesis, and
provider diagnostics. Table Stream validates a lossless table view, advances a
row cursor, bounds requests, and presents ordered chunks. Rank-2 or higher
variables remain direct Canonical Dataset API v2 use cases.

Native CORE streams own one Canonical handle. A modern Octave stream owns one
persistent Tcl bridge, which owns the Table Stream and Canonical handle. HDF5
adds one persistent provider worker. No layer starts a process per chunk, and
no cursor is shared accidentally between streams.

HDF5 reports `range_mode=direct`; CSV reports
`range_mode=sequential_fallback` and its prefix scan. `require_direct=1`
rejects a sequential provider.

The deterministic late-range fixture starts at row 8,000,000 and reads 65,536
rows in 4,096-row chunks. It reports zero prefix elements, a maximum stream
chunk of 8,192 values for two selected variables, 65,536 physical payload
elements for the selected signal, and 65,536 chunk-local implicit coordinate
values. Unselected HDF5 variables are not read. These are bounded-request
proofs, not general speedup claims.

Legacy three-argument Octave calls continue on their original CSV path.
Whole-table helpers remain. No scientific module was migrated. Final Storage
Auto policy, materialization/cache, plot LOD, indexed CSV, mmap, NetCDF, and
Zarr are outside this step.
