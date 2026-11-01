# Framework Maintenance

SPDX-License-Identifier: GPL-3.0-or-later

Configuration → Framework Maintenance is a child of Configuration. Its persistent
left sidebar selects one right content pane: Framework Status, Cache & Temporary
Files, Logs & Diagnostics, Backup & Restore, API Catalog, Modules & Plugins, and
Configuration Browser. Existing tabs and Save user defaults remain available.

## Public ownership

`::GX::frameworkMaintenanceApiInfo` describes this trusted desktop host API.
Reusable orchestration lives in CORE; widgets own presentation drafts only.
Configuration, Resource Management, Diagnostics, Project/Session Portable, native
Workspace/History and API Catalog retain their existing state and persistence.
These administration operations are host-only: they access installation paths,
user settings and transport across Projects/Sessions, rather than scientific
Script data. They grant no new Python/Octave or restricted Viewer capability.

Preview operations return `{token kind expires preview}`. A preview expires after
600 seconds and is bounded to 64 outstanding plans per process. Changes require
the exact token; consumed/expired/changed plans refuse. Programmatic callers are
responsible for displaying the preview and obtaining explicit confirmation.

## Framework Status

`frameworkMaintenanceStatus` reports the actually executed framework root,
VERSION/patch identity and available public Workspace/storage/History/Catalog and
Diagnostics state. Missing owners report `unknown` with the reason. This does
not read the newest release archive or assert that it is installed.

## Cache & Temporary Files

`frameworkMaintenanceCachePreview ids callback` obtains a measured owner inventory
asynchronously. The callback receives `code result`; success contains an expiring
preview for the selected exact registered allocations. Only verified released
reconstructible caches and owned disposable temporary allocations qualify.
`frameworkMaintenanceCacheCleanup token callback` delegates exact IDs to Resource
Management, which rechecks leases, ownership and allocation identity at commit.
Per-resource refusals and partial results remain visible.

The GUI measures categories, owners, liveness, byte/file counts, state and
eligibility. Existing read-only legacy observations remain protected. Unknown
reference counts are unknown. Native Workspace/Session/Dataset/Job/provenance,
source scripts and the Script Registry are never cache-cleanup targets. No
filename pattern grants deletion rights or permits a broad recursive cleanup.

## Logs & Diagnostics

The page uses `stderrDiagnostics read/meta/export/request/cancel` and its
`cleanup_preview/cleanup` operations. It reads at most 100 records/524288 bytes
per page, filters that displayed page, and explicitly exports selected stable
record IDs. A pending scan has a 60-second GUI budget. Opening the page does not
enable capture. Cleanup is distinct from export and requires a complete preview,
confirmation, inactive writer and unchanged owner preimages. Scientific Job
logs, publication records and History remain untouched.
See [Diagnostics](STDERR_DIAGNOSTICS_API_v1.md) for exact native bounds and receipts.

## Backup & Restore

`frameworkMaintenanceBackupInventory` enumerates ALL registered Projects and
associated Sessions, plus physically discovered unassociated Sessions from the
configured Session root, Project roots and current Session. Paths outside that
discovery scope are explicitly unknown; the page does not search the machine.
Conflicting membership refuses. The Default / Unassigned Project is a Project
and is included.

`frameworkMaintenanceBackupPlan include|exclude` requires an explicit policy for
discovered unassociated Sessions and captures the full inventory. After preview
and confirmation, `frameworkMaintenanceBackupExport token archive ?progress?`
creates one new archive containing every Project package and, if requested,
unassociated Session packages. The manifest lists source identities, associated
Experiment/Session mappings, excluded orphan records, discovery scope, carrier
installation, sizes and SHA-256 values. Project/Session Portable export and
validation own all scientific serialization, dependency admission and native
Workspace/History checkpoint/foreign-writer locks.

Unassociated Sessions physically below a Project's `Sessions/` directory are
explicitly excluded from that Project's raw resource copy through the Portable
owner. Include adds each once as a mapped Session Portable package; Exclude
omits its standalone package and raw resource copy. Nested Project exclusion
metadata must agree with the aggregate policy, preventing duplicate or silently
included Session data. Required dependencies of included registered Sessions
retain the existing Portable contract regardless of physical source location.

