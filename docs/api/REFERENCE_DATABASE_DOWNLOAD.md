# Reproducing the RefIMP acquisition

Official record and metadata: https://mediatum.ub.tum.de/1656656 . The record publishes the rsync endpoint and its read-only password. On Debian:

```sh
RSYNC_PASSWORD=m1656656 rsync -av rsync://m1656656@dataserv.ub.tum.de/m1656656/FTIR_MP_references.csv SOURCE_DOWNLOADS/
RSYNC_PASSWORD=m1656656 rsync -av rsync://m1656656@dataserv.ub.tum.de/m1656656/FTIR_MP_train_test_spectra.csv SOURCE_DOWNLOADS/
sha256sum SOURCE_DOWNLOADS/FTIR_MP_references.csv SOURCE_DOWNLOADS/FTIR_MP_train_test_spectra.csv
```

For the 2022 files, compare hashes in `REFERENCE_DATABASE_SOURCES.md`. Do not substitute changed upstream bytes without reviewing the new release, rights, fields and scientific semantics. Preserve originals read-only outside the framework release tree, alongside retrieval date and hashes. The 5.3 GB RefIMP image is not needed for 1-D reference matching and was not acquired.

After a fresh, tested GX-TXT CORE staging install, run the cataloged adapters with **new output paths**:

```sh
tclsh install_refimp_library.tcl FRAMEWORK_ROOT SOURCE_DOWNLOADS/FTIR_MP_references.csv NEW_EXPORT/tum.refimp.ftir.2022.gxsrl.zip
python3 install_refimp_training.py FRAMEWORK_ROOT SOURCE_DOWNLOADS/FTIR_MP_train_test_spectra.csv NEW_EXPORT/tum.refimp.ftir.training.2022.gxsrl.zip
tclsh test_refimp_training.tcl FRAMEWORK_ROOT
```

The resulting SQLite libraries are user-owned under `$XDG_DATA_HOME/gxtxt_pipeline/scientific_reference_libraries` (or `$HOME/.local/share/...`); they are not Session contents. Both adapters refuse existing destinations and use source-hash guards. The portable `.gxsrl.zip` exports include integrity manifests and can be imported with `::GX::ReferenceLibraryAPIv1::importLibrary`. The core API validates library consistency and numerical payload hashes.

The separately tested OpenSpecy-package sample is not part of RefIMP and must never be treated as a license for an OSF bulk mirror. To reproduce its one-spectrum local library, obtain the original `fitr_nitrocellulose.jdx` from the OpenSpecy package, verify SHA-256 `5dc366d7a86ac372a5328c33d94f87f210aee456cef6feed369ccec72379b1bf`, then run the version-pinned `tools/reference_adapters/openspecy_example_2017/install_openspecy_example.tcl` against GX-TXT 0.9.7.89 or newer with a fresh output ZIP path. The adapter verifies the original hash and refuses an existing library/export. Re-audit any changed upstream bytes and rights before importing a replacement under a new ID.
