# Script Parameter Dataset API v1

Save additively accepts final `?invocationSchema?` after `?reviewed?`, preserving
manual invocation-only declarations alongside the saved schema. Load additionally
returns `invocation_parameters`. Structured metadata separates
`registry_declarations` and `invocation_declarations` while `declarations` remains
the complete effective typed schema. Existing declaration-only presets retain
compatibility. See [source and invocation parameter contract](SCRIPT_PARAMETER_DECLARATIONS_v1.md).

SPDX-License-Identifier: GPL-3.0-or-later

`gxtxt.script_parameters.v1` is an ordinary canonical typed Dataset for one
reviewed Script invocation. It extends the Script Registry/Execution owner;
Dataset Publication API v2, Variable Schema v3, Metadata, Namespace and Canonical
Dataset access retain all persistence, integrity and authorization authority.
The numeric CSV `PARAMETER_SET_API_v1` contract remains separate.

Host review operations are:

- `scriptParameterDatasetSave session reference supplied dataset_id ?label? ?reviewed? ?invocationSchema?`
  validates effective typed values and creates a new Dataset. Optional reviewed
  metadata pins SHA/revision/declarations; Script identity is checked again
  before finalization. Existing IDs are
  refused; no implicit replacement, automatic Save or execution occurs.
- `scriptParameterDatasetLoad session reference dataset_id` validates the whole
  preset before returning `parameters`, `dataset_id`, opaque `revision`, `sha256`
  and `variable_ids`. The caller applies values only after success.

These are host-only invocation-review operations: scripts already consume the
same typed data through Canonical Dataset APIs and receive loaded provenance at
`gxtxt_context().parameter_dataset`. They do not acquire interactive Registry
mutation or review state. Producers retain ordinary publication capabilities.

The Dataset contains one row with a stable Variable ID `p_<parameter_name>` for
every effective parameter. Integers use int64, finite real numbers float64,
booleans bool, strings and choices string. Original declaration type, constraints,
required/default rules and choice vocabulary are preserved in structured metadata;
a string-backed choice is still validated against its exact declaration. An
out-of-range integer is refused by Publication, rather than narrowed. Existing
UI Field normalization maps whitespace-only optional strings to empty; other
Unicode, quotes and embedded newlines retain their exact text. Unset
optional numeric values remain absent. A script with no effective values has
only the bool `preset_marker` Variable and an empty names list. Every preset
includes that true marker to retain a physical row even when its only parameter
is an empty or whitespace-only string.

Structured metadata `script_parameters.*` records schema
`gxtxt.script_parameters.v1`, qualified `reference`, `source_sha256`,
`script_revision`, canonical sorted `declarations` and effective `names`.
Metadata and typed payload commit atomically through Publication. The owning
producer is the language's existing Analysis module. Save defaults to that
producer's private namespace; cross-namespace reading does not grant writes.
The display label is presentation only. No private preset file/registry exists.

Load requires the reviewed current Session, exact contract, compatible qualified
Script reference/source SHA/revision/declarations, exact Variable IDs/dtypes and
one-row shape, complete effective names, valid current required/type/range/choice
rules, matching canonical payload SHA and an unchanged Dataset revision through
readback. Missing/extra/duplicate names, wrong types, altered payload, incompatible
Script or foreign Session refuse without applying partial values. Loading a
moved preset explicitly is permitted in its current namespace; an already loaded
review becomes stale if that identity/revision changes.

Runner values remain editable after Load. Run passes effective values separately
from the preset provenance. Job preparation reloads and verifies the exact preset
revision/SHA/Variable IDs, then freezes those identities in the immutable receipt
and runtime. A later Bridge call rejects a changed preset. Choosing a different
Script or Session requires a new review. Preset editing never updates a registered
Script's source, schema/defaults or debugger state.
