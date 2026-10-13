# Scientific Library Manager API v1

## Step 1 additive registry contract (dev-045)

This is an additive v1 extension. Existing managed package installation,
`listInstalledLibraries`, IR/NMR entry access, and saved schema-1 registries keep
their prior behavior. `listInstalledLibraries` remains the managed-library view.
The manager is CORE loaded and does not depend on Analysis execution state.

`libraryRoot` returns the effective absolute GX-TXT Library Root. The persisted
configuration key remains `libraries.scientific_root`; callers should use the
public CORE method or `configurationGet`, not the internal environment compatibility mechanism.

`listRegisteredLibraries` lists active managed, external and remote records.
`getLibraryInfo` accepts each mode and removed tombstones. Every public record
provides `library_id`, `library_type`, `display_name`, `provider_id`,
`provider_version`, `mode`, `version`, `state`, `availability`, `origin`,
`license`, `rights`, `read_only`, `authentication_required`,
`authentication_status`, and `provider_config` (JSON object). Historical
managed records receive compatible defaults on read. Managed payloads remain
under Library Root; external/remote registrations store metadata only.

`registerLibrary fields` accepts a Tcl dict with `library_id`, `library_type`,
`display_name`, `mode=external|remote`, optional `version`, `origin`, `license`,
`rights`, `read_only=0|1`, `availability`, `description`, and provider-owned
`config.<name>` fields. It returns the public record. `unregisterLibrary id`
marks an external/remote record removed and retains its ID as a tombstone.
Managed libraries continue to use `installLibrary` and `removeLibrary`.
Providers may declare `REGISTRATION_SCHEMA` in their Python entrypoint as a
mapping from mode to `{required: [...], optional: [...]}` and optionally
`validate_registration(mode, configuration)`. CORE checks keys and delegates
semantic validation; it does not interpret endpoint or local database formats.
Secret-like configuration keys are rejected. Credential profiles and operational
access to external/remote entries are later-step work.

Provider discovery in the Tcl host uses the loaded module catalog descriptors,
including independently installed provider-only plugins. A provider-only module
uses `kind=service`, `runner=service`, `selectable=0`, and a
`[library_type_provider]` descriptor. Legacy provider descriptors with
`kind=analysis`, `runner=service` stay loadable and are excluded from runnable
Analysis jobs. Direct standalone invocation of the Python helper retains its
bundled-descriptor fallback for compatibility.

GX-TXT 0.9.8.06 manages scientific data libraries independently of the framework and executable plugins. CORE verifies the data-only package, stores its payload, tracks versions and checksums, and resolves an installed Library Type Provider. The provider validates scientific meaning and exposes entries. CORE contains no IR-specific parser.

## Public Tcl API

The namespace is `::GX::ScientificLibraryManagerAPIv1`. It is loaded with the framework.

| Operation | Result |
| --- | --- |
| `listLibraryTypes` | Library types served by installed providers. |
| `resolveLibraryProvider type` | Provider ID and version for a type; explicit error when absent. |
| `listInstalledLibraries` | Public registry records for installed libraries. |
| `getLibraryInfo id` | Registry record, including `removed` tombstones. |
| `queryCompatibleLibraries type` | Installed logical library IDs for a type. |
| `installLibrary package.zip` | Validate and install a new data package. |
| `updateLibrary id package.zip` | Validate a newer package with the same ID, provider, type and stable entries. |
| `removeLibrary id` | Remove managed payload and mark saved references stale. |
| `verifyLibrary id` | Recheck package and payload hashes and provider entry index. |
| `openLibrary id` | Resolve an installed logical ID without returning a storage path. |
| `listLibraryEntries id` | Provider-indexed stable entry IDs. |
| `openLibraryEntry id entry` | Validate an installed entry and open the provider-declared specialized Viewer with `library_id` and `entry_id` context. |
| `readLibrarySpectrum id entry` | Provider spectrum fields, arrays, metadata and provenance for supported one-dimensional spectra. |

`openLibrary`, entry access and verification reject removed IDs. The public registry contains origin, license, type, version, provider, state, hashes, timestamps and entry count. Storage paths and scientific entry metadata remain private. An update cannot remove an existing stable entry ID.

A Library Type Provider may declare both `entry_viewer_module` and `entry_viewer_id` in its `[library_type_provider]` descriptor section. They are optional for types with no specialized Viewer. `resolveLibraryProvider` exposes these validated IDs, and `openLibraryEntry` uses the normal Viewer Provider API to open a selected entry. The manager checks that the library is installed and the entry belongs to it before dispatch. No Session is required for a library entry.

## Data package

The ZIP contains exactly `library.ini`, `SHA256SUMS.txt` and `payload/library.gxsrl`. The manifest declares library ID, type, version, provider requirement, format version, name, description, license and origin. `SHA256SUMS.txt` binds the payload bytes. The manager rejects extra paths, directories, links, oversized members, checksum mismatch, unsafe IDs and incompatible providers. It never executes content from a data package. Provider validation runs before the registry commit.

The first independently distributed type is `spectroscopy.ir.reference`, served by the separately installable `library.spectroscopy.ir.reference` plugin. The IR provider validates the Scientific Reference Library database, IR spectral semantics, stable spectrum IDs and provenance. The Scientific Spectral Library viewer offers **Install library...** when its reference list is empty, then discovers the installed logical ID through this API. Existing user-authored reference libraries remain visible.

Task 006 adds `spectroscopy.nmr.reference` with a managed Cambridge 1-D NMR library. The generic `viewer.reference_library` handles installation, search, version and provenance. Its selected-entry action calls `openLibraryEntry`, which routes to the provider-declared `viewer.nmr_reference`; NMR ppm/nucleus presentation stays in that specialized viewer. The current IR viewer continues to serve its established comparison and ranking workflow.

Install or update the provider through Plugin Install API v1, then install a data package through this manager. A library can be updated or removed without updating the framework, the provider, or the viewer. Removing a package leaves a tombstone so a saved ID reports a stale reference rather than resolving to different content.

The manager stores payloads and its registry below `XDG_DATA_HOME/gxtxt_pipeline/scientific_libraries` (or the XDG default). This path is internal and must not be used by consumers.
