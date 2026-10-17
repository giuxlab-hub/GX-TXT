#!/usr/bin/env python3
# GX-TXT Portable Session package helper
# SPDX-License-Identifier: GPL-3.0-or-later
"""Safe, transactional GX-TXT Session export/import helper.

The transport archive is deliberately separate from the scientific Session
manifest.  The package manifest only describes transport/integrity metadata.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import stat
import sys
import tempfile
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable

PACKAGE_MANIFEST = "gxtxt-session-package.ini"
SESSION_PREFIX = "session/"
PACKAGE_FORMAT = "1"
STANDARD_DIRS = ("raw", "metadata", "channels", "analysis", "report", "logs", "notes", "datasets")

# Only files that are unambiguously transient are omitted.  Calculated results,
# graphs, reports and normal runtime/configuration sidecars are retained.
TRANSIENT_NAME_PATTERNS = (
    re.compile(r"^\.gx-(?:install|rollback|uninstall|import|export)-"),
    re.compile(r"^\.nfs[0-9A-Fa-f]+$"),
    re.compile(r".*\.part$"),
    re.compile(r".*\.lock$"),
    re.compile(r".*\.pid$"),
    re.compile(r".*\.tmp\.[0-9]+(?:\..*)?$"),
)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def utc_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def safe_rel_text(rel: PurePosixPath) -> str:
    text = rel.as_posix()
    if not text or text == ".":
        raise ValueError("empty package path")
    if text.startswith("/") or re.match(r"^[A-Za-z]:/", text):
        raise ValueError(f"absolute package path is not allowed: {text}")
    if any(part in ("", ".", "..") for part in rel.parts):
        raise ValueError(f"unsafe package path: {text}")
    if "\x00" in text:
        raise ValueError("NUL in package path")
    return text


def zip_entry_is_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0xFFFF
    return stat.S_ISLNK(mode)


def is_transient(rel: PurePosixPath) -> bool:
    # Staging directories are never authoritative Session content.
    if any(part.startswith(".gx-") and part not in (".gx-session",) for part in rel.parts):
        return True
    # Graph previews are a GUI cache. Their source graph may belong to a
    # previously opened Session; export only the Session's real analysis PNGs.
    if rel.parts[:2] == ("report", "previews"):
        return True
    if rel.parts[:2] == ("cache", "dataset_previews"):
        return True
    name = rel.name
    return any(rx.fullmatch(name) for rx in TRANSIENT_NAME_PATTERNS)


def classify(rel: PurePosixPath) -> str:
    top = rel.parts[0] if rel.parts else ""
    if top == "metadata":
        return "authoritative"
    if top == "notes":
        return "authoritative"
    if top in ("raw", "channels", "datasets"):
        return "scientific_source_or_dataset"
    if top == "analysis":
        return "scientific_result_or_configuration"
    if top == "report":
        return "derived_useful_artifact"
    if top == "logs":
        return "diagnostic_artifact"
    return "session_artifact"


def simple_ini(path: Path) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    section = ""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"invalid UTF-8 INI file: {path}") from exc
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            out.setdefault(section, {})
            continue
        if "=" in raw and section:
            k, v = raw.split("=", 1)
            out.setdefault(section, {})[k.strip()] = v.strip()
    return out


def split_ids(value: str) -> list[str]:
    return [x.strip() for x in re.split(r"[;,]", value or "") if x.strip()]


def module_version(framework_root: Path, module_id: str) -> str:
    p = framework_root / "plugins" / "modules" / module_id / "module.ini"
    if not p.is_file():
        return "missing"
    d = simple_ini(p)
    return d.get("meta", {}).get("version", "unknown") or "unknown"


def discover_dependencies(session: Path, framework_root: Path) -> list[tuple[str, str]]:
    ids: set[str] = set()
    manifest = session / "metadata" / "manifest.ini"
    if manifest.is_file():
        d = simple_ini(manifest)
        for field in ("enabled", "run"):
            ids.update(split_ids(d.get("module_state", {}).get(field, "")))
        acq = d.get("acquisition", {}).get("module_id", "").strip()
        if acq:
            ids.add(acq)
    datasets = session / "metadata" / "datasets.ini"
    if datasets.is_file():
        d = simple_ini(datasets)
        for sec, vals in d.items():
            if sec.startswith("dataset."):
                sm = vals.get("source_module", "").strip()
                if sm:
                    ids.add(sm)
    idocs = session / "metadata" / "interactive_documents.ini"
    if idocs.is_file():
        d = simple_ini(idocs)
        for sec, vals in d.items():
            if sec.startswith("interactive_document."):
                mid = vals.get("module_id", "").strip()
                if mid:
                    ids.add(mid)
    return [(mid, module_version(framework_root, mid)) for mid in sorted(ids)]


@dataclass
class FileItem:
    rel: PurePosixPath
    source: Path
    size: int
    sha256: str
    classification: str
    dereferenced_symlink: bool = False


def scan_session(session: Path) -> tuple[list[PurePosixPath], list[FileItem], list[tuple[str, str]]]:
    session = session.resolve()
    if not session.is_dir():
        raise ValueError(f"Session directory does not exist: {session}")
    manifest = session / "metadata" / "manifest.ini"
    if not manifest.is_file():
        raise ValueError("Session is missing metadata/manifest.ini")
    # Reading it also verifies that the authoritative manifest is UTF-8/INI-like.
    simple_ini(manifest)

    dirs: set[PurePosixPath] = set()
    files: list[FileItem] = []
    external_dependencies: list[tuple[str, str]] = []
    seen: set[str] = set()

    for root, dirnames, filenames in os.walk(session, topdown=True, followlinks=False):
        rootp = Path(root)
        relroot = PurePosixPath(rootp.relative_to(session).as_posix()) if rootp != session else None
        # Symlinked directories are external resources, not recursively copied.
        kept_dirs: list[str] = []
        for dn in sorted(dirnames):
            dp = rootp / dn
            rel = PurePosixPath(dp.relative_to(session).as_posix())
            if dp.is_symlink():
                external_dependencies.append((rel.as_posix(), "symlink_directory"))
                continue
            if is_transient(rel):
                continue
            safe_rel_text(rel)
            dirs.add(rel)
            kept_dirs.append(dn)
        dirnames[:] = kept_dirs

        for fn in sorted(filenames):
            p = rootp / fn
            rel = PurePosixPath(p.relative_to(session).as_posix())
            if is_transient(rel):
                continue
            reltext = safe_rel_text(rel)
            if reltext in seen:
                raise ValueError(f"duplicate Session path: {reltext}")
            seen.add(reltext)
            deref = p.is_symlink()
            if deref:
                try:
                    target = p.resolve(strict=True)
                except FileNotFoundError:
                    external_dependencies.append((reltext, "broken_symlink"))
                    continue
                if not target.is_file():
                    external_dependencies.append((reltext, "unsupported_symlink_target"))
                    continue
                source = target
            else:
                if not p.is_file():
                    continue
                source = p
            files.append(FileItem(rel, source, source.stat().st_size, sha256_file(source), classify(rel), deref))

    # Ensure standard empty directories can survive the ZIP transport.
    for d in STANDARD_DIRS:
        dirs.add(PurePosixPath(d))
    return sorted(dirs, key=lambda p: p.as_posix()), sorted(files, key=lambda x: x.rel.as_posix()), external_dependencies


def find_portable_acquisition_source(session: Path, files: list[FileItem]) -> tuple[str, str]:
    """Return (packaged relative source, unresolved external source)."""
    mf = session / "metadata" / "manifest.ini"
    d = simple_ini(mf)
    value = d.get("acquisition", {}).get("input_csv", "").strip()
    if not value:
        return "", ""
    p = Path(value)
    if not p.is_absolute():
        return "", ""
    try:
        p = p.resolve(strict=True)
    except FileNotFoundError:
        return "", value
    session_res = session.resolve()
    if session_res == p or session_res in p.parents:
        return p.relative_to(session_res).as_posix(), ""
    # Prefer an already-packaged raw file resolving to the same external target.
    for item in files:
        if item.rel.parts and item.rel.parts[0] == "raw":
            try:
                if item.source.resolve() == p:
                    return item.rel.as_posix(), ""
            except OSError:
                pass
    return "", value


def write_package_manifest(
    out: Path,
    *,
    framework_version: str,
    session_name: str,
    files: list[FileItem],
    dirs: list[PurePosixPath],
    dependencies: list[tuple[str, str]],
    external_dependencies: list[tuple[str, str]],
    acquisition_source_rel: str,
    carrier_installation: str = "unknown",
) -> None:
    with out.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write("; GX-TXT Portable Session package manifest\n")
        fh.write("; SPDX-License-Identifier: GPL-3.0-or-later\n")
        fh.write("[package]\n")
        fh.write(f"format_version={PACKAGE_FORMAT}\n")
        fh.write(f"source_framework_version={framework_version}\n")
        fh.write(f"session_name={session_name}\n")
        fh.write(f"export_timestamp={utc_timestamp()}\n")
        fh.write(f"carrier_installation={carrier_installation}\n")
        fh.write(f"file_count={len(files)}\n")
        fh.write(f"directory_count={len(dirs)}\n")
        fh.write(f"dependency_count={len(dependencies)}\n")
        fh.write(f"external_dependency_count={len(external_dependencies)}\n")
        fh.write(f"acquisition_source_rel={acquisition_source_rel}\n")
        for i, d in enumerate(dirs, 1):
            fh.write(f"\n[directory.{i}]\npath={d.as_posix()}\n")
        for i, item in enumerate(files, 1):
            fh.write(f"\n[file.{i}]\n")
            fh.write(f"path={item.rel.as_posix()}\n")
            fh.write(f"size={item.size}\n")
            fh.write(f"sha256={item.sha256}\n")
            fh.write(f"classification={item.classification}\n")
            fh.write(f"dereferenced_symlink={1 if item.dereferenced_symlink else 0}\n")
        for i, (mid, ver) in enumerate(dependencies, 1):
            fh.write(f"\n[dependency.{i}]\nmodule_id={mid}\nversion={ver}\n")
        for i, (path, kind) in enumerate(external_dependencies, 1):
            fh.write(f"\n[external_dependency.{i}]\npath={path}\nkind={kind}\n")


def export_session(session: Path, archive: Path, framework_root: Path, framework_version: str, carrier_installation: str = "unknown") -> dict[str, str]:
    session = session.resolve()
    framework_root = framework_root.resolve()
    dirs, files, external_deps = scan_session(session)
    acquisition_rel, unresolved = find_portable_acquisition_source(session, files)
    if unresolved:
        # When the Session manifest points to a normal user scientific source
        # outside the Session tree, make the transport package self-contained
        # instead of preserving a machine-specific absolute path.  Only a
        # regular file explicitly referenced by the Session is copied; arbitrary
        # machine-global directories/resources are never traversed.
        ext_source = Path(unresolved)
        try:
            ext_source = ext_source.resolve(strict=True)
        except (FileNotFoundError, OSError):
            ext_source = None
        if ext_source is not None and ext_source.is_file():
            base = re.sub(r"[^A-Za-z0-9._-]+", "_", ext_source.name).strip("._") or "source"
            digest = sha256_file(ext_source)
            rel = PurePosixPath("raw") / "portable_source" / base
            occupied = {item.rel.as_posix() for item in files}
            if rel.as_posix() in occupied:
                stem = Path(base).stem or "source"
                suffix = Path(base).suffix
                rel = PurePosixPath("raw") / "portable_source" / f"{stem}-{digest[:12]}{suffix}"
            files.append(FileItem(rel, ext_source, ext_source.stat().st_size, digest,
                                  "scientific_source_or_dataset", True))
            files.sort(key=lambda x: x.rel.as_posix())
            dirs = sorted(set(dirs) | {PurePosixPath("raw/portable_source")},
                          key=lambda path: path.as_posix())
            acquisition_rel = rel.as_posix()
        else:
            external_deps.append((unresolved, "acquisition_source_unavailable_or_not_packaged"))
    deps = discover_dependencies(session, framework_root)

    archive = archive.resolve()
    archive.parent.mkdir(parents=True, exist_ok=True)
    tmp_archive = archive.with_name(archive.name + f".tmp-{os.getpid()}")
    if tmp_archive.exists():
        tmp_archive.unlink()
    with tempfile.TemporaryDirectory(prefix="gxtxt-session-export-") as td:
        manifest = Path(td) / PACKAGE_MANIFEST
        write_package_manifest(
            manifest,
            framework_version=framework_version,
            session_name=session.name,
            files=files,
            dirs=dirs,
            dependencies=deps,
            external_dependencies=external_deps,
            acquisition_source_rel=acquisition_rel,
            carrier_installation=carrier_installation,
        )
        try:
            with zipfile.ZipFile(tmp_archive, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
                zf.write(manifest, PACKAGE_MANIFEST)
                for d in dirs:
                    info = zipfile.ZipInfo(SESSION_PREFIX + d.as_posix().rstrip("/") + "/")
                    info.external_attr = (stat.S_IFDIR | 0o755) << 16
                    zf.writestr(info, b"")
                for item in files:
                    zf.write(item.source, SESSION_PREFIX + item.rel.as_posix())
            os.replace(tmp_archive, archive)
        finally:
            if tmp_archive.exists():
                tmp_archive.unlink()
    return {
        "archive": str(archive),
        "sha256": sha256_file(archive),
        "file_count": str(len(files)),
        "dependency_count": str(len(deps)),
        "external_dependency_count": str(len(external_deps)),
    }


def parse_package_manifest_bytes(data: bytes) -> dict[str, dict[str, str]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("package manifest is not valid UTF-8") from exc
    out: dict[str, dict[str, str]] = {}
    section = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            if section in out:
                raise ValueError(f"duplicate package manifest section: {section}")
            out[section] = {}
        elif "=" in raw and section:
            k, v = raw.split("=", 1)
            k = k.strip()
            if k in out[section]:
                raise ValueError(f"duplicate package manifest key: {section}.{k}")
            out[section][k] = v.strip()
        else:
            raise ValueError(f"malformed package manifest line: {raw}")
    return out


def validate_archive(archive: Path) -> tuple[dict[str, dict[str, str]], dict[str, zipfile.ZipInfo]]:
    archive = archive.resolve()
    if not archive.is_file():
        raise ValueError(f"portable Session archive not found: {archive}")
    try:
        zf = zipfile.ZipFile(archive, "r")
    except zipfile.BadZipFile as exc:
        raise ValueError("invalid or corrupt ZIP archive") from exc
    with zf:
        infos: dict[str, zipfile.ZipInfo] = {}
        for info in zf.infolist():
            raw = info.filename.replace("\\", "/")
            rel = PurePosixPath(raw.rstrip("/"))
            if raw != PACKAGE_MANIFEST:
                safe_rel_text(rel)
            if raw in infos:
                raise ValueError(f"duplicate ZIP path: {raw}")
            if zip_entry_is_symlink(info):
                raise ValueError(f"symbolic links are not allowed in portable Session archives: {raw}")
            infos[raw] = info
        if PACKAGE_MANIFEST not in infos:
            raise ValueError(f"missing required {PACKAGE_MANIFEST}")
        manifest = parse_package_manifest_bytes(zf.read(PACKAGE_MANIFEST))
        pkg = manifest.get("package", {})
        if pkg.get("format_version") != PACKAGE_FORMAT:
            raise ValueError(f"unsupported portable Session package version '{pkg.get('format_version', '')}'")
        try:
            count = int(pkg.get("file_count", "-1"))
            dcount = int(pkg.get("directory_count", "-1"))
        except ValueError as exc:
            raise ValueError("invalid package file/directory count") from exc
        file_sections = [s for s in manifest if re.fullmatch(r"file\.\d+", s)]
        dir_sections = [s for s in manifest if re.fullmatch(r"directory\.\d+", s)]
        if len(file_sections) != count:
            raise ValueError("package file inventory count mismatch")
        if len(dir_sections) != dcount:
            raise ValueError("package directory inventory count mismatch")
        expected_paths: set[str] = set()
        for sec in sorted(file_sections, key=lambda s: int(s.split(".")[1])):
            rec = manifest[sec]
            rel = PurePosixPath(rec.get("path", ""))
            reltxt = safe_rel_text(rel)
            arcname = SESSION_PREFIX + reltxt
            if arcname in expected_paths:
                raise ValueError(f"duplicate inventory path: {reltxt}")
            expected_paths.add(arcname)
            info = infos.get(arcname)
            if info is None or info.is_dir():
                raise ValueError(f"missing required Session file: {reltxt}")
            try:
                expected_size = int(rec.get("size", "-1"))
            except ValueError as exc:
                raise ValueError(f"invalid size in inventory for {reltxt}") from exc
            if info.file_size != expected_size:
                raise ValueError(f"size mismatch for {reltxt}")
            expected_sha = rec.get("sha256", "").lower()
            if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
                raise ValueError(f"invalid SHA-256 inventory entry for {reltxt}")
            h = hashlib.sha256()
            with zf.open(info, "r") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    h.update(chunk)
            if h.hexdigest() != expected_sha:
                raise ValueError(f"SHA-256 mismatch for {reltxt}")
        # Unknown Session files are rejected; directory entries and package manifest are allowed.
        for name, info in infos.items():
            if name == PACKAGE_MANIFEST or info.is_dir():
                continue
            if not name.startswith(SESSION_PREFIX):
                raise ValueError(f"unexpected archive member outside Session root: {name}")
            if name not in expected_paths:
                raise ValueError(f"Session file is not declared in package inventory: {name[len(SESSION_PREFIX):]}")
        if SESSION_PREFIX + "metadata/manifest.ini" not in expected_paths:
            raise ValueError("portable Session is missing metadata/manifest.ini")
    return manifest, infos


def ini_rewrite(path: Path, updates: dict[tuple[str, str], str]) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    section = ""
    found: set[tuple[str, str]] = set()
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1].strip()
            out.append(line)
            continue
        if "=" in line and section:
            prefix, _ = line.split("=", 1)
            key = prefix.strip()
            pair = (section, key)
            if pair in updates:
                nl = "\n" if line.endswith("\n") else ""
                out.append(f"{key}={updates[pair]}{nl}")
                found.add(pair)
                continue
        out.append(line)
    # Existing current Manifest Format 2 contains all relocation keys.  Avoid
    # inventing sections in older manifests; missing keys remain untouched.
    path.write_text("".join(out), encoding="utf-8", newline="\n")


def import_session(archive: Path, destination: Path, current_worker_file: str = "", logical_destination: Path | None = None) -> dict[str, str]:
    manifest, _ = validate_archive(archive)
    destination = destination.resolve()
    logical_destination = logical_destination.resolve() if logical_destination is not None else destination
    if destination.exists():
        raise ValueError(f"destination Session already exists: {destination}")
    parent = destination.parent
    parent.mkdir(parents=True, exist_ok=True)
    stage_root = Path(tempfile.mkdtemp(prefix=".gxtxt-import-", dir=parent))
    stage_session = stage_root / "session"
    try:
        stage_session.mkdir()
        with zipfile.ZipFile(archive, "r") as zf:
            # Create declared directories first.
            dirs = []
            for sec, rec in manifest.items():
                if re.fullmatch(r"directory\.\d+", sec):
                    rel = PurePosixPath(rec.get("path", ""))
                    reltxt = safe_rel_text(rel)
                    dirs.append(reltxt)
            for reltxt in sorted(dirs):
                (stage_session / Path(reltxt)).mkdir(parents=True, exist_ok=True)
            for sec, rec in manifest.items():
                if not re.fullmatch(r"file\.\d+", sec):
                    continue
                rel = PurePosixPath(rec.get("path", ""))
                reltxt = safe_rel_text(rel)
                target = stage_session / Path(reltxt)
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(SESSION_PREFIX + reltxt, "r") as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
                if sha256_file(target) != rec.get("sha256", "").lower():
                    raise ValueError(f"staged file integrity mismatch: {reltxt}")
        for d in STANDARD_DIRS:
            (stage_session / d).mkdir(parents=True, exist_ok=True)
        mf = stage_session / "metadata" / "manifest.ini"
        if not mf.is_file():
            raise ValueError("staged Session has no metadata/manifest.ini")
        simple_ini(mf)

        pkg = manifest.get("package", {})
        updates: dict[tuple[str, str], str] = {
            ("acquisition", "session_root"): str(logical_destination.parent),
            ("acquisition", "session_name"): logical_destination.name,
        }
        relsrc = pkg.get("acquisition_source_rel", "").strip()
        if relsrc:
            safe_rel_text(PurePosixPath(relsrc))
            src = logical_destination / Path(relsrc)
            # Store the final destination path, not the staging path.
            updates[("acquisition", "input_csv")] = str(src)
        if current_worker_file:
            updates[("runtime", "worker_file")] = current_worker_file
        ini_rewrite(mf, updates)

        # Commit is one rename on the same filesystem.  The destination was
        # checked before staging and is checked again immediately before commit.
        if destination.exists():
            raise ValueError(f"destination Session appeared during import: {destination}")
        os.replace(stage_session, destination)
    except Exception:
        shutil.rmtree(stage_root, ignore_errors=True)
        raise
    shutil.rmtree(stage_root, ignore_errors=True)
    deps = []
    for sec, rec in manifest.items():
        if re.fullmatch(r"dependency\.\d+", sec):
            deps.append((rec.get("module_id", ""), rec.get("version", "")))
    external = []
    for sec, rec in manifest.items():
        if re.fullmatch(r"external_dependency\.\d+", sec):
            external.append((rec.get("path", ""), rec.get("kind", "")))
    return {
        "session": str(destination),
        "source_framework_version": manifest.get("package", {}).get("source_framework_version", ""),
        "dependency_count": str(len(deps)),
        "external_dependency_count": str(len(external)),
    }


def emit(result: dict[str, str]) -> None:
    for k, v in result.items():
        print(f"{k}={v}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="GX-TXT Portable Session helper")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("export")
    p.add_argument("session")
    p.add_argument("archive")
    p.add_argument("framework_root")
    p.add_argument("framework_version")
    p.add_argument("--carrier-installation", default="unknown")
    p = sub.add_parser("validate")
    p.add_argument("archive")
    p = sub.add_parser("import")
    p.add_argument("archive")
    p.add_argument("destination")
    p.add_argument("--worker-file", default="")
    p.add_argument("--logical-destination", default="")
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            emit(export_session(Path(args.session), Path(args.archive), Path(args.framework_root), args.framework_version, args.carrier_installation))
        elif args.command == "validate":
            manifest, _ = validate_archive(Path(args.archive))
            pkg = manifest.get("package", {})
            result = {
                "format_version": pkg.get("format_version", ""),
                "source_framework_version": pkg.get("source_framework_version", ""),
                "session_name": pkg.get("session_name", ""),
                "carrier_installation": pkg.get("carrier_installation", "unknown"),
                "export_timestamp": pkg.get("export_timestamp", ""),
                "file_count": pkg.get("file_count", ""),
                "dependency_count": pkg.get("dependency_count", ""),
                "external_dependency_count": pkg.get("external_dependency_count", ""),
            }
            for sec, rec in manifest.items():
                m = re.fullmatch(r"dependency\.(\d+)", sec)
                if m:
                    result[f"dependency.{m.group(1)}"] = rec.get("module_id", "") + "|" + rec.get("version", "")
                m = re.fullmatch(r"external_dependency\.(\d+)", sec)
                if m:
                    result[f"external_dependency.{m.group(1)}"] = rec.get("path", "") + "|" + rec.get("kind", "")
            emit(result)
        elif args.command == "import":
            emit(import_session(Path(args.archive), Path(args.destination), args.worker_file, Path(args.logical_destination) if args.logical_destination else None))
        return 0
    except Exception as exc:
        print(f"Portable Session error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
