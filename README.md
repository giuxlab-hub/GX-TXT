# GX-TXT — public validation sources

This **independent Git branch** contains curated, reproducible validation scripts for [GX-TXT](https://github.com/giuxlab-hub/GX-TXT). It is deliberately separate from both the scientific source distribution on `main` and the presentation site on `gh-pages`.

The initial scope is **0.9.8.10-dev-102**. The scripts are copied **byte-for-byte** from the accepted official Debian release (SHA-256 and path provenance in [source-manifest.json](source-manifest.json)). They are not rewritten to invent success or retrofit later APIs into earlier tests.

## Included

- **19** original Tcl scientific/GUI validation cases in `validation/official_dev102/`.
- **3** original shared, dependency-providing Tcl helpers under `validation/official_dev099/` and `validation/official_dev100/`. These retain their original relative import locations.
- [TEST_MATRIX.md](TEST_MATRIX.md) describing expected inputs, runtime requirements and safe usage.
- `tools/validate_suite.py`, a local read-only hash check/list tool and an explicitly opt-in isolated runner for a small supported subset.

The scientific framework itself, modules, Session generator implementations and native libraries are **not duplicated** here. See [main source](https://github.com/giuxlab-hub/GX-TXT/tree/main) and its [three Session Generator libraries](https://github.com/giuxlab-hub/GX-TXT/tree/main/session_generator_libraries).

## Explicit exclusions

This branch does **not** contain any privately supplied document-extraction test generator, the two non-redistributable PDF fixtures, dependent test data, private scientific Sessions, acceptance receipts, development-work evidence, whole release bundles, user files or credentials. It does not include historical release deposit/installer/rollback scripts such as `release.py`; those are not safe public scientific test runners.

The official full dev-102 archive has many more internal validation files. This branch is a **selected public-source suite**, not a mirror of the archive. In particular, an upstream Debian acceptance report is not reproduced here as a new, independently verified result.

## Safe starting point

On any machine with Python 3, the following commands **inspect the public test source without executing GX-TXT, scientific Jobs, or writing Session data**:

```bash
python3 tools/validate_suite.py verify
python3 tools/validate_suite.py list
```

To actually execute an included **CLI-safe, synthetic-data case**, use an **isolated Debian test copy** of GX-TXT dev-102 and explicitly opt in:

```bash
python3 tools/validate_suite.py run core_contracts \
  --framework /path/to/immutable/gxtxt_pipeline_v09810dev_102 \
  --execute
```

This creates a fresh run directory under the operating system's temporary directory and redirects XDG, resource, Job and HOME directories into it. The test may invoke real Tcl/Python/Octave scientific services and create test Datasets there. The test directory is retained for inspection. **This is not an operating-system sandbox**: run only against a trusted, separate test framework installation. Do not use a live or mutable scientific Session or an active server deployment.

GUI, external fixture, native ABI, performance and multi-stage tests are shipped as historical **source-only** validation cases: their actual arguments, required Debian X11 dependencies (`xdotool`, ImageMagick `import`, suitable native builds) and prior controlled outputs must be prepared independently. They are **not** executed automatically by the runner. See [TEST_MATRIX.md](TEST_MATRIX.md).

## Versioning and interpretation

- Framework release: **0.9.8.10-dev-102**.
- Immutable public source commit: [`93d326af356ce1bc9237e93d0ebff8c0f87f75ee`](https://github.com/giuxlab-hub/GX-TXT/commit/93d326af356ce1bc9237e93d0ebff8c0f87f75ee).
- Official deposited archive SHA-256: `48630fae9171721ee164d390a0139b5dbaabc1a70dcb059b0a0338c690abdded`.
- License: **GNU GPL-3.0-or-later** (see [LICENSE](LICENSE)).

An older test intentionally bound to a particular release is not a general-purpose compatibility test. Generators should instead use applicable *public framework APIs*, not require one exact internal module implementation merely for generating a Session.

Scientific runtime testing on Windows, remote X11 and different GPU/ABI combinations has **not** been performed as part of publishing this branch. The original Debian test receipts remain outside this repository. Results and claims belong to the exact tested platform, input, version and scientific assumptions.

## Contributing future cases

Add new versions under their own `validation/official_devNNN/` directory; avoid changing previously published source files. Supply small redistributable synthetic fixtures and expected results with documented units, tolerances, provenance and science limitations. Review hard-coded paths, resource ownership, subprocesses, write/delete actions, credentials, license terms and private data before any publication. Update the source SHA-256 inventory and tests before committing to this branch. Keep the published `main` and `gh-pages` branches unchanged.

## Second suite: GX-TXT dev-103 (source-only)

The framework source commit [`e07376e0a62e0eecf1737da33c87bbbb41273f4b`](https://github.com/giuxlab-hub/GX-TXT/commit/e07376e0a62e0eecf1737da33c87bbbb41273f4b) adds remote scientific compute-node services, asynchronous Dataset Preview, a disposable verified Preview cache and Viewer catalog improvements. A **separate selection of 11 original source files** is now published at `validation/official_dev103/`; all 11 are SHA-256-identical to the officially accepted Debian archive. Consult [source-manifest-dev103.json](source-manifest-dev103.json) and the separate dev-103 section of [TEST_MATRIX.md](TEST_MATRIX.md).

Run `python3 tools/validate_suite.py verify` for a read-only consistency check of **both** dev-102 and dev-103 source manifests. The `list` and `run` subcommands remain intentionally limited to the original **dev-102** vetted CLI cases. The dev-103 cases are published as **source-only/manual**: they are not automatically executed by this branch and are not new proof of Debian/Windows/platform acceptance. The upstream dev-103 acceptance took place on Linux and includes a localhost mTLS compute-node campaign; no separate physical remote machine is asserted here.

Dev-103 materials deliberately exclude the private copied 2D21 scientific Session, remote-node certificates or account configuration, developer-source reviews, release activation/deposit/rollback and evidence scripts, and any privately supplied teaching-document PDFs/generators. Tests using remote/TLS dependencies require a separately provisioned isolated test node and synthetic inputs; never point them at a live computing service.

## GX-TXT dev-104 validation sources (NOT RERUN)

The [dev-104 source commit](https://github.com/giuxlab-hub/GX-TXT/commit/d99268348aa55b62f3a1e21ec3672f04504a740d) introduces Viewer Interface Builder, grouped Projects and scientific Print/PDF. We publish **16 original Tcl/Python validation cases and helpers**, SHA-256 identical to the official Debian archive, in `validation/official_dev104/` with [source-manifest-dev104.json](source-manifest-dev104.json).

These are **source-only**, not automatically run. `python3 tools/validate_suite.py verify` checks all three release inventories (dev-102, dev-103, dev-104). The explicit `run` command remains restricted to the seven previously reviewed dev-102 CLI cases. Dev-104 GUI tests require local X11; PDF checks require Poppler/qpdf; CUPS tests require a disposable fake backend. Their inclusion is not new runtime evidence or physical printer acceptance. See [TEST_MATRIX.md](TEST_MATRIX.md).

The branch contains no real user Session, private printer settings, credentials, confidential teaching PDFs, document-extraction test generator or scripts that deposit/activate the official framework.

## GX-TXT dev-106 validation sources (NOT RERUN)

The dev-106 public source commit (db10ef525670944f031bcb33b8d9968d6bcac312) follows dev-104 directly; dev-105 was skipped. This branch now includes 14 original Tcl/Python source-only tests and helpers from the official archive directory validation/integrated_dev106/, copied without modification to validation/official_dev106/. Original paths and SHA-256 hashes are in source-manifest-dev106.json.

The selected material covers document/source and XML contracts, managed debugger services, native document interfaces, Signal and Statistical APIs and GUI inspection workflows. Some tests require a prepared Debian/X11 workspace, compatible native libraries and synthetic scientific fixtures. **No dev-106 cases are executed automatically**; the opt-in runner remains restricted to reviewed dev-102 CLI cases. Source verification covers all published release manifests.

No private scientific Sessions, confidential test PDFs, dependent document-extraction generators, deployment scripts, internal acceptance evidence, credentials or original test outputs are included.

## GX-TXT dev-107 validation sources (NOT RERUN)

GX-TXT dev-107 (source commit 2e404977430906f6bc711239d5d934b72f0a6080) adds restricted C++ Viewer authoring, independent native display components and shared Script Workspace GUI controls. This branch includes 11 selected original source-only cases and helpers under validation/official_dev107/, copied byte-identically from the official validation/unified_dev107/ release directory. Their source identities and SHA-256 are in source-manifest-dev107.json.

These tests were not rerun during publication. The CLI runner still allows only the original reviewed dev-102 cases. GUI tests require prepared Debian X11 and native components. C++ policy tests and debugger interactions must be invoked only in controlled disposable environments.

The WordPress debugger guide package and its supporting tutorial directory are intentionally withheld, together with original acceptance evidence, private Sessions, developer files, sensitive teaching PDFs and any dependent generators.

## GX-TXT dev-108 validation sources (NOT RERUN)

The accepted dev-108 public source commit 6371001a219a4e611ce89c8b396c62294e6b979c adds Circuit Workbench and extends Numeric, Plot Dataset, native Viewer components, restricted C++ debugging and the shared Viewer GUI API. The validation branch includes **15 selected Tcl/Python source-only cases** under validation/official_dev108/, copied byte-identically from the official validation/dev108/ tree. Original source paths and SHA-256 checksums are in source-manifest-dev108.json.

These cases were not executed as part of public-source publication. GUI and numerical checks require dedicated Debian test installations, C++/Octave dependencies and synthetic fixtures. The opt-in runner remains limited to the originally reviewed dev-102 CLI cases.

Internal acceptance evidence, private Sessions, confidential PDFs and dependent generators, credentials and the separately withheld WordPress debugger package are not included.

## GX-TXT dev-109 scientific validation sources (NOT RERUN)

These 15 selected original Tcl cases are copied byte-for-byte from the official dev-109 archive, with source SHA-256 recorded in source-manifest-dev109.json. They cover grouped Modules, Session Generator registration, Dataset Preview and Curve Workbench coordinate/geometry behaviors. Scientific main source reference: 940b94c4cd3cbe4200f23f3eb5a04c9d836bd3f0.

**Publication does not execute these cases.** Their actual Debian display, scientific inputs and temporary Session fixtures are external prerequisites; previous validation suites and the original dev-102 opt-in runner remain unchanged. Internal developer/acceptance records, teaching PDFs, private Session data, version-specific dev-108 hotfix and credentials are excluded.

## GX-TXT dev-110 intermediate TASK210 source cases

The deposited dev-110 source is explicitly an intermediate TASK210 snapshot, not a final all-feature acceptance. Seven selected original Tcl/Python scientific-source cases are copied byte-identically into validation/official_dev110/, with exact SHA-256 and original archive paths in source-manifest-dev110.json. These cover bounded acquisition lifecycle, Print syntax, source-quality inspection, ScriptJob duplex and Session creation control contracts.

**Not executed:** this public branch does not assert Debian GUI/Clang/Octave runtime acceptance; no official_dev110 package ZIP series exists in the deposited source, and historical dev-108 hotfixes are incompatible by policy. The existing dev-102 controlled CLI runner remains unchanged.

## GX-TXT dev-111 (r3) — selected original validation sources

Seven source-only Tcl/Python cases copied byte-for-byte from the official deposited r3 revision. They concern document source capture, the shared icon catalog, paired-source readback, scientific video error handling, typed Script Bridge values and managed Job worker behavior. Exact original file paths and SHA-256 hashes are in source-manifest-dev111.json.

**No new tests were run by GitHub source publication.** Controlled scientific and native GUI fixtures remain necessary; case inclusion is not full Linux/Windows acceptance. Neither the historically version-bound dev-108 hotfix nor private user Sessions or confidential test generators are included.

## DEV111 r3 maintenance patch validation — P001 to P005

The branch includes seven exact-byte author Tcl test files for P001, P002, P003 and P004, under validation/official_dev111_patches, and a new independent validator for all five patches including corrected P005.

The original test cases have exact provenance and SHA-256 in patch-manifest-dev111.json. Their code is archived as SOURCE ONLY, without importing internal development evidence, installed Sessions or testing claims.

Read-only commands:

~~~sh
python3 tools/validate_suite.py verify
python3 tools/validate_dev111_patches.py
python3 tools/validate_dev111_patches.py --repository /path/to/GX-TXT-maintenance-checkout
python3 tools/validate_dev111_patches.py --installed-final /path/to/gxtxt
~~~

--repository requires an independent Git checkout with annotated dev111 P001/P002/P001-r2/P003/P004/P005 tags and the public patch ZIPs. It checks source history, predecessor commits, exact changed files, ZIP contents, correct native ELF64 Linux x86_64 binary, P005 CMake target and worker bootstrap, CORE fallback, and seven native scientific sources preserved across P005.

--installed-final only reads an existing final cumulative patched source and compares SHA-256; it does not launch a GUI, activate a provider, or write to the installation. Never confuse this with a new functional test.

The regular tools/validate_suite.py run command remains limited to the existing dev102 opt-in scientific fixture runner. The archived patch Tcl helpers require separate deliberate execution in suitable isolated Linux/Tcl/Tk environments. P005 did not deposit an independent portable end-to-end Tcl GUI test; its native functional test requires an admitted Preview provider and a controlled disposable scientific Session.

Two P003 SHA256SUMS.txt inventories differ from the author manifest because the public main source had already withheld internal documentation; the precise two SHA-256 reconciliations are declared in the patch manifest. No scientific source/binary changes are exempted.

The user-reported functional testing is separate from independent publication-source checks. No original private test receipts or credentials have been redistributed.
