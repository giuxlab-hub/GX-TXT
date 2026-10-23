# GX-TXT dev111-r3 — DEV111-P002

**Verified and approved by the GX-TXT project owner.** This is the second sequential maintenance patch and requires DEV111-P001 first.

Changes Configuration by adding Acquisition and Preview Components tabs, registered scientific preview providers, metadata and table/curve/native-plane/raster-overlay presentation, source-bound cache invalidation, and a bounded fixed native worker. The existing Session and scientific Dataset owners remain authoritative.

Compatibility: original dev111-r3 main commit 4daf135e49378eff1f413310bc17cf32f1928c44, plus P001 maintenance commit 5c9d72b4a30e3d464bd263fbf3a3a072c651bbe0. Six predecessor hash guards, one native engine guard and all 18 changed/new file conditions were matched.

The addon gxpreviewprovider.so is a verified ELF64 x86_64 library; requires Linux x86_64, Tcl 8.6 and Python 3. The original installer and all scientific payload bytes are retained unchanged. See APPLY.md for exact sequential application and rollback.

Original sealed package DEV111-P002.zip SHA-256: 65a4d7d33ec4d2defbd8c81a2240aecdc89dc4bd2f710a5954e4b4f437ad6cfe (749433 bytes). The separately checksummed GitHub distribution ZIP intentionally omits private upstream QA recordings and machine paths, while retaining the original manifest, installer, changed files and rollback preimages byte-identically.

The project owner completed functional verification. The publishing process independently verified the source SHA-256 chain and packaging. Official main and historical maintenance releases remain unchanged.
