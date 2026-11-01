# Large Dataset Foundation, Phase 1

SPDX-License-Identifier: GPL-3.0-or-later

GX-TXT 0.9.7.23 implements the first foundation phase approved in
`GX-TXT_0.9.7.22_large-data_architecture_report.md`.

```text
logical Dataset ID + scientific contract + stable variable IDs
                         |
                 Canonical Dataset API v2
                         |
             CORE storage-provider dispatch
                   /                 \
       sequential CSV             direct HDF5
```

The implementation evolves the existing dataset architecture. It does not add
a Big Data API, HDF5 API, FFT storage API, CFD storage API, or plot-specific
loader API. Providers live below Canonical Dataset API v2 and report explicit
capabilities.

The CSV provider preserves current text behavior. It supports selected columns,
ranges and chunks but reports `random_access=0` because late ranges scan the
prefix.

The HDF5 provider is read-only in this phase. It supplies typed metadata,
selected rank-1 variables, direct ranges, chunks, n-D hyperslabs, logical
groups and multidimensional shape. Its persistent CORE worker prevents a new
Python process for each small chunk. Provider diagnostics used by release tests
count payload elements, prefix elements, metadata payload reads and maximum
request size without making timing claims.

Uniform coordinates are logical variables. CORE synthesizes only the requested
range from origin, step and count. Multidimensional values keep rank and shape;
the API rejects attempts to treat an n-D variable as a row range.

Phase 1 is read-side infrastructure. Dataset Publication v2, a generic writer,
Storage Auto policy, indexed CSV, plot.dataset migration, Graph Series loader
migration, FFT migration, audio migration, dataset.extract migration,
Spectrogram, Equation Engine, CFD, LOD, mmap/native, NetCDF and Zarr are left
for later work.
