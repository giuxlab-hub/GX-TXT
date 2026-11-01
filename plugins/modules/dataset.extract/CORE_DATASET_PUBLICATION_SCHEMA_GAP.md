# Historical CORE request — Dataset Publication API v1 schema inheritance

SPDX-License-Identifier: GPL-3.0-or-later

## Status

**Resolved in GX-TXT 0.9.7.19.**

This file is retained because `dataset.extract` 1.1.0 documented the original CORE limitation and requested a minimal backward-compatible extension. It is no longer an active limitation for `dataset.extract` 1.3.0 pure subset/projection publication.

## Implemented CORE interface

GX-TXT 0.9.7.19 extended the existing Dataset Publication API v1 request with:

```ini
[publication]
schema_source_dataset_id=source.dataset
schema_source_variable_ids=v0004;v0001;v0003
```

The source variable IDs are ordered one-to-one with the published `variables` list and CSV header.

The Octave helper accepts the same data as:

```octave
meta.schema_source_dataset_id = 'source.dataset';
meta.schema_source_variable_ids = {'v0004','v0001','v0003'};
```

No second Publication API or second Dataset Schema was introduced.

## Implemented inheritance behavior

CORE resolves every mapping by:

```text
source_dataset_id + source_variable_id
```

and allocates fresh derived variable IDs in output-column order. Source IDs never become derived identities.

GX-TXT 0.9.7.19 inherits these interpretation fields:

```text
unit
canonical_unit
to_canonical
from_canonical
display_label
semantic_role
semantic_source
semantic_reason
instrument_id
instrument_channel
value_kind
value_format
decimal_separator
time_reference
time_origin
```

The generated output file remains authoritative for physical/output-column metadata. CORE rebuilds source-column position, canonical position, original header, canonical name, and delimiter from the published CSV rather than copying source physical provenance.

Declared `units` and `semantic_roles` must agree with the mapped source variables. Invalid source datasets, missing/duplicate mappings, header mismatches, and contradictions fail publication transactionally.

The behavior is additive: requests without the inheritance fields retain legacy Dataset Publication API v1 behavior.

## dataset.extract 1.3.0 use

Version 1.3.0 provides both inheritance fields on every derived CSV publication. Its ordered source mapping is also retained in module provenance.

Normal, one-row, and header-only outputs are tested explicitly, so scientific interpretation no longer depends on post-publication value inference.

## Unrelated publication behavior

GX-TXT 0.9.7.19 still permits a module to republish a Dataset ID that it already owns through Dataset Publication API v1. No create-only capability is implemented in the actual 0.9.7.19 interface, and `dataset.extract` 1.3.0 does not emulate one through private registry access.
