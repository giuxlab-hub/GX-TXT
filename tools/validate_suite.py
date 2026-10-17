#!/usr/bin/env python3
"""GX-TXT dev-102: verify byte-identical public tests or opt in to one isolated run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CASES = ROOT / "validation" / "official_dev102"
CLI = {
    "core_contracts": "CORE publication and metadata provenance",
    "legacy_publication": "Legacy Replicate scientific publication",
    "metadata_bridge": "Metadata provenance and Script Bridge",
    "replicate_contracts": "Replicate scientific Jobs and atomic output",
    "replicate_xy": "Replicate XY topology and statistics",
    "worksheet_contracts": "Scientific Worksheet typed model",
    "automation_contracts": "Worksheet scripts and Filter Views",
}
MANUAL = {
    "native_paths": "Requires compatible Native2D binary",
    "metadata_acquisition": "Requires synthetic PNG input",
    "replicate_bridges": "Requires controlled earlier Session",
    "replicate_equivalence": "Requires prior Session and independent golden result",
    "deposited_gui": "Requires X11 and retained Session",
    "grid_benchmark_gui": "Requires X11, native grid, xdotool and row-count inputs",
    "preview_gui": "Requires X11, prior Session and source Dataset",
    "replicate_gui": "Requires X11 and prior study",
    "replicate_xy_gui": "Requires X11 and prior XY study",
    "selectors_gui": "Requires X11 and xdotool",
    "worksheet_gui": "Requires X11 and native Worksheet",
    "worksheet_workflows_gui": "Requires X11 and prepared scientific inputs",
}
BANNED = ("document_extraction_teacher", "middlebrook_loop_gain",
          "climate_tables.pdf", "/home/giu/", "H:\\", "D:\\",
          "BEGIN PRIVATE KEY", "BEGIN OPENSSH PRIVATE KEY")
RELEASE = "0.9.8.10-dev-102"
MAIN_SHA = "93d326af356ce1bc9237e93d0ebff8c0f87f75ee"

def verify(announce=True):
    info = json.loads((ROOT / "source-manifest.json").read_text(encoding="utf-8"))
    assert info["schema"] == "gxtxt.public-validation-sources/1"
    assert info["referenceFramework"] == RELEASE
    assert info["referenceMainCommit"] == MAIN_SHA
    assert info["officialArchiveSha256"] == "48630fae9171721ee164d390a0139b5dbaabc1a70dcb059b0a0338c690abdded"
    originals = info["copiedFiles"]
    if len(originals) != 22 or info["totalCases"] != 19 or info["totalHelpers"] != 3:
        raise ValueError("Expected 19 original Tcl cases and three helpers")
    seen = set()
    for item in originals:
        rel = Path(item["path"])
        if rel.is_absolute() or ".." in rel.parts or rel.as_posix() in seen:
            raise ValueError("Unsafe or duplicated source path: " + str(rel))
        seen.add(rel.as_posix())
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Missing/non-regular test file: " + str(rel))
        raw = candidate.read_bytes()
        if len(raw) != item["bytes"] or hashlib.sha256(raw).hexdigest() != item["sha256"]:
            raise ValueError("Original scientific test checksum mismatch: " + str(rel))
        text = raw.decode("utf-8").lower()
        if any(secret.lower() in text for secret in BANNED):
            raise ValueError("Private/host-specific source reference detected: " + str(rel))
    for case in set(CLI) | set(MANUAL):
        if f"validation/official_dev102/{case}.tcl" not in seen:
            raise ValueError("Missing declared case: " + case)
    for candidate in (ROOT / "validation").rglob("*"):
        if candidate.is_symlink():
            raise ValueError("Unexpected symlink: " + str(candidate))
        if candidate.is_file() and candidate.relative_to(ROOT).as_posix() not in seen:
            raise ValueError("Unreviewed file inside validation tree: " + str(candidate))
    if not (ROOT / "LICENSE").is_file():
        raise ValueError("GPL license missing")
    if announce:
        print("PASS: 22 byte-identical files, 19 dev-102 scientific cases, 3 shared helpers.")
        print("PASS: reviewed public inputs only, no private test PDFs or deployment scripts.")
        print("Runtime scientific/GUI tests: NOT RUN by source verification.")
    return info

def list_cases():
    verify(False)
    for name, description in CLI.items():
        print("opt-in CLI | {:27} | {}".format(name, description))
    for name, description in MANUAL.items():
        print("manual     | {:27} | {}".format(name, description))

def run_one(args):
    verify(False)
    if not args.execute:
        raise ValueError("Real scientific test execution requires --execute")
    if os.name != "posix":
        raise ValueError("This controlled CLI test runner supports Linux only")
    if not args.framework:
        raise ValueError("Supply an independently extracted dev-102 test framework")
    framework = Path(args.framework).expanduser().resolve(strict=True)
    if not framework.is_dir():
        raise ValueError("Framework path is not a directory")
    version = framework / "VERSION.txt"
    if not version.is_file() or version.read_text(encoding="utf-8").strip() != RELEASE:
        raise ValueError("Requires the exact dev-102 source release")
    if not (framework / "gxtxt_pipeline.tcl").is_file():
        raise ValueError("Missing framework Tcl/Tk entrypoint")
    name = framework.as_posix().lower()
    if "/script-ag/current" in name or "/ag-script/current" in name or "/public_git_stage" in name:
        raise ValueError("Refusing the active installation or a source publishing checkout")
    tclsh = shutil.which(args.tclsh)
    if not tclsh:
        raise ValueError("Tcl executable unavailable: " + args.tclsh)
    work = Path(tempfile.mkdtemp(prefix="gxtxt-validation-dev102-" + args.case + "-"))
    output = work / "case-output"  # Must not exist when the official test starts.
    env = os.environ.copy()
    keys = ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
            "GXTXT_INSTALLATION_ROOT", "GXTXT_RESOURCE_ROOT", "GXTXT_RESOURCE_STORAGE",
            "GXTXT_JOB_ROOT")
    for key in keys:
        env[key] = str(work / key)
    env["HOME"] = str(work / "home")
    env["TMPDIR"] = str(work / "tmp")
    (work / "home").mkdir()
    (work / "tmp").mkdir()
    command = [tclsh, str(CASES / (args.case + ".tcl")), str(framework), str(output)]
    print("Scratch: " + str(work), flush=True)
    print("Executing real scientific Tcl code; this is not an OS sandbox.", flush=True)
    status = "UNKNOWN"
    try:
        with (work / "execution.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=work, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=args.timeout,
                                    stdin=subprocess.DEVNULL, check=False)
        code = result.returncode
        status = "PASS" if code == 0 else "FAIL"
    except subprocess.TimeoutExpired:
        code, status = 124, "TIMEOUT"
    report = {"release": RELEASE, "case": args.case, "status": status,
              "exit_code": code, "output": str(work),
              "test_sha256": hashlib.sha256((CASES / (args.case + ".tcl")).read_bytes()).hexdigest(),
              "scope": "One explicit local test, not general platform certification"}
    (work / "run-summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    print("Complete stdout/stderr: " + str(work / "execution.log"))
    return code

def main():
    parser = argparse.ArgumentParser(description="GX-TXT dev-102 public validation")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("verify", help="Only check exact source SHA-256 files, do not execute tests")
    sub.add_parser("list", help="List cases, prerequisites and the run policy")
    run = sub.add_parser("run", help="Run ONE reviewed case in a new Linux temporary directory")
    run.add_argument("case", choices=sorted(CLI))
    run.add_argument("--framework", required=True, help="Extracted independent dev-102 framework directory")
    run.add_argument("--tclsh", default="tclsh")
    run.add_argument("--timeout", type=int, default=900)
    run.add_argument("--execute", action="store_true", help="Required for actual scientific processes")
    options = parser.parse_args()
    try:
        if options.action == "verify":
            verify()
        elif options.action == "list":
            list_cases()
        else:
            if not 10 <= options.timeout <= 3600:
                raise ValueError("Timeout must be 10–3600 seconds")
            return run_one(options)
    except (ValueError, AssertionError, OSError, UnicodeError) as e:
        print("VALIDATION ERROR: " + str(e), file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
