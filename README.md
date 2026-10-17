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
