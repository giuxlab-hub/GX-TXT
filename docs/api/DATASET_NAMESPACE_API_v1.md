# Dataset Namespace API

`DATASET_NAMESPACE_API_v1` organizes canonical Datasets within a Session. Namespaces are neither physical paths nor Dataset identities/stores. Existing Publication, Metadata, Catalog and Session Manifest remain authoritative. Reads can cross namespaces; producer writes are restricted.

## Identity and user/admin operations

`datasetNamespaceNormalize value` trims whitespace and empty slash components. It returns1–32 case-sensitive components, at most512 characters overall, using letters/digits, underscores, hyphens and dots. `.` and `..` are forbidden. A legacy leading `current` projects to `base` without rewriting sources.

Tcl functions live in `::GX`:

- `datasetNamespaceGet session datasetId`: recorded namespace, or deterministic `base` when absent.
- `datasetNamespaceSet session datasetId value`: user/admin placement change, writing only reserved framework metadata. IDs, schema, payload and provenance remain intact.
- `datasetNamespaceCurrentGet ?session?`: current user selection, default `base`.
- `datasetNamespaceCurrentSet session value`: change Current in the open Session through Session Persistence. It does not move existing Datasets.
- `datasetNamespaceCreate session value`: idempotently create an empty namespace in the existing Manifest.
- `datasetNamespaceList ?session?`: occupied, empty/current/pending namespaces and ancestors; no separate namespace catalog.
- `datasetNamespaceForModule moduleId`: `module/<id>` with reversible UTF-8 hex fallback where necessary.

Current and empty namespaces persist under `[dataset_organization]` and `[dataset_namespace.N]`. Dataset moves, Current changes and empty namespace creation notify existing Catalog subscribers. New registrations with a known producer receive `module/<producer>`; anonymous registrations use `base`. Pending is an acquisition context, never a canonical publication destination.

## Producer publication and shared scientific inputs

Ordinary Publication v2 and File Publication assign the producer's private module namespace. A producer cannot replace content moved outside its assigned namespace. Streaming writers recheck placement at finalization. Historical records without placement remain writable only by their recorded producer, acquiring explicit placement on publication.

`datasetNamespaceAuthorizeSharedInput session namespace producers` is a host-only user/admin operation. It records an explicit authorized producer list in the **same Session Manifest**, beside namespace definitions. `datasetNamespaceSharedInputs session` reads that policy. Private `module/*` and pending namespaces cannot be shared. An empty list revokes permission.

An authorized producer may pass `dataset_namespace` to ordinary Publication APIs to **create a new Dataset** there. Existing IDs, `replace_owned`, foreign overwrite, mutation or deletion are never granted by this policy, even to the original creator. Namespace spelling and shared read access grant no write permission. A caller-supplied namespace without a real grant is rejected. Private module publication remains the default. Shared inputs preserve stable Dataset identities and source provenance.

## Browser, metadata and imports

The Dataset Browser is a Catalog projection. Row highlight is browse state; the row glyph or explicit guarded context action activates the canonical inspection choice. Preview shares this authority. Namespace context menus and the pictographic manager use the same user/admin create/move/current APIs, including drag/drop.

Ordinary Metadata UI/text export hides reserved private fields. Portable Dataset import preserves private module fields while assigning the target Session Current namespace (or `base` when Current is pending). Bound module contexts cannot invoke user/admin placement operations. Metadata, schema, notes, rename and deletion retain existing module placement checks. In-process trusted Tcl is not an OS sandbox.

## Script Bridge and migration

Python/Octave operations are `get`, `list`, `current_get`, `module_default`; the trusted host supplies Session and module identity. Namespace grants/moves/create/current mutation remain host-only. Publication can request only an explicitly authorized CREATE-only shared destination.

`datasetNamespaceMigrationPlan ?session?` describes legacy Dataset/Manifest fields without rewriting them. `datasetNamespaceMigrate session newBackupArchive` creates and validates a portable backup outside the Session, then migrates through the existing Catalog transaction. Errors restore affected registry, metadata, Manifest and in-memory settings. Restore by importing that backup into a new directory. Reserved namespace keys remain under the existing private metadata authority.
