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

    dev106 = json.loads((ROOT / "source-manifest-dev106.json").read_text(encoding="utf-8"))
    if (dev106.get("schema") != "gxtxt.public-validation-sources/4"
            or dev106.get("referenceFramework") != "0.9.8.10-dev-106"
            or dev106.get("referenceMainCommit") != "db10ef525670944f031bcb33b8d9968d6bcac312"
            or dev106.get("officialArchiveSha256") != "08a629e05d801279cddcf874a68c3c8b65b877a83cfd697d2847ec9e3fa45777"
            or dev106.get("selectedCount") != 14
            or dev106.get("sourceOnly") is not True
            or dev106.get("runnerStatus") != "NOT RUN"
            or len(dev106.get("files", [])) != 14):
        raise ValueError("Unrecognized dev-106 source-only validation inventory")
    recent106 = set()
    for entry in dev106["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106)
                or not name.startswith("validation/official_dev106/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/integrated_dev106/" + rel.name):
            raise ValueError("Invalid dev-106 test path/provenance: " + name)
        source = ROOT / rel
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-106 source-only file: " + name)
        raw = source.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)):
            raise ValueError("Unverified dev-106 scientific source: " + name)
        recent106.add(name)
    dev107 = json.loads((ROOT / "source-manifest-dev107.json").read_text(encoding="utf-8"))
    if (dev107.get("schema") != "gxtxt.public-validation-sources/5"
            or dev107.get("referenceFramework") != "0.9.8.10-dev-107"
            or dev107.get("referenceMainCommit") != "2e404977430906f6bc711239d5d934b72f0a6080"
            or dev107.get("officialArchiveSha256") != "f5ffd37b22a98544a6f678ff0c7835bb10a9e05b778e21008d775beac58e33ce"
            or dev107.get("selectedCount") != 11
            or dev107.get("sourceOnly") is not True
            or dev107.get("runnerStatus") != "NOT RUN"
            or len(dev107.get("files", [])) != 11):
        raise ValueError("Unrecognized dev-107 source-only inventory")
    recent107 = set()
    for entry in dev107["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106 | recent107)
                or not name.startswith("validation/official_dev107/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/unified_dev107/" + rel.name):
            raise ValueError("Invalid dev-107 scientific test path: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Dev-107 test source missing: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)
                or "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107" in raw.decode("utf-8")):
            raise ValueError("Unverified or excluded dev-107 test: " + name)
        recent107.add(name)
    dev108 = json.loads((ROOT / "source-manifest-dev108.json").read_text(encoding="utf-8"))
    if (dev108.get("schema") != "gxtxt.public-validation-sources/6"
            or dev108.get("referenceFramework") != "0.9.8.10-dev-108"
            or dev108.get("referenceMainCommit") != "6371001a219a4e611ce89c8b396c62294e6b979c"
            or dev108.get("officialArchiveSha256") != "9299864520f552e7a8dd47766917ed5c323fd1e79e3825ef704cd2d448365e51"
            or dev108.get("selectedCount") != 15
            or dev108.get("sourceOnly") is not True
            or dev108.get("runnerStatus") != "NOT RUN"
            or len(dev108.get("files", [])) != 15):
        raise ValueError("Unrecognized dev-108 source-only inventory")
    recent108 = set()
    for entry in dev108["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106 | recent107 | recent108)
                or not name.startswith("validation/official_dev108/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/dev108/" + rel.name):
            raise ValueError("Invalid dev-108 test source: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-108 source-only file: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)
                or "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107" in raw.decode("utf-8")):
            raise ValueError("Unverified or excluded dev-108 test: " + name)
        recent108.add(name)

    dev109 = json.loads((ROOT / "source-manifest-dev109.json").read_text(encoding="utf-8"))
    if (dev109.get("schema") != "gxtxt.public-validation-sources/7"
            or dev109.get("referenceFramework") != "0.9.8.10-dev-109"
            or dev109.get("referenceMainCommit") != "940b94c4cd3cbe4200f23f3eb5a04c9d836bd3f0"
            or dev109.get("officialArchiveSha256") != "679ec6c8fa929f8f8cfaab51706909100851f67b10279a3b1172dd9247908633"
            or dev109.get("selectedCount") != 15
            or dev109.get("sourceOnly") is not True
            or dev109.get("runnerStatus") != "NOT RUN"
            or len(dev109.get("files", [])) != 15):
        raise ValueError("Unrecognized dev-109 source-only inventory")
    recent109 = set()
    for entry in dev109["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106 | recent107 | recent108 | recent109)
                or not name.startswith("validation/official_dev109/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/" + name.removeprefix("validation/official_dev109/")):
            raise ValueError("Invalid dev-109 original source path: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-109 original test source: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)
                or "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107" in raw.decode("utf-8")):
            raise ValueError("Unverified or owner-private dev-109 source: " + name)
        recent109.add(name)

    dev110 = json.loads((ROOT / "source-manifest-dev110.json").read_text(encoding="utf-8"))
    if (dev110.get("schema") != "gxtxt.public-validation-sources/8"
            or dev110.get("referenceFramework") != "0.9.8.10-dev-110"
            or dev110.get("referenceMainCommit") != "ccde3a0f62020941c6ed3756c4de3c135a4772e4"
            or dev110.get("officialArchiveSha256") != "0d311db4c416462ecda70e9dce2cacace292c9e529725ba16213911a0eb0e9ba"
            or dev110.get("developmentStatus") != "INTERMEDIATE_TASK210_SOURCE_SNAPSHOT"
            or dev110.get("selectedCount") != 7
            or dev110.get("sourceOnly") is not True
            or dev110.get("runnerStatus") != "NOT RUN"
            or len(dev110.get("files", [])) != 7):
        raise ValueError("Unrecognized dev-110 source-only inventory")
    recent110 = set()
    for entry in dev110["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106 | recent107 | recent108 | recent109 | recent110)
                or not name.startswith("validation/official_dev110/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/" + name.removeprefix("validation/official_dev110/")):
            raise ValueError("Invalid dev-110 original source path: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-110 original test source: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)
                or "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107" in raw.decode("utf-8")):
            raise ValueError("Unverified or owner-private dev-110 source: " + name)
        recent110.add(name)

    dev111 = json.loads((ROOT / "source-manifest-dev111.json").read_text(encoding="utf-8"))
    if (dev111.get("schema") != "gxtxt.public-validation-sources/9"
            or dev111.get("referenceFramework") != "0.9.8.10-dev-111"
            or dev111.get("sourceRevision") != "r3"
            or dev111.get("referenceMainCommit") != "4daf135e49378eff1f413310bc17cf32f1928c44"
            or dev111.get("officialArchiveSha256") != "c31721b84e8f66cd385c1df4d82fae76e32ca816f2bec7f74c434ac720d26cfe"
            or dev111.get("selectedCount") != 7
            or dev111.get("sourceOnly") is not True
            or dev111.get("runnerStatus") != "NOT RUN"
            or len(dev111.get("files", [])) != 7):
        raise ValueError("Unrecognized dev-111 revision r3 source-only inventory")
    recent111 = set()
    for entry in dev111["files"]:
        name = entry["path"]
        rel = Path(name)
        if (rel.is_absolute() or ".." in rel.parts
                or name in (seen | newer | recent | recent106 | recent107 | recent108 | recent109 | recent110 | recent111)
                or not name.startswith("validation/official_dev111/")
                or rel.suffix.lower() not in (".tcl", ".py")
                or entry.get("sourcePath") != "validation/" + name.removeprefix("validation/official_dev111/")):
            raise ValueError("Invalid dev-111 original source: " + name)
        candidate = ROOT / rel
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT):
            raise ValueError("Missing dev-111 original source file: " + name)
        raw = candidate.read_bytes()
        if (len(raw) != entry["bytes"]
                or hashlib.sha256(raw).hexdigest() != entry["sha256"]
                or any(token.lower() in raw.decode("utf-8").lower() for token in BANNED)
                or "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107" in raw.decode("utf-8")):
            raise ValueError("Unverified or excluded dev-111 source file: " + name)
        recent111.add(name)

    # Additional maintenance patch fixtures are byte-identical author sources.
    # Static patch/package checks live in tools/validate_dev111_patches.py.
    sys.path.insert(0, str(ROOT / "tools"))
    from validate_dev111_patches import read_manifest as _read_patch_manifest
    patch_data = _read_patch_manifest()
    patch_sources = {x["publicPath"] for x in patch_data["originalFixtures"]}
    if len(patch_sources) != 7:
        raise ValueError("Wrong DEV111 patch fixture source count")

    # DEV111 P016/P017 original owner test scripts are source-only and are
    # independently checksum-bound to the P007–P017 patch manifest.
    from validate_dev111_p007_p017 import load as _load_p017_sources
    dev111_p017 = _load_p017_sources()
    patch_p017_sources = {item["path"] for item in dev111_p017["selectedPortableSourceTests"]}
    if len(patch_p017_sources) != 31:
        raise ValueError("P016/P017 original source-only test inventory incomplete")

    for candidate in (ROOT / "validation").rglob("*"):
        if candidate.is_symlink():
            raise ValueError("Unexpected symlink: " + str(candidate))
        if candidate.is_file() and candidate.relative_to(ROOT).as_posix() not in (seen | newer | recent | recent106 | recent107 | recent108 | recent109 | recent110 | recent111 | patch_sources | patch_p017_sources):
            raise ValueError("Unreviewed file inside validation tree: " + str(candidate))
    if not (ROOT / "LICENSE").is_file():
        raise ValueError("GPL license missing")
    if announce:
        print("PASS: 167 original validation sources through dev-111 P017, including 31 curated P016/P017 cases; SHA-256 verified.")
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
