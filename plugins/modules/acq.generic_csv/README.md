# acq.generic_csv

Standard Module API v1 acquisition/import plugin for one or many generic CSV tables. It creates canonical datasets, assigns dataset IDs/contracts, snapshots RAW sources, and records SHA-256 provenance.

Version3 accompanies DEV111-P032 CORE. Text decoding is strict and shared by
recipe inspection and conversion, including explicit cp1252 and UTF BOM codecs.
Linear coefficients must be finite; finite inputs that overflow their declared
linear conversion refuse. Existing scientific NaN/Inf payload policy is retained.
Unit labels do not imply an undeclared conversion.

CORE pins a queued recipe's file, normalized definition and parser SHA. A changed
recipe requires renewed selection. Actual enabled row mappings, names, units,
delimiter, header and contract are captured as an effective configuration.
Scale/offset follow the original mapping name through removal/reordering and
canonical renaming; an unknown mapping identity requires review in CSV Importer
Builder. The actual Dataset Registry exposes `importer_reviewed_*`,
`importer_row_*` and `importer_effective_config_json/sha256`, the recipe file SHA,
codec and parser identity. Header metadata uses the same decoded RAW prefix;
`importer_header_digest_scope=prefix` distinguishes it from full RAW SHA.

Recipe INI portability preserves unavailable contracts as inert drafts. Actual
Test/scientific import requires an installed compatible Table contract. A
Builder Test checks parser/mapping/codec/coefficients and compatible contract
availability; canonical Dataset, variable schema and payload acceptance belongs
to the actual CORE import/publication transaction.

RAW regeneration during a canonical column edit replays the captured codec and
linear transformations and refuses a changed configuration/parser SHA. Its last
RAW replay is inspectable as `importer_regenerated_*`. Canonical source snapshots
remain canonical: coefficients are not applied twice. Older recipe outputs with
no reviewed configuration use the existing canonical snapshot lane; restoring
originally omitted variables requires a reviewed RAW reconstruction capability.

See also `docs/guides/GENERIC_CSV_MULTI_IMPORT.md`, `docs/guides/MULTI_DATASET_IMPORT_AND_INSPECTION.md`, `docs/api/DATASET_API_v1.md`, `docs/api/DATASET_INSPECTION_VARIABLE_MAPPING_API_v1.md`, and `docs/api/CONTRACT_REGISTRY_API_v1.md`.
