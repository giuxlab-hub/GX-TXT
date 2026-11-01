# Prepared numeric Acquisition publication v1

P033 generic `spectrum.scientific` prepared outputs additionally declare their
six scientific fields and exact X/Y Variable IDs. CORE validates the actual
sealed samples through the existing Scientific Spectrum value owner before
publication. See [paged qualification](SCIENTIFIC_SPECTRUM_PAGED_VALIDATION_v1.md)
for required coordinate/unit identity, bounded reads, numerical versus payload
hashes and rollback. Other prepared contracts retain their existing checks.

This is a narrow additive handoff under the existing Acquisition Handler owner.
`::GX::acquisitionHandlerDispatchApiInfo` advertises `prepared_publication_api=1`,
`dataset_group_api=1` and supported source-dispatch options. It is a host
capability query, unaffected by the existing variadic transaction wrappers.

A handler may return `datasets {}` and `prepared_publications`, a bounded list
of 1–64 declarations. Each contains exactly `definition`, `row_count` and
`variables`. `definition` uses existing Publication v2 dataset_id/contract/storage/
metadata/provenance fields. Each of 1–128 variables contains `variable_id`,
`schema` and a normalized relative `path` beneath the handler's private output
directory. Its actual file contains the existing little-endian numeric array
transport with exactly row_count × dtype-width bytes; this is not a canonical
Dataset format. Each variable has one rank-one `row` dimension, supported numeric
dtype and a maximum 512 MiB, matching the existing managed binary resource lane.

P033 adds an optional `dimensions` map `{stable_dimension_id: positive-size}`
to prepared declarations. Each Variable then declares its own ordered unique
`dimension_ids`; rank/shape, if supplied, must agree with those dimensions.
There are at most16 dimensions/rank and every dimension belongs to a real
Variable. Coordinate Variables may have independent lengths. The exact file
length is `product(shape) * dtype-width`, with the same512MiB per-Variable bound.
Bytes are little-endian, column-major (`F`) as in Scientific Binary Transport v2;
no flattening, transposition or dtype conversion is implicit. The legacy form
without `dimensions` retains its original one-row-dimension behavior.

The native SDK adds an overload
`prepare_output(definition, dimensions, variables)`; the existing
`prepare_output(definition, row_count, variables)` remains unchanged. CORE
derives a compatibility `row_count` summary as the maximum first shape extent,
matching Publication v2 Registry summaries; this scalar is not an nD shape.
The sealed declaration includes exact dimensions/Variable schemas. Shared
Publication v2 declares these dimensions and transfers each actual shaped array
through the existing managed-binary lane. Storage selection requests
`multidimensional` where needed, with no fallback to an incompatible CSV writer.
The Dataset contract must actually describe the scientific content; transport
rank support never licenses calling arbitrary images or stacks a 1D spectrum.

CORE preflights all IDs/contracts/schema/paths/lengths before authoritative
placement, then admits scoped resources and calls the existing Publication v2
managed numeric writer. Only that owner selects actual HDF5 storage, declares
typed variables, validates/flushes/closes and computes canonical SHA. No second
writer, private Registry mutation or relabelled CSV is involved. Existing byte-
preserved file-shaped Acquisition output remains unchanged.

The already-held outer Acquisition/Dataset authority transaction encloses every
publication, RAW placement, metadata, optional declarative Dataset Group and
reviewed destination Namespace. A late failure rolls back all enlisted resources;
no nested finalization can leave a successful partial Group. Temporary array
resources and any failed writer are released through existing Resource Management.
Library provenance options are merged before writer admission, not appended by a
Viewer after import. Producers cannot change their own module identity.

The original source SHA is captured before inspection and matched to the actual
RAW snapshot, preventing changed headers/units between inspection and parsing.
Reference-mode source SHA is additionally rechecked after the handler completes.
No source file is modified, and unknown/malformed outputs refuse normally.