Active managed/pipeline writers, pending Project organization transactions,
changed registry/membership/source snapshots,
unresolved scientific dependencies, unsafe destinations and existing archive
names refuse publication. The archive must be outside every source tree.
Portable snapshot capture uses existing synchronous owner barriers; the progress
callback may repaint but must not dispatch scientific mutations or nested edits.
The source inventory is checked before and after capture. This is a consistency
guard for cooperative owner operations, not a filesystem-wide transaction against
hostile uncooperative writes.

`frameworkMaintenanceBackupValidate archive` checks the complete aggregate and
every nested owner package without importing. It rejects unsafe/duplicate names,
symbolic entries, schema/identity/count/hash mismatches and malformed scientific
packages. Manifest size is at most 4 MiB, with at most 20000 nested packages and
16 TiB per nested transport package. Validation uses private temporary extraction;
adequate disk space is required.

`frameworkMaintenanceBackupRestorePlan archive` prepares a validated inspection.
After explicit confirmation, `frameworkMaintenanceBackupRestore token` validates
again and delegates each Project/Session import to its existing owner. Imports
create new identities and non-overwriting destinations; the receipt retains
source→new Project/Experiment/Session mappings and nested owner diagnostics.
Unassociated imports use the existing Default Project policy and a new Session
directory. If a later owner import fails, the result is `partial`, listing every
already committed import and the failing source/reason. Earlier commits remain
visible for inspection; they are never deleted to simulate aggregate atomicity.
Existing Projects, Sessions and scientific data are preserved.

## API Catalog

The page consumes `apiCatalogDiagnostics`, bounded Query/Get, selected/manual-page
inspection, normal manual Open and `apiCatalogRefresh callback`. Explicit source
verification is separate from ordinary status. Refresh/Reconcile stages the next
process snapshot, preserves the current good snapshot on failure and reports
whether restart is required. The page never edits SQLite or accepts SQL.

Manual inspection distinguishes physical absence, incorrect declarations, stale
index, unsafe path, unavailable provider and actual renderer errors. Available
file status does not prove rendered pixels. See
[Catalog](API_CATALOG_SERVICE_API_v1.md) and
[Documentation](DOCUMENTATION_BROWSER_API_v1.md) for source/window correlation.

## Modules & Plugins

`frameworkMaintenanceModulesInventory` uses public operational metadata.
`frameworkMaintenanceModulesPlan ?disable_optional|restore?` previews transitions;
`frameworkMaintenanceModulesApply token` delegates enablement to `moduleSetEnabled`.
Mandatory CORE/ALWAYS authorities remain unchanged. Optional dependencies needed
by enabled protected modules are retained and listed in `kept`. Active operations,
changed versions/inventory/states and new dependency conflicts refuse stale plans.
Packages and scientific data are not removed.

Previous enablement and Run selection are captured in process memory, with honest
per-module partial errors. Restore uses the exact captured states and validates
dependencies again. Close/restart loses that transient restore set. Ordinary
installation/uninstallation remains in the linked Plugin Manager.

## Configuration Browser

`frameworkMaintenanceConfigurationInventory ?query?` projects field IDs, sections,
types, supported scopes, factory/User/Session/effective values and effective
origin from Configuration. Secret/sensitive descriptors and credential-like IDs
are redacted and excluded from editing/export/reset/import. Framework/runtime and
readonly fields remain protected.

`frameworkMaintenanceConfigurationExport user|session path` writes new bounded
JSON data, never executable Tcl. Session export includes explicit overrides only.
`frameworkMaintenanceConfigurationPlan edit|import|reset scope ids ?values?`
creates a typed diff. Edit takes an ID→value dictionary; import takes a JSON path
and requires the exact declared scope; reset takes selected IDs. Session reset
inherits the User value where supported, otherwise uses its factory default.
Already inherited values and unchanged Session-only defaults are omitted from
the diff, so future-output selectors do not require a currently materialized
Dataset when no binding changes. Actual changes retain binding validation.

`frameworkMaintenanceConfigurationApply token` invokes `configurationCommit`
with captured expected values and Session lifetime. Field/section/all reset is
an explicit selection in one scope, never a merge of User and Session settings.
All candidates validate before any durable commit; invalid bindings, changed
values, a changed inheritance target User default or a switched Session refuse.
The GUI displays the diff and asks explicit
confirmation. Editing the visible field value invalidates that diff; preview it
again before confirming. A new inspection or operation receipt also retires the
previous displayed plan, including when an import fails; earlier hidden changes
cannot remain confirmable behind another result. Secrets are neither exposed in
receipts nor silently imported.
