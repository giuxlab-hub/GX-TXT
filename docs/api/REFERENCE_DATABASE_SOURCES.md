# Scientific reference sources (audit 2026-09-24)

GX-TXT's reference libraries are outside Sessions. The source files below are retained separately from their converted `.gxsrl` libraries. A reference trace is a candidate for comparison, not proof of compound identity.

| Source | Official record | Acquired source and integrity | Installed library |
|---|---|---|---|
| TUM RefIMP reference µFTIR | https://mediatum.ub.tum.de/1656656 | `FTIR_MP_references.csv`, SHA-256 `3ec55d86481da93b73f5f9f46e0c6d7c3d941165fd45beefeb84fb1305a0d19c` | `tum.refimp.ftir.2022`, 15 spectra, 15 materials, 637 samples each; library content hash `325e3ef8a4e5447ccaf03594c4d5596b35e1ca87691f7ba9964cc44d8ec9b571` |
| TUM RefIMP training/test µFTIR | https://mediatum.ub.tum.de/1656656 | `FTIR_MP_train_test_spectra.csv`, SHA-256 `569050ddf6cfed952fdaabe6e2020522b643510cf1e00cf27265f4cd3783711a` | `tum.refimp.ftir.training.2022`, 9,537 labeled traces, 15 material classes, 637 samples each; content hash `21e511f0a3c2f4fbe196c418c4a5f56cbc5b18c9029614212009d3b422340a8b` |
| OpenSpecy package example / PNNL-IARPA nitrocellulose | https://github.com/wincowgerDEV/OpenSpecy-package | Original `fitr_nitrocellulose.jdx`, local preserved copy `openspecy_nitrocellulose.jdx`, SHA-256 `5dc366d7a86ac372a5328c33d94f87f210aee456cef6feed369ccec72379b1bf` | `openspecy.example.nitrocellulose.2017`, one reflectance IR spectrum, 7,154 samples; content hash `e6855f02624ca3f03176a82cfdf95c9c779d512c17b542d015229a7ba830512e` |

Both files were retrieved 2026-09-24 from the TUM official rsync endpoint and are CC-BY-SA-4.0. Cite Weisser, Jana and Pohl, Teresa, RefIMP, Technical University of Munich, mediaTUM 1656656; retain the license and source URL when sharing an adapted library. The TUM record describes transmission µFTIR, ~3700–1250 cm⁻¹, resolution 8 cm⁻¹; the ordinate's absolute calibration is not documented, so GX-TXT retains it as `relative_transmission_signal` and never silently converts it to absorbance or percent transmittance.

The training/test traces are separately labeled. They are not independently validated chemical-identification references; using them as matching candidates may create correlated or duplicate hits. The 15 curated reference traces are the default scientifically cleaner comparison set.

The one OpenSpecy package example is a distinct local library, not the bulk OSF database. Its own JCAMP header says `OWNER=Public domain`, `ORIGIN=Pacific Northwest National Laboratory Under IARPA Contract`, and `DATE=March 2017`. No rights conclusion about other OpenSpecy/OSF records follows from this item. NIST WebBook water JCAMP was obtained as a parser test only, not bundled or bulk mirrored. See `REFERENCE_DATABASE_LICENSES.md`.
