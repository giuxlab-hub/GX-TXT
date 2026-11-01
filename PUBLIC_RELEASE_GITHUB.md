# GX-TXT 0.9.8.10-dev-112-r2 — Public GitHub release

This branch holds the **original, unmodified public framework source tree** from the canonical DEV112-r2 framework archive:

`gxtxt_pipeline_dev112_public.tar.gz` — SHA-256 `8fda1fd6e485d9d917adfb08d64991c2403f8faf19ed10f4770565d8afcdbaa0`.

Every original framework file in this branch is preserved with its source bytes and UNIX mode. This note is the only additional file for GitHub distribution. The source tree contains the original `GX-TXT_REMAINING_WORK_TODO.md`, including remaining scientific limitations.

**Public release:** https://github.com/giuxlab-hub/GX-TXT/releases/tag/v0.9.8.10-dev-112-r2

## What is distributed

GX-TXT DEV112-r2 is a **complete standalone version**, not an incremental DEV111 patch. You do not need to replay DEV111-P001–P035 on it.

The public release provides the main `gxtxt` Debian package (Debian 13 / amd64), optional `gxtxt-demos`, `gxtxt-generators` and `gxtxt-compute-node` Debian packages, a self-contained graphical home-folder installer, the complete public framework archive, a reproducible installer/compute build-source Git bundle and the unchanged Curve Digitizer Viewer/Preview package ZIPs.

The base framework includes **149 non-demo modules**, with **15 optional Demo modules**; **39 public Generators** are available in the public generator package. **Five further private teaching Generators and five private Scientific Libraries are not part of this public release**.

## Installation

For Debian 13 amd64, use a graphical APT-capable package manager or install the local Debian packages using APT:

```sh
sudo apt install ./gxtxt_0.9.8.10~dev112-1_amd64.deb
sudo apt install ./gxtxt-demos_0.9.8.10~dev112-1_all.deb
sudo apt install ./gxtxt-generators_0.9.8.10~dev112-1_all.deb
```

The optional Compute Node service is separately installed from `gxtxt-compute-node_0.9.8.10~dev112r2-1_amd64.deb`. It requires explicit configuration and grants; a production listener must not be assumed to be active. The alternative graphical installer can install the complete public framework into a new folder without changing Debian packages.

For migration, keep the previous installation, Sessions, RAW, Configuration, personal libraries and archives intact. Do not overwrite a live DEV111 installation or open the same writable Session concurrently in both versions.

## Public-only distribution and source history

The public files have the exact hashes in the release `SHA256SUMS` and `PUBLIC_MANIFEST.json`. The original release includes source provenance:

- Accepted DEV111-P035 source `ce34988db2c7500b60f7235b237b2fdb67e5d434`.
- DEV112 framework consolidation source `8e637adff46306b5005297679166c09a1e9d36b8`.
- Installer/Compute source `f2bdfd20df261e3a34f3240c90873661ebcbe52a`.

**The `PRIVATE_OWNER_ONLY` directory and its contents have never been included in this GitHub branch or public release assets.** Do not publish private reference libraries, recovered NMR data, owner workkits, credentials or personal Sessions.

The original release documentation records focused packaging, Debian dependency, GUI installation and optional Compute Node checks, including explicit limitations. Publishing these artifacts does not add new scientific or GPU validation.

The source code is distributed under the license included in `LICENSE`. Consult individual third-party licenses and data rights where applicable.
