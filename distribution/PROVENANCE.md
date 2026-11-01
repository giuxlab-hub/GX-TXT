# Source and qualification

The sole functional source baseline is independently accepted DEV111-P035 commit
`ce34988db2c7500b60f7235b237b2fdb67e5d434`.
Its canonical patch archive SHA-256 is
`8848e8e3f7ada48d7d2b8b34780a398dc83a8829424f64e2dc63c60487b2447d`.

DEV112 changes the distribution identity to `0.9.8.10-dev-112` and baseline
patch level to `000`, restores the already reconciled post-P035 TODO from
administrative commit `ffdf74584eff426a4ca39701a3ae404c7b99d595`, and adds
packaging/installation documentation and adapters. Existing CORE APIs, scientific
algorithms, binaries and activation/lifecycle rules remain byte-identical to P035.
The owner additionally requires core=1 in the descriptors of gxtxt.ir_identify,
gxtxt.ir_waveform and model.spice_build_validate; waveform's checksum updates only
that descriptor entry. The Analysis API demo receives its standard package
manifest; the geospatial demo includes its already-declared original published
example ZIP. No scientific/runtime source is altered. The pipeline's version
literal is the only changed existing Tcl line.
The new source commit and complete admitted file mapping are recorded in the
generated release manifests.

The source TODO SHA-256 remains
`af36ec62f5f699c551b532d698980955e762585e6c0867d4a4220934fc2772fb`.
No genuinely unfinished scientific item was removed for this consolidation.

Owner originals, preserved without rebuilding or repackaging:

| Original archive | SHA-256 |
|---|---|
| `viewer.curve_digitizer_2.0.26_dev111_p032_standalone.zip` | `ded07ad9a85c79f68fa53866edef9a4a186ef06546882940526b56d9894a1198` |
| `preview.curve_digitizer_0.1.12_dev111_p032_REQUIRES_CORE_BRIDGE_022.zip` | `57a0ae932bef79c64d597299581f7319ed30548bc0c2a7846bcace34c436c5b2` |

Qualification: `OWNER_SUPPLIED_UNMODIFIED; NOT_TESTED_BY_OWNER_REQUEST`.
Only the expressly authorized distribution installation/registration/lifecycle
checks are new; scientific, module-functional and full GUI suites are not rerun.

Previously accepted P035 functional/scientific/GUI evidence is reused, including
its limits and `REAL_UNVERIFIED` cases. Compact original P035 handoff/acceptance
records accompany the distribution; they are not new DEV112 test results.

## Reproducible packaging

The registered `validation/dev112_release/build.py` tool accepts an exact clean
source commit descended from P035, a repository, and a fresh scratch output
directory. It reads tracked Git objects, verifies the permitted source delta,
preserves module payloads, creates deterministic containers only where original
matching ZIPs are unavailable, and writes the complete file/package manifests
and deterministic framework and separate-demo archives. All 149 non-demo modules
are already expanded. A fresh preparation invokes the unchanged Plugin Install
API for 49 independent non-demo modules; its exact resulting registry is frozen
as an immutable, checksummed build input with actual transaction evidence. It is
not a development registry and its rows/timestamps are never manufactured or
edited. Reproducibility uses the exact source plus that same frozen input.
Original package inputs and their checksums are
listed in the generated metadata. The final release verification records the
two independently checked builds and their archive identity.

The final archive checksums are supplied externally to avoid a self-referential
manifest. File manifests exclude themselves. Personal Configuration, installation
identity, logs and caches are excluded. The sole admitted registry input is the
proven, frozen clean release-preparation result; normal later plugin operations
create local mutable state through the existing API. Only DEMOs use an end-user
installer, supplied separately from the ready framework.
