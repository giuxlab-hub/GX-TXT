# Portable Dataset Group resources v2

The existing Portable Resource owner additively supports `dataset_group` through
`::GX::portableResourceExportGroup groupId newArchive` and the existing
`portableResourceValidate`, `portableResourceInspect` and `portableResourceImport`.
`portableResourceGroupApiInfo` describes this host-only API. Individual Dataset,
Graph and Workspace v1 schemas and ZIP operations remain compatible.

Group descriptors retain original creation time and the bounded inert lifecycle
history when present. Import preserves that history and source revision and
appends an attributed import event; older v2 descriptors without these optional
fields remain compatible. History never supplies executable commands or changes
scientific resource identity.

Group ZIP uses `schema=GXTXT_PORTABLE_RESOURCE_v2`, `schema_version=2`,
`resource_type=dataset_group`, one `group/descriptor.json` and ordinary validated
Dataset transport records under `datasets/<id>/`. Every source/payload hash,
Variable schema, member contract/role and primary ID is validated before staging.
The existing owner handles ZIP path/symlink/count/ratio/size/SHA limits and HDF5
external-reference rejection. No separate archive engine or executable payload.

Export freezes one complete Group under the existing Dataset authority lock and
preserves order, revision, Namespace, original source SHA/module/name and actual
member bytes without duplicating RAW acquisition files. An existing output is
never overwritten. Degraded Groups refuse; no missing member is fabricated.

Import options specific to Group resources are:

- `group_id`: optional destination identity, source ID by default;
- `dataset_id_map`: optional dictionary of original member IDs to new IDs;
- `destination_namespace`: one destination Namespace, Current by default.

All IDs, member destinations, collisions and mapping keys are preflighted, then
the existing Dataset importer restores each member and Group authority records
the wrapper within one recovery journal transaction. A late failure rolls back
all payloads/metadata/Registry/membership. Primary and admitted same-package
`source_dataset_ids` references follow the explicit ID map; unrelated references
are preserved. Group revision and original descriptor provenance survive cold
reopen. Results report `atomic=1`, `group_id`, `imported_dataset_ids`, `id_mapping`
and per-member results, plus standard package SHA/integrity.

An individual member exported through ordinary Dataset ZIP remains v1. It records
`original_group_id` and `original_group_state=DETACHED`; importing it creates only
that Dataset and a descriptive warning, never an incomplete Group. Whole-Session
portable transport includes the ordinary Session Group descriptor as metadata.
