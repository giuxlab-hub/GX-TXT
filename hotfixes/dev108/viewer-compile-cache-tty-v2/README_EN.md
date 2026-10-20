# GX-TXT dev-108 Viewer compilation-cache / TTY hotfix (v2)

**Status:** Experimental maintenance hotfix; isolated tests PASS, Debian real-GUI acceptance pending.

**Only compatible with:** GX-TXT `0.9.8.10-dev-108`, original public main commit `6371001a219a4e611ce89c8b396c62294e6b979c`, target Git blob `5d77772e22ce6eb0befcdc3e32ac783c7d46fbb0`.

**Incompatible by design with:** dev-109, all subsequent dev revisions, other GX-TXT releases, and any modified or previously patched dev-108 source. No merge into `main` or `dev-109`.

## Symptom and proposed fix

In dev-108, the restricted C++ Viewer event path can repeatedly invoke validation and compile a new `viewer.so` even when the project is unchanged. This hotfix (v2) attempts to reuse a previously compiled, verified release binary when source, design, project metadata, SDK, policy, compiler, adapter, toolchain and backend fingerprints match. Source/build-environment changes invalidate that cache. Explicit Build/Export and debug builds are not cached.

Actual compiler invocations generate `COMPILE START` and `COMPILE OK`, `COMPILE FAILED`, or `COMPILE ERROR` messages. The implementation tries the worker's controlling terminal `/dev/tty`, without contaminating structured stdout/stderr. If unavailable, it appends to the bounded project-local `derived/viewer_compilation.log`. A cache hit emits no compile message. A fresh installed Viewer instance can legitimately cause an initial compilation.

## Download and checksum

Original user-supplied installer package: [GXTXT_dev108_viewer_compile_cache_TTY_patch_v2.zip](GXTXT_dev108_viewer_compile_cache_TTY_patch_v2.zip)

SHA-256: `4f90e0ed8b510e442a8d80db219e7abbe80ffd59098afa70e69cb4921fd89885`

The package contains `README.md`, `backport.py` and `test_patch.py`; it is **not** a ZIP of the entire GX-TXT framework. The sole framework source file affected is `core/python/gxtxt_viewer_development.py`. This maintenance branch also tracks the patched source for audit, but its already modified file is not a valid input to `backport.py --apply`.

## Install only on original dev-108 (Debian)

Close GX-TXT. Fully roll back any earlier hotfix v1 first. Extract the ZIP outside the framework installation and run:

```bash
ROOT="$HOME/gxtxt/gxtxt_pipeline_v09810dev_108"
python3 backport.py --check "$ROOT"
python3 -m unittest -v test_patch
python3 backport.py --apply "$ROOT"
```

The installer checks the exact version and Git blob before changing anything. It makes a verified private copy in `<ROOT>/.gxtxt_patch_backups/` and prints the exact rollback command. Do **not** bypass the checks or manually copy it onto dev-109.

After restart, open the same Viewer, repeat an unchanged event and compare actual Clang invocations. If console output is absent, inspect `derived/viewer_compilation.log` inside the relevant Viewer project. Opening a separate Viewer runtime project may compile once again.

## Rollback and support limits

Use the `ROLLBACK:` command produced by the installer. If any source edits occurred after installation, rollback refuses to overwrite them; resolve that conflict manually from the preserved backup.

Six standalone offline fixture tests passed on 2026-10-20, covering cache invalidation, backup/rollback, terminal/fallback logs and stdout/stderr isolation. **No live Debian GUI/Clang integration acceptance is claimed.** The fix is provisional; dev-109 will use an independent correction.

Security note: build receipts and binaries are in writable project-local files. Fingerprints detect accidental changes but do not cryptographically authenticate artifacts against a malicious project author. Treat the cache as a performance/stability optimization for trusted projects, not as authorization to execute untrusted native binaries. No account-wide hostile-code sandbox is claimed.

License: GNU GPL-3.0-or-later. Original archive and documentation are preserved without rewriting the supplied patch.