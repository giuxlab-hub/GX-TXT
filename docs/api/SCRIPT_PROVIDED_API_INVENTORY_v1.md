# Source-declared Script API inventory v1

`::GX::scriptRegistryProvidedApiInventory reference ?options? ?session?` is the
read-only trusted host operation of the existing Script Execution / Registry
owner. `reference` is an existing qualified User or Session Script/Project.
The complete source set comes from its admitted Registry snapshot. No source is
imported or executed. This operation grants no Script Bridge capability, native
filesystem access, Registry mutation, public API registration or execution right.

The result uses `gxtxt.script_provided_api_inventory.v1`: `provided` API identities
are distinct from `consumed` requirements. `operations` bind source-declared
`gxtxt_api_export` operations to actual implementation files, functions, ordered
signatures, declaration lines and SHA-256. Arguments/results, unit behavior,
effects and capability requirements retain their explicit literal schemas.
`valid` and bounded diagnostics describe static compatibility, not runtime
qualification. An ordinary Analysis entrypoint can be reported as an unsafe
function loader while legitimate helper exports remain independently describable.

Options accept only `expected_sha256`, `expected_revision`,
`expected_record_sha256`, `expected_owner_context`, `draft_sources`, and
`draft_entrypoint`. Expected comparisons use the existing Registry identity owner
before and after reading/discovery. A changed record, configured/physical root or
source snapshot refuses. An explicit Session is frozen for this read.

The explicit `session` argument is the Session directory, never its opaque
document-lifetime token. The editor canvas captures these separately: directory
for the existing Registry read and token for lifecycle admission. Session-source
results and implementation navigation recheck both the current directory and
token, plus the complete source/record/root comparison fields. Reopening the
same path cannot adopt a result from an older lifetime. User-source inventory
does not acquire a scientific Session lifetime merely because a Session is open.

`draft_sources` is the complete in-memory path-to-UTF-8 source map for an unsaved
preview, not a patch overlay. Optional `draft_entrypoint` requires that map;
otherwise the registered entrypoint applies. Existing 256-file, 4 MiB per-file
and 16 MiB Project bounds remain. Paths, implementation names and source schemas
use the shared static extractor's normal admission. Removing the only exporting
file produces an empty inventory; a retained declaration with no implementing
function is invalid. No unsaved preview revises source or metadata.

Results add `reference`, full `registry_baseline` comparison fields,
`source_scope` (`registered_snapshot` or `unsaved_draft_preview`) and
`execution_authority=none`. A Builder must validate its exact current source
closure and use the existing managed execution/Script Bridge owners for genuinely
callable operations; this inventory cannot substitute for either gate.

Python uses literal `gxtxt_api_export({...})`; Octave uses literal JSON in
`gxtxt_api_export('...')`, including declarations inside the actual filename-matched
primary function. This document describes inventory only. Runtime marker support,
automatic Builder manifests and managed invocation have separate implementation
and acceptance obligations.

The additive managed invocation contract is documented separately in
[SCRIPT_PROVIDED_API_RUNTIME_v1.md](SCRIPT_PROVIDED_API_RUNTIME_v1.md). Static
inventory continues to grant no runtime authority.
