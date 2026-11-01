# Dataset write providers in GX-TXT 0.9.7.24

Dataset Publication API v2 owns write planning, logical schema, transactions,
integrity, placement, and registry commit. Provider adapters own only storage
operations. This is the write-side counterpart to Canonical Dataset API v2.

## CSV provider

The CORE Tcl provider accepts typed logical declarations and writes a UTF-8,
comma-delimited table sequentially. It supports selected declared columns,
complete output for a single-variable dataset, row-chunk append, explicit
coordinates, materialized uniform coordinates, flush, finalize, and abort.
Quoting is provider-owned. Consumers still receive typed values through
Canonical Dataset API v2.

CSV rejects groups, rank greater than one, random range replacement, and
hyperslabs. It does not flatten arrays or claim bounded late random access.

## HDF5 provider

`core/python/gxtxt_hdf5_writer.py` is a private CORE adapter. One Python/h5py
worker remains alive from writer open through finalize or abort. No process is
started per chunk. It supports numeric and string dtype declarations, fixed or
extendible shapes, chunks, arbitrary append axis, complete/range writes,
n-dimensional hyperslabs, logical groups, component metadata, and explicit or
implicit coordinates.

The provider maps stable variable IDs to private HDF5 object locators. The
mapping is stored only in registry provider state and never appears in public
Schema v3 results or plugin runtime configuration. Plugins must not import
h5py or inspect the private layout.

The worker converts only the current write request. Diagnostics report total
elements, maximum request elements, append calls, hyperslab elements, and the
single worker process ID. The 0.9.7.24 fixture writes 131,072 signal samples in
eight 16,384-sample calls; its largest request is the paired 32,768-element
vector chunk. The hyperslab operation receives only its four-element region.
No intermediate CSV is created.

## Transaction boundary

Both providers write a `.partial` sibling of the destination. Provider
validation and close precede SHA-256. SHA time is measured separately. CORE
then renames the object within the destination directory and persists the
registry. A failed registry persistence restores the prior registry and
deletes the renamed object.

Session-relative paths are authoritative. Reopening a copied session resolves
the provider from registry metadata and uses the copied storage object.

## Scope

This release does not add Table Stream v3, final Storage Auto heuristics,
CSV-to-HDF5 caching, compatibility materialization, plot LOD, indexed CSV,
mmap, NetCDF, or Zarr. Existing scientific modules and their storage behavior
are unchanged.
