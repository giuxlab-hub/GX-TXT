# Library Entry Acquisition Dispatch API v1 (P028)

Host-only `::GX::LibraryEntryAcquisitionDispatchAPIv1` bridges explicit selected
persistent Library content to the existing Acquisition Handler API. It owns no
scientific parser, Dataset registry, RAW or publication engine.

- `apiInfo` describes version and operations.
- `compatibleHandlers contract mediaType ?recordType?` discovers enabled installed
  Acquisition descriptors by output contract compatibility, declared media and
  optional qualified `library_acquisition.record_types`. It does not guess from
  filename extensions. Missing handlers remain unavailable.
- `inspectSelection selection` requires reference and resource_index. The latter
  is -1 for a structured record or an actual local resource index. It allocates a
  bounded-lifetime Resource Management directory, validates the pinned immutable
  Entry/content/resource SHA, stages exact bytes and calls each compatible
  handler's public inspect operation. Staging is released in `finally`.
- `importSelected session selections ?destinationNamespace?` requires each
  selection to include reference, resource_index, handler_id, dataset_id and
  expected_sha256 from review. At most100 representations. It revalidates source
  identity and bytes, installed compatibility and target, then calls the existing
  `acquisitionHandlerImportSourceToSession` with additive seventh-argument options
  `{source_provenance {library.* ...} destination_namespace ...}`. CORE Acquisition
  admits provenance and Namespace within its normal transaction. A six-argument
  predecessor lacking that support is refused rather than silently losing origin.

The result is `gxtxt.library_acquisition_batch.v1` with per-selection status,
actual Dataset IDs, handler and source SHA, or an exact failure. Each entry uses
its existing atomic Acquisition transaction; arbitrary semantic neighbors are
not automatically made into a Dataset Group. A failed later independent
selection does not falsely roll back earlier completed selections.

Existing molecular/PDF/image handlers process their actual original sources.
New `acq.electronics_component` + `contract.electronics_component` and
`acq.scientific_publication` + `contract.scientific_publication` are ordinary
independent packages. A component/publication is one opaque typed JSON Dataset
with structured metadata and no fake numerical rows. A citation does not imply
full article text. Scalar attributes never automatically become Datasets.

Recognition and staged scientific context (P028 refinement): handler candidates
must declare actual Acquisition Format MIME or a qualified library_acquisition
record type in addition to compatible output contracts. inspectSelection exposes
only candidates whose actual existing inspection recognizes the staged bytes.
Broad legacy output contracts alone never certify unrelated source formats.
The existing binary image module now declares its already supported
PNG/JPEG/BMP/TIFF MIME formats; its parser/configuration remain unchanged.

A domain may declare bounded `acquisition_context_fields`. CORE stage then writes
a fixed data-only context containing those scientific fields, exact Entry pin
and resource SHA. The receipt includes context_path/context_sha256. Dispatch
checks the exact allocation path, context digest and original resource digest
before and after inspection and before import; malformed, mismatched or orphan
context fails. The context is data and confers no privilege from its filename.
The resulting library.context_sha256 travels through the same existing
Acquisition transaction as all other Library provenance.

`domain.scientific_spectra`, `library.scientific.spectra` and
`acq.scientific_spectrum` provide independently packaged real numeric CSV/JCAMP
admission and handoff through the existing CORE Scientific Spectrum Import API.
The domain's validator also invokes the existing Spectrum API for finite,
monotonic coordinates and scientific semantics. CSV source semantics are explicit
parser_options; JCAMP uses supported actual headers. Direct ordinary Acquisition
and selected Library import use the same adapter/parser, exact original RAW and
canonical Variable Schema. Source images, annotations and bibliography never
become fabricated numeric spectra.
