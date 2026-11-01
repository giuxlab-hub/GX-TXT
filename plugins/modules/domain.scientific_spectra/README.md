# Scientific Numeric Spectrum Domain

Independent normal Plugin Install package. Actual source CSV/JCAMP bytes are retained; no numeric data is invented from annotations, pictures or external references. Uses existing CORE Scientific Spectrum Import/Spectrum APIs for parsing, finite/monotonic axis/units and sample admission; no duplicate scientific parser. A persistent Library entry is independent of Sessions. Only an explicit later selected import invokes the standard Acquisition transaction, retaining RAW/SHA/Variable Schema/Library provenance.

## 1.1.0 additive Library descriptions

The historical `scientific.spectra` Library Type remains the same immutable typed
record storage provider. It can contain these installed Domain-declared records:

| Record type | Meaning of the description |
|---|---|
| `scientific.spectrum` | The existing 1-D XY type: original numeric CSV/JCAMP, or an explicitly qualified 1-D description. |
| `scientific.scalar_measurement` | Rank-zero scientific scalar metadata. |
| `scientific.complex_spectrum` | Explicit observed component membership/order/representation; no invented magnitude, phase or conversion. |
| `scientific.multidimensional_spectrum` | Real multidimensional spectral shape/axes, including an explicitly declared NMR contract where applicable. |
| `scientific.spatial_measurement` | Spatial field/image/volume metadata; typed arrays and opaque original raster resources remain distinct. |
| `scientific.frame_sequence` | Ranked frame/measurement sequence with an explicitly identified sequence dimension, not an inferred clock. |
| `scientific.temporal_trace` | Explicit observed time-coordinate/response metadata, not an optical spectrum or invented absolute origin. |
| `scientific.measurement_array` | Other typed scientific measurement metadata using the same stable shape/coordinate/component representation. |

These are Library record types, not new Dataset contracts. Other providers can
declare other types through the same public vocabulary without CORE/Browser
branches. There is no vendor/extension whitelist and no new Library ingestion
workflow or automatic population from Acquisition. The provider contains no
new scientific-format parser or Dataset writer.

### Existing numeric spectra stay numeric

Absent `fields.representation` means `numeric_source`. Original `format=csv|jcamp`
and typed `parser_options` remain mandatory on that path, and the unchanged
`api/spectrum_validation.py` delegates to the existing scientific parser and
finite/monotonic Spectrum API exactly as before. The old whole-schema SHA
`0904b93dbf9413708bd64825abbfe4201b8cf6e40cc53e1f3f3de177ea44025c`
is explicitly compatible for the existing type. Missing optional historical
`content_contract` is preserved; an explicit contradictory contract refuses.
Existing payloads, Entry/Library identities and numeric bytes are not rewritten.

### Description-only is explicit and carries no numeric qualification

Set `fields.representation=description_only` and provide `fields.measurement`
with `schema=gxtxt.library_measurement_description.v1`. This same representation
is mandatory for the seven new record types. A description has no top-level
`content_contract` asserting a validated canonical payload. It cannot claim
original numeric parser options, format or validated sample count. An original
SP/SIF 1-D spectrum description therefore uses the SAME `scientific.spectrum`
record type, with its observed `measurement.source_format` and provenance, not
a fabricated CSV conversion or an alternate spectrum schema.

The inert `measurement` object carries:

- Observed `source_format`, original `source_sha256` and/or `source_resources`
  (`source_id`, `sha256`, `role`), `modality` (empty means unknown), and optional
  literal `dataset_contracts`. Unknown future contract IDs remain descriptions;
  this declaration neither registers nor validates them.
- `storage_kind=numeric_variables`, or `opaque_resource` with a `binary_resource`
  hash/media type/storage kind and no fabricated numeric Variables.
- `dimensions`: stable `dimension_id`, exact nonnegative integer `size`, optional
  observed quantity/unit/label. `variables`: stable `variable_id`, observed
  `dtype`, exact integer `rank`, `shape` and `dimension_ids`, `coordinate_role`,
  coordinate/component Variable references, `unit` and `unit_status=declared|unknown`.
  Scalar rank0 has empty shape/dimensions; missing units remain empty/unknown.
- Optional existing axis fields, component groups (`component_id`, observed
  `representation`, ordered `variable_ids`/`roles`), sequence dimension IDs, and
  bounded finite JSON `observed_metadata`. No values are converted, flattened,
  resampled or numerically qualified by this metadata validator. Counts/rates,
  pixels, physical wavelength/shift/frequency and time remain their actual units.

Description metadata is bounded to128KiB with up to256 Variables/dimensions.
Structural checks prevent contradictory rank/shape/coordinate/component identity,
unknown-unit relabeling and unsupported representation selectors; they are not
proof that an unavailable scientific source or canonical numerical payload is
correct. Optional resources retain the existing Library resource/size/access
policy. Unavailable external originals can still be inspected as metadata.

### Identity and explicit links

Entry identity/revision/content SHA and Domain schema SHA remain distinct from
a Dataset. `scientific.describes_dataset` is an attributed explicit assertion
from a record to its own type's `canonical_dataset` anchor, requiring actual
Session/Dataset identity, payload SHA revision, matching SHA and actual contract.
The Library does not resolve that Session or create a Dataset on admission. The
existing Dataset Viewer validates current Session/revision/hash/contract when
explicitly followed; unavailable/stale targets remain unavailable, never rebound.
`scientific.related_measurement` permits attributed associations between declared
measurement records; it asserts no numerical equality, correlation or conversion.
Existing Library/external anchors preserve their pinned identities and evidence.

Normal Browser metadata/search/Related and the existing public Domain schema/
manual APIs discover these declarations. Merely viewing, describing or linking
a record publishes no Session data. Actual future Library-specific binary
importers, authentic PRF/fluorescence qualification and numeric scientific
validation remain separate gates, not implied by this provider declaration.

The description selector requires the P033 additive public Library domain owner.
A pre-P033 core that does not implement that vocabulary cannot prepare a
description-only spectrum as a validated numeric payload: the provider refuses
the contradictory contract. Module packaging/version/checksum seals must match
the delivered P033 CORE; a descriptor version alone is not a capability grant.

When deliberately changing representation in the existing generic manual form,
clear the other mode's fields explicitly: numeric source uses format/parser
options, description uses measurement JSON. The provider refuses contradictory
settings rather than silently discarding them. Existing field choice/multiline
controls expose the declarations; no new domain-specific Browser is introduced.

Compatibility: CORE `domainApiInfo` advertises `literal_content_contract_selector_v1` for the additive literal selector. Description-only records require that P033 feature; the provider explicitly refuses their admission on earlier CORE code rather than accepting a misleading fixed numeric content contract. Existing numeric_source CSV/JCAMP entries retain the original validator and behavior. Schema discovery alone is not proof that an older host can admit every new representation.
