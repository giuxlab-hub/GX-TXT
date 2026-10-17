# Scientific I/O API

`SCIENTIFIC_IO_API_v1` gives cooperating scientific clients location-opaque source tokens and canonical Dataset access. It extends existing Dataset File Publication, Dataset Catalog/Authority, Namespace, File Publication and Resource Management. Canonical identity, format/codec and physical transport remain distinct. No new Dataset registry or persistent resource store is introduced.

## Authorization and browsing

The host user/admin explicitly calls `::GX::scientificIoAuthorize root producers allowImport? allowExport?`. This path-bearing grant operation is deliberately absent from Script Bridge. Module contexts cannot issue it. Tokens belong to the current host process/Session lifetime and named producer identities. They are not cross-process credentials; an independent Bridge host must receive its own trusted host authorization. Browsing permission, content import and output creation are separate grants.

`scientificIoBrowse scope producer directory_token? offset? count?` returns at most 500 metadata entries per page, with opaque child tokens, name/type/size and availability. An unchanged entry keeps the same token within its authorized scope; changed identity receives a new token. Directory tokens permit bounded tree navigation, not content consumption. Symlinks/special files are unsupported. Root and every descendant are opened relative to validated directory descriptors with no-follow semantics. No entry token contains a usable scientific filename/path. The current local directory implementation sorts at most10,000 entries in one directory; it is not an unlimited recursive index. Host budgets are32 source scopes and20,000 retained entry tokens per Session, with explicit budget errors and stale-Session cleanup.

## Canonical adoption and reading

`scientificIoImport scope producer entry_token request` requires an explicit content grant. Request fields are `dataset_id`, `contract`, `format`, `storage_kind`, `media_type`, `policy` (`copy` or `reference`), optionally `expected_sha256` and an authorized `dataset_namespace`. No source path is accepted. CORE revalidates entry identity, regular-file/single-link status, permissions, source SHA and descriptor stability.

Copy mode materializes through a managed temporary allocation and existing transactional File Publication, with matching SHA before canonical commit. The small generic materializer is limited to 64 MiB; use a verified reference or an existing specialized acquisition materializer for larger input. It retains immutable original sources and creates a distinct canonical copy.

Reference mode creates an immutable/read-only canonical file Dataset through the same Publication owner. The existing registry privately retains physical location; public identity remains the Dataset ID, source SHA and format. No source bytes are copied. It is an opaque file contract, not automatic CSV/HDF5 schema inference. Numerical consumers must use a registered format importer/schema before treating opaque bytes as variables. Existing typed Dataset/Storage APIs remain authoritative for typed tables.

`scientificIoDescribeDataset dataset_id` returns identity, format, contract, policy, content SHA and availability. Offline media leave identity/metadata intact. `scientificIoReadDataset dataset_id offset count` reads at most 1 MiB after descriptor-relative source validation and full expected-SHA verification; changed sources are refused. Full verification is intentional for static immutable references, unlike lightweight provisional live observations. A disconnected source returns explicit unavailable status. Existing unrelated trusted legacy consumers have not been silently migrated into this facade.

## Export and shared namespaces

`scientificIoExportDataset scope producer dataset_id filename` requires an explicit export grant and a safe single leaf name. CORE verifies canonical source bytes and publishes through existing File Publication with CREATE-only behavior. Existing destinations are never overwritten by this facade. The public receipt omits physical destination paths.

Script Bridge provides `capabilities`, `browse`, `import`, `describe`, `read`, `export`. It binds producer identity to the actual executing module, rather than accepting a caller-supplied owner. Host-only grants cannot be minted by the client.

`::GX::datasetNamespaceAuthorizeSharedInput session namespace producers` is a user/admin-only addition to `DATASET_NAMESPACE_API_v1`. Grants live in the **existing Session Manifest** beside namespace definitions. Authorized producers may explicitly request that namespace when creating a new Dataset through ordinary Publication APIs. Existing IDs, foreign content, overwrite and producer deletion/mutation rights are not granted. Private `module/<id>` and pending namespaces cannot be shared; namespace spelling alone never grants access. Standard publication without an explicit shared destination retains its prior private module namespace. Revocation is an empty authorized producer list. Existing namespace moves remain user/admin operations.

## Boundary and future providers

The implemented transport is local descriptor-relative storage. Capabilities disclose copy/reference/read/browse support and unavailable remote backends. Future location providers can retain the same logical identity and codec contracts, but no SSH/cloud/remote scheduler implementation is included. Tokens and API checks do not sandbox arbitrary hostile code running under the same OS user. Scientific Viewers following this contract receive identities, typed descriptors or bounded bytes rather than direct filesystem authority.
