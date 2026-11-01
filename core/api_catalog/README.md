# Native API Catalog index schema3

This C++17 Tcl extension stores the installed declaration snapshot in SQLite.
It stores metadata only. A catalog record neither invokes nor authorizes a host,
Script Bridge or restricted C++ SDK operation. Existing service owners supply
and validate those declarations.

The GUI loads the supplied `libgxtxt_api_catalog.so`; it never runs a compiler.
Maintainers can reproduce the Linux binary using an isolated build directory:

```sh
cmake -S core/api_catalog -B /absolute/new/build-directory -DCMAKE_BUILD_TYPE=Release
cmake --build /absolute/new/build-directory --parallel 2
```

Dependencies are Tcl 8.6 development files, SQLite3 and OpenSSL Crypto. Build
outputs stay in the explicit build directory. These commands neither install nor
activate the framework. Linux builds enable RELRO and immediate symbol binding.
The distributed binary is built from the adjacent source and links the existing
system Tcl, SQLite and OpenSSL runtimes.

Load with `load PATH Gxtxt_api_catalog`. The package is `gxtxt_api_catalog 1.1`
and its command is `::GX::apiCatalogNative`:

| Command | Result |
| --- | --- |
| `open DATABASE FRAMEWORK_ID` / `open_readonly DATABASE FRAMEWORK_ID` | Interpreter-local opaque handle. Parent directory must already exist. |
| `close HANDLE` | Closes this handle; interpreter destruction closes all remaining handles. |
| `validate HANDLE` | Native integrity and normalized-relation validation; returns status plus integrity. |
| `status HANDLE` | Dictionary with `schema`, `schema_version`, `framework_id`, `root`, `fingerprint`, `generation`, `count`, `native_package_version`. |
| `summary HANDLE` | Bounded `surfaces`/`providers` count dictionaries, total `count`, fingerprint and generation from one read transaction. No declaration payloads are fetched. |
| `reconcile HANDLE FINGERPRINT RECORDS` | Validates the complete input, then atomically replaces the snapshot when the fingerprint differs. Returns status plus boolean `changed`. |
| `query HANDLE FILTERS` | Dictionary with `rows`, `total`, `offset`, `limit`, `generation`, `fingerprint`. Count and page share one SQLite read snapshot. |
| `get HANDLE RECORD_ID` | Exact record dictionary, or typed `MISSING` error. |
| `file_digest PATH` | Exact binary SHA256, bounded to64MiB. |
| `digest TEXT` | SHA256 hex of the exact Tcl UTF-8 representation, bounded to 64 MiB. |
| `fingerprint PATH_LIST ?ROOT?` | SHA256 over ordered normalized paths (relative to optional ROOT), length-delimited existence/size markers and exact file bytes. |

Records require exactly nine fields: `id`, `api_id`, `provider_id`, `surface`,
`language`, `version`, `title`, `summary`, `payload`. `payload` is a Tcl dictionary
retained byte-for-byte in its original Tcl string representation. Surfaces are
`family` (internal complete snapshot), `host`, `script_bridge`, `cpp_sdk`.
Languages are `all`, `Python`, `Octave`, `Cpp`. `all` records qualify for any
language filter; callers choose the intended surfaces independently.

Filters accept only `surface`, `language`, `query`, `api_id`, `provider_id`,
`source_ref`, `source_sha256`, `offset`, `limit`. Source predicates match exact
indexed source membership (including aggregate families). Empty surface means all surfaces; a single name or list of up
to four names restricts them. Empty or `all` language means all languages. API
and provider filters match exact identities. Search is literal substring search
over API/title/summary/payload, with SQLite's ASCII case folding; `%`, `_`, quotes
and SQL fragments remain literal text. Pagination is stable by
`api_id,provider_id,surface,id`. Offset defaults to 0, limit to 100.

The facade owns the per-user cache path and reconciliation scheduling. Native
operations do not spawn processes, read scientific data, modify Sessions or
write product sources. Fingerprints include content changes even when file size
and modification time stay unchanged. Absent files have explicit markers, so
addition and removal change identity. A file changing size while read fails the
fingerprint instead of publishing a partial identity; the facade can retry later.

Limits: 50,000 records and 64 MiB input per reconciliation; 1 MiB payload per
record; 65,536-byte summary and 4,096-byte title; 1,024-byte other scalar fields;
256-character search; 1..1,000 rows/page and 16 MiB response. Fingerprinting
accepts at most 10,000 paths, 16 MiB/file, 256 MiB combined content. All SQL values
use prepared statement bindings. WAL and a 100 ms SQLite busy timeout permit
concurrent readers and prevent unbounded database-lock waits. Failed replacement
rolls back to the previous fingerprint, generation and rows.

The database uses both SQLite `application_id` (`GXAC`) and `user_version`, and binds
the database to the exact framework identity. Future/foreign schemas, identity
mismatches and corruption are reported; native code never deletes a database.
The facade reports installed-seed failure and preserves the previous user cache; a staged candidate is validated before the process handle changes.
Errors have `-errorcode {GX API_CATALOG REASON}`, including `INVALID`, `HANDLE`,
`MISSING`, `BUSY`, `CORRUPT`, `SCHEMA`, `IDENTITY`, `RESPONSE_LIMIT`, `FINGERPRINT`,
`DIGEST`, `SQLITE`, `CONSTRAINT`, `MEMORY`, `INTERNAL`. No Tcl SafeInit entrypoint
is exported: this is a trusted host component, not an author sandbox facility.

Schema version3 includes normalized `declaration_sources`, `operation_visibility` and
`operation_arguments` and `catalog_source_members` tables, including provider version/source hashes,
documentation availability, explicit independent Python/Octave flags and ordered
typed arguments/result contracts. `records.payload` is bounded presentation data,
not the only contract representation. The public Tcl facade and maintenance
procedure are documented in `docs/api/API_CATALOG_SERVICE_API_v1.md`.

The distribution ships `catalog.sqlite` and `source_manifest.json`. Build them
with `python3 -B core/python/gxtxt_api_catalog.py build FRAMEWORK NEW_STAGE` after
all packaged sources and module manifests settle. Only this packaging command
uses trusted registered metadata imports. Normal `stage` uses inert parsing and
never imports plugin sources or starts Tcl CORE. Runtime snapshots are per user
and immutable for the process lifetime. Framework Maintenance calls the public
facade Refresh/Reconcile operation only in its API Catalog section.

Normalized argument requiredness uses1(required),0(optional),-1(undeclared).
Order/defaults come only from authoritative signatures/explicit parameter fields;
`default_known` distinguishes an explicit empty default from an unknown default.

Families are non-executable aggregate references. `source_kind` labels them and
`catalog_source_members` retains every declaring host, binding and SDK source;
a representative display ref/hash never replaces multi-source membership.
Packaged seeds use DELETE journal mode; private mutable snapshots alone use WAL.
