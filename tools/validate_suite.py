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

    additional = json.loads((ROOT / "source-manifest-dev103.json").read_text(encoding="utf-8"))
    if (additional.get("schema") != "gxtxt.public-validation-sources/2"
            or additional.get("referenceFramework") != "0.9.8.10-dev-103"
            or additional.get("referenceMainCommit") != "e07376e0a62e0eecf1737da33c87bbbb41273f4b"
            or additional.get("officialArchiveSha256") != "c13ff6b8170eb76efa4fb724137238646efc7766a752862fc7f8ddbe2aa85745"
            or additional.get("selectedCount") != 11
            or not additional.get("sourceOnly")
            or additional.get("runnerStatus") != "NOT RUN"):
        raise ValueError("Unrecognized or unverified dev-103 source-only suite")
    newer = set()
    if len(additional["files"]) != 11:
        raise ValueError("Dev-103 manifest does not contain exactly 11 reviewed scripts")
    for entry in additional["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts or name in newer or name in seen
                or not name.startswith("validation/official_dev103/")
                or rel.suffix.lower() not in (".tcl", ".py")):
            raise ValueError("Unexpected dev-103 source path: " + name)
        source = ROOT / rel
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-103 source: " + name)
        original = source.read_bytes()
        if (len(original) != entry["bytes"]
                or hashlib.sha256(original).hexdigest() != entry["sha256"]
                or any(token.lower() in original.decode("utf-8").lower() for token in BANNED)):
            raise ValueError("Unverified dev-103 scientific source: " + name)
        newer.add(name)

    newest = json.loads((ROOT / "source-manifest-dev104.json").read_text(encoding="utf-8"))
    if (newest.get("schema") != "gxtxt.public-validation-sources/3"
            or newest.get("referenceFramework") != "0.9.8.10-dev-104"
            or newest.get("referenceMainCommit") != "d99268348aa55b62f3a1e21ec3672f04504a740d"
            or newest.get("officialArchiveSha256") != "ee07751380454c226003efa0edb4cbbe2d002ea2424c6ef893ed6982af14726b"
            or newest.get("selectedCount") != 16
            or newest.get("sourceOnly") is not True
            or newest.get("runnerStatus") != "NOT RUN"
            or len(newest.get("files", [])) != 16):
        raise ValueError("Unrecognized dev-104 source-only validation inventory")
    recent = set()
    for entry in newest["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts or name in seen or name in newer
                or name in recent or not name.startswith("validation/official_dev104/")
                or rel.suffix.lower() not in (".tcl", ".py")):
            raise ValueError("Unexpected dev-104 validation source path: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Dev-104 scientific test file absent: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)):
            raise ValueError("Dev-104 test differs from accepted scientific source: " + name)
        recent.add(name)

    for candidate in (ROOT / "validation").rglob("*"):
        if candidate.is_symlink():
            raise ValueError("Unexpected symlink: " + str(candidate))
        if candidate.is_file() and candidate.relative_to(ROOT).as_posix() not in (seen | newer | recent):
            raise ValueError("Unreviewed file inside validation tree: " + str(candidate))
    if not (ROOT / "LICENSE").is_file():
        raise ValueError("GPL license missing")
    if announce:
        print("PASS: 49 verified original files: 19 dev-102 tests, 3 helpers, 11 dev-103 tests and 16 dev-104 tests.")
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
