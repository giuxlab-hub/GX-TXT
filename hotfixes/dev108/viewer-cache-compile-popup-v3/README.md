# GX-TXT dev108 — Restricted C++ Viewer compile-cache and GUI notice (v3)

## Scope

Standalone backport to the **exact public GX-TXT `0.9.8.10-dev-108`** tree on GitHub, commit `6371001a219a4e611ce89c8b396c62294e6b979c`. The private dev109 tree is not read or changed.

Changes only these two framework files:

- `core/python/gxtxt_viewer_development.py`
- `core/tcl/viewer_development_api_v1.tcl`

The installer checks their **original Git blob SHA-1 hashes** before any changes. It refuses patches v1/v2, unknown modifications, or a non-dev108 version; it is meant for an unmodified copy of public dev108.

## Behavior

1. Before each restricted C++ Viewer event, the backend looks for a binary matching the current source, design, project metadata, SDK, native adapter, policy, compiler, toolchain manifest, Python backend and policy implementation. It verifies the actual binary SHA-256. If the cache matches, `viewer.so` is reused.
2. If the cache is absent or stale, the original Clang compilation flow runs. Only **when this compilation path begins**, the backend creates a uniquely named temporary marker for that GUI event inside its project `derived/tmp`.
3. The Viewer Tcl/Tk host checks only its own marker. When found, it opens a **nonmodal** little window: `Compilazione C++ del viewer in corso...`. It automatically dismisses the notice when the associated event completes, errors or the Viewer closes.
4. After a successful native event, the Viewer status line displays either **`COMPLETED (C++ compiled)`** or **`COMPLETED (C++ binary reused)`**. This gives a visible result even when compilation is so fast that the transient notice is not observed.
5. Source/toolchain changes invalidate the cache. Explicit Build/Export and debugger builds remain on their original paths and are not served from this event cache.

**No changes** to `scriptJobAsync`, Script Job stdout/stderr handling, Python or Octave execution, generic Tcl pipelines, or other Viewers. The diagnostic uses a **project-local marker file**, not terminal streams. There is no `/dev/tty` dependency.

## Installation on the independent Debian machine

Close GX-TXT first. Extract the ZIP outside the framework directory, then run the following **from the extracted patch directory**:

```bash
ROOT="$HOME/gxtxt/gxtxt_pipeline_v09810dev_108"
python3 backport.py --check "$ROOT"
python3 backport.py --apply "$ROOT"
```

Both commands validate *both* files against their public Git blobs; `--check` does not modify them. `--apply` copies the two original files into `<ROOT>/.gxtxt_patch_backups/...`, checks the backups, updates each source with atomic rename, and verifies their final SHA-256. On an application exception it attempts to restore the original files. No data/workspaces/plugins are removed.

Restart GX-TXT, open a restricted C++ Viewer and use the same action two or more times:

- First run for that project: expect a brief compilation notice, followed by `COMPLETED (C++ compiled)`.
- Later runs for that **same unchanged project**: no compilation notice and `COMPLETED (C++ binary reused)`.
- A reopened installed Viewer might use a newly created temporary runtime project, so **its first use may legitimately compile again**. This patch does not share binary outputs between different projects.

No command-line test procedure is required to observe the change.

## Rollback

Follow the **exact `ROLLBACK:` command printed by `--apply`**, with this patch's saved backup directory:

```bash
python3 backport.py "$ROOT" --rollback "$ROOT/.gxtxt_patch_backups/<v3-backup-directory>"
```

Rollback restores both files only if both still match their installed patch checksums. It refuses to overwrite any later local edits. The backup is retained.

## Offline verification and limitations

```bash
python3 -m unittest -v test_patch
```

The included tests cover strict source guards, install and rollback, cache hit and invalidation, marker isolation from stdout/stderr, and Tcl notice lifetime. The Tk notice has also been exercised under Xvfb with a real Tk interpreter (`TCL_TK_INTEGRATION_PASS`). These are **not a full integration test with the actual GX-TXT app and Clang on the target Debian system**; that still requires opening the GUI on the test machine.

Licensed GNU GPL-3.0-or-later. Text and inline source comments are in English, in line with project conventions; the on-screen notification is in Italian for this test patch.
