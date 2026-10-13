# Reference library update protocol

1. Check the official source record, release date, file list, rights and citation. For TUM, use https://mediatum.ub.tum.de/1656656 . Record a new retrieval date and SHA-256 for each original file. Never treat a changed file as the old 2022 version.
2. Download into a **new** `source_downloads/<source>/<version>/` directory. Preserve the original immutable; do not rewrite the current library.
3. Audit headers, coordinate and ordinate semantics, counts, classes, missing/non-finite values and potential duplicate identities. Update a version-pinned adapter and its hash guard. Build a **new** library ID/version in a staging user-data root.
4. Validate SQLite integrity, every numerical payload, source and content hashes, entity/spectrum counts, and sample round-trips through the public Tcl Spectrum API. Export and re-import the portable ZIP into another clean user-data root; compare content hashes.
5. Only after success, make the new library available to users and switch any chosen default. Keep the old known-good library and export for rollback. A failed download, conversion, validation or export must leave the old library intact. Never edit an installed library in place as an update strategy.
6. Update source/license/download documentation and attribution; mark any changed record classification. Do not acquire NIST/SDBS/OpenSpecy bulk data solely because an endpoint remains reachable.

The current 2022 RefIMP adapters refuse overwrite. This deliberately makes an update an explicit staged new-version operation. The analysis consumer must record exact library IDs, versions and content hashes so past results remain interpretable.

The audited, version-pinned RefIMP import adapters ship in `tools/reference_adapters/refimp_2022/`: `install_refimp_library.tcl` imports the 15 curated reference traces through public CORE APIs, and `install_refimp_training.py` imports the separately labeled 9,537 training/test traces transactionally. Each requires the documented original CSV hash and refuses an existing library or export ZIP. They do **not** update a future source version automatically; audit and adapt a new version under a new library ID using the protocol above.
