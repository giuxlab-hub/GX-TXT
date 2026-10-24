#!/usr/bin/env python3
"""GX-TXT dev111 r3 P001–P005 version-bound, read-only validation.

The checks are executable and meaningful, but do not claim scientific GUI acceptance.
Use an independently cloned Git repository containing annotated maintenance/dev111 tags.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = ROOT / "patch-manifest-dev111.json"
EXPECTED_MAIN = "4daf135e49378eff1f413310bc17cf32f1928c44"
EXPECTED_LAST = "6a59da41c2aa23fdc356e6f956238c02bdc6fff3"
HEX = re.compile(r"^[0-9a-f]{64}$")
PRIVATE = ("/home/giu/", "/srv/gxtxt/", "github_pat_", "GXTXT_SCRIPT_WORKSPACE_DEBUGGER_GUIDE_WP_dev107")
ALLOWED_EXCEPTION_PATHS = {
    "plugins/modules/analysis.octave_script/SHA256SUMS.txt",
    "plugins/modules/analysis.python_script/SHA256SUMS.txt",
}

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def require(test: bool, message: str) -> None:
    if not test:
        raise ValueError(message)

def safe_rel(name: str) -> Path:
    posix = PurePosixPath(name)
    require(
        bool(name) and name == posix.as_posix() and not posix.is_absolute()
        and ".." not in posix.parts and "." not in posix.parts and "\\" not in name
        and not re.match(r"^[A-Za-z]:", name),
        "Unsafe source path: " + name,
    )
    return Path(*posix.parts)

def read_manifest() -> dict:
    info = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    require(info.get("schema") == "gxtxt.patch-validation/1", "Wrong patch manifest schema")
    require(info.get("framework") == "0.9.8.10-dev-111" and info.get("revision") == "r3", "Wrong framework/revision")
    require(info.get("officialMain") == EXPECTED_MAIN and info.get("validatedMaintenanceHead") == EXPECTED_LAST, "Wrong public source identity")
    expected = ["p001-r2", "p002", "p003", "p004", "p005"]
    require([r["patch"] for r in info["patches"]] == expected, "Incomplete/out-of-order patch sequence")
    require([p["requiredPredecessor"] for p in info["patches"]] == [0, 1, 2, 3, 4], "Invalid patch prerequisites")
    require(set(info["publicManifestReconciliations"]) == ALLOWED_EXCEPTION_PATHS, "Unexpected source reconciliation exception")
    require(len(info["originalFixtures"]) == 7, "Wrong selected original fixture count")
    require(info["runnerScope"] == "STATIC_SOURCE_AND_PACKAGE_ONLY", "Incorrect validation scope")
    for row in info["originalFixtures"]:
        rel = row["publicPath"]
        require(rel.startswith("validation/official_dev111_patches/"), "Unexpected original test location")
        file = ROOT / safe_rel(rel)
        require(not file.is_symlink() and file.is_file() and file.resolve().is_relative_to(ROOT), "Missing or symlinked fixture: " + rel)
        raw = file.read_bytes()
        require(len(raw) == row["bytes"] and digest(raw) == row["sha256"], "Original Tcl source hash mismatch: " + rel)
        require(row["execution"] == "ORIGINAL_SOURCE_ONLY_NOT_EXECUTED_BY_PUBLICATION", "Invalid execution classification")
        decoded = raw.decode("utf-8")
        for item in PRIVATE:
            require(item.lower() not in decoded.lower(), "Private material in original Tcl fixture: " + rel)
    for row in info["patches"]:
        require(HEX.fullmatch(row["commit"]) is None or len(row["commit"]) == 40, "Malformed commit")
        require(len(row["commit"]) == len(row["parent"]) == 40, "Git SHA length invalid")
        require(row["tag"].startswith("v0.9.8.10-dev-111-p"), "Unexpected patch tag")
        require(HEX.fullmatch(row["zipSha256"]) is not None, "Invalid ZIP SHA")
        require(HEX.fullmatch(row["manifestSha256"]) is not None, "Invalid source manifest SHA")
        require(row["zipBytes"] > 1000 and row["files"], "Invalid/empty patch payload record")
        for item in row["files"]:
            safe_rel(item["path"])
            require(HEX.fullmatch(item["after"]) is not None, "Invalid postimage SHA")
            if item["before"] is not None:
                require(HEX.fullmatch(item["before"]) is not None, "Invalid preimage SHA")
    return info

class Git:
    def __init__(self, folder: Path):
        self.folder = folder.resolve(strict=True)
        require((self.folder / ".git").exists(), "Repository with .git metadata required")
        require(shutil.which("git") is not None, "git executable required")

    def command(self, *args: str, allow_missing: bool = False) -> bytes | None:
        p = subprocess.run(["git", "-C", str(self.folder), *args],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if p.returncode and allow_missing:
            return None
        require(p.returncode == 0, "Git operation failed " + repr(args) + " " + p.stderr.decode(errors="replace")[:240])
        return p.stdout

    def rev(self, obj: str) -> str:
        return self.command("rev-parse", obj).decode("utf-8").strip()

    def blob(self, rev: str, rel: str) -> bytes | None:
        safe_rel(rel)
        return self.command("show", rev + ":" + rel, allow_missing=True)


def validate_elf(blob: bytes) -> None:
    require(len(blob) > 4096 and blob[:4] == b"\x7fELF", "Native Preview is not a valid ELF blob")
    require(blob[4] == 2 and blob[5] == 1, "P005 must be little-endian ELF64")
    require(struct.unpack_from("<H", blob, 16)[0] == 3, "P005 must be a shared object (ET_DYN)")
    require(struct.unpack_from("<H", blob, 18)[0] == 62, "P005 must target Linux x86_64")


def validate_p005_integration(getblob, info: dict) -> int:
    commit = info["patches"][-1]["commit"]
    cmake = getblob(commit, "core/native2d/CMakeLists.txt")
    worker = getblob(commit, "core/tcl/dataset_preview_worker_v1.tcl")
    native = getblob(commit, "core/native2d/bin/gxpreviewprovider.so")
    for payload, label in ((cmake, "CMake"), (worker, "Tcl Worker"), (native, "ELF binary")):
        require(payload is not None, "P005 missing " + label)
    cmake_text = cmake.decode("utf-8")
    worker_text = worker.decode("utf-8")
    for token in (
        "GXTXT_PREVIEW_PROVIDER_ONLY",
        "add_library(gxpreviewprovider MODULE",
        "gx2d_preview_provider_v1.cpp",
        "gx2d_preview_provider_loader.cpp",
        "install(TARGETS gxpreviewprovider",
    ):
        require(token in cmake_text, "P005 CMake integration missing " + token)
    for token in (
        "source [file join $framework gxtxt_pipeline.tcl]",
        "::GX::datasetPreviewNativeEnsure",
        "if {[catch {::GX::datasetPreviewNativeEnsure} nativeError]}",
        "Native Preview adapter unavailable; using CORE fallback",
        "::GX::datasetPreviewCacheGenerate",
    ):
        require(token in worker_text, "P005 worker integration missing " + token)
    validate_elf(native)
    preserved = info.get("p005PreservedSources", [])
    require(len(preserved) == 7, "P005 source-preservation inventory missing")
    for row in preserved:
        rel = row["path"]
        b = getblob(commit, rel)
        require(b is not None and digest(b) == row["sha256"], "P005 changed preserved native algorithm: " + rel)
    return 3 + len(preserved)


def check_repo(info: dict, folder: Path) -> dict:
    g = Git(folder)
    require(g.rev("refs/tags/v0.9.8.10-dev-111-p005^{}") == EXPECTED_LAST, "Wrong final patch tag")
    checked_blobs = 0
    checked_zips = 0
    records = []
    for row in info["patches"]:
        name, commit, parent = row["patch"], row["commit"], row["parent"]
        require(g.rev(row["tag"] + "^{}") == commit, "Tag does not point at expected patch commit " + name)
        require(g.rev(commit + "^") == parent, "Patch not built on expected predecessor " + name)
        archive = folder / safe_rel(row["archivePath"])
        require(not archive.is_symlink() and archive.is_file(), "Missing public patch ZIP: " + name)
        raw = archive.read_bytes()
        require(len(raw) == row["zipBytes"] and digest(raw) == row["zipSha256"], "Patch archive SHA-256 mismatch: " + name)
        manifest_rel = "patches/dev111/" + row["archivePath"].split("/")[2] + "/MANIFEST.json"
        mblob = g.blob(commit, manifest_rel)
        require(mblob is not None and digest(mblob) == row["manifestSha256"], "Public patch manifest differs from tag: " + name)
        with zipfile.ZipFile(archive) as z:
            members = [i.filename for i in z.infolist() if not i.is_dir()]
            require(len(set(members)) == len(members) and all(safe_rel(n) for n in members), "ZIP member traversal/duplicate path: " + name)
            require(z.testzip() is None, "Bad ZIP CRC: " + name)
            for item in row["files"]:
                rel, after, before = item["path"], item["after"], item["before"]
                current = g.blob(commit, rel)
                previous = g.blob(parent, rel)
                cleaned = info["publicManifestReconciliations"].get(rel) if name == "p003" else None
                expected_after = cleaned or after
                require(current is not None and digest(current) == expected_after,
                        "Published scientific postimage mismatch " + name + ": " + rel)
                if name == "p001-r2":
                    require(current == previous, "P001-r2 changed functional file " + rel)
                    original_p001 = g.blob("v0.9.8.10-dev-111-p001^{}", rel)
                    require(original_p001 == current, "P001-r2 differs from original P001 " + rel)
                elif before is None:
                    require(previous is None, "Expected new file already exists: " + rel)
                elif not cleaned:
                    require(previous is not None and digest(previous) == before, "Patch prerequisite differs " + name + ": " + rel)
                else:
                    require(previous is not None, "Missing sanitized module checksum preimage: " + rel)
                    # The preexisting public module sanitization means the two inventories differ from owner source.
                member = ("payload/" + rel) if name == "p002" else rel
                if name == "p001-r2":
                    with zipfile.ZipFile(z.open("DEV111-P001.zip")) as nested:
                        require(nested.read(rel) == current, "P001 original six-file archive differs " + rel)
                else:
                    require(member in members, "ZIP lacks functional payload: " + name + " " + rel)
                    require(digest(z.read(member)) == after, "ZIP deposited scientific afterhash differs " + name + " " + rel)
                checked_blobs += 1
            if name == "p001-r2":
                require("apply.sh" in members and "ROLLBACK.zip" in members, "P001-r2 installer/rollback missing")
                require(len(row["files"]) == 6, "P001-r2 wrong source count")
            checked_zips += 1
        records.append({"patch": name, "tag": row["tag"], "files": len(row["files"]), "archiveSha256": row["zipSha256"]})
    native_checks = validate_p005_integration(g.blob, info)
    return {
        "status": "DEV111_P001_TO_P005_STATIC_CHAIN_PASS",
        "patches": records,
        "checkedSourcePreimagesAndPostimages": checked_blobs,
        "verifiedPublicZips": checked_zips,
        "p005NativeIntegrationChecks": native_checks,
        "runtimeGuiTest": "NOT_EXECUTED_BY_THIS_TOOL",
    }


def check_final_tree(info: dict, root: Path) -> dict:
    """Read-only comparison; doesn't start GX-TXT, touch a Session or create output in its tree."""
    root = root.resolve(strict=True)
    require((root / "VERSION.txt").read_text(encoding="utf-8").strip() == info["framework"], "Incorrect installed framework version")
    final = {}
    for row in info["patches"]:
        for f in row["files"]:
            final[f["path"]] = (
                info["publicManifestReconciliations"].get(f["path"], f["after"]) if row["patch"] == "p003"
                else f["after"]
            )
    for rel, expected in final.items():
        p = root / safe_rel(rel)
        require(p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root), "Missing installation file: " + rel)
        require(digest(p.read_bytes()) == expected, "Installed patch sequence differs at " + rel)
    native = (root / "core/native2d/bin/gxpreviewprovider.so").read_bytes()
    validate_elf(native)
    return {"status": "EXACT_FINAL_PATCHSET_INSTALLED_SOURCE_HASHES_PASS", "filesChecked": len(final),
            "runtimeGuiTest": "NOT_EXECUTED_BY_THIS_TOOL"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, help="Git checkout with version-bound dev111 P001-P005 tags; validates manifests, source history and binary")
    parser.add_argument("--installed-final", type=Path, help="Optional READ-ONLY check of the final cumulative installed source (no GUI execution)")
    parser.add_argument("--json", action="store_true", help="Machine-readable result output")
    args = parser.parse_args()
    try:
        info = read_manifest()
        result = {"status": "DEV111_PATCH_TEST_SOURCE_MANIFEST_PASS", "originalSourceFixtures": len(info["originalFixtures"])}
        if args.repository:
            result["repository"] = check_repo(info, args.repository)
        if args.installed_final:
            result["installed"] = check_final_tree(info, args.installed_final)
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print("PASS: " + result["status"] + " (seven original author fixtures)")
            if args.repository:
                print("PASS: " + result["repository"]["status"] + " (five patch releases, P005 native checks)")
            if args.installed_final:
                print("PASS: " + result["installed"]["status"])
            print("Scientific GUI/native runtime acceptance is not inferred from static checks.")
        return 0
    except (ValueError, OSError, UnicodeError, zipfile.BadZipFile) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        return 2

if __name__ == "__main__":
    sys.exit(main())
