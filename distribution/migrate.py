#!/usr/bin/env python3
"""Side-by-side personal migration into an already complete DEV112 distribution.

This is migration tooling, not an alternative plugin registry or installer.
The source DEV111 installation, its Configuration and scientific data are read-only.
"""
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TYPES = {"module": ("modules", "module.ini"), "model": ("models", "model.ini"),
         "instrument": ("instruments", "instrument.ini"),
         "analysis_definition": ("analysis_definitions", "analysis.ini")}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def relative(value):
    p = PurePosixPath(value)
    if not value or p.is_absolute() or ".." in p.parts or "\\" in value or str(p) != value:
        raise ValueError(f"Unsafe manifest path: {value!r}")
    return Path(*p.parts)


def no_links(path):
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError(f"Symbolic link is not a supported installation path: {parent}")


def canonical(path):
    path = path.absolute()
    no_links(path)
    return path.resolve(strict=False)


def files_under(root):
    result = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError(f"Symbolic link in payload: {path}")
            if not path.is_dir():
                if not path.is_file():
                    raise ValueError(f"Non-ordinary file: {path}")
                result[path.relative_to(root).as_posix()] = path
    return result


def protected_module(meta):
    core = meta.get("core", "0").strip().lower() in {"1", "true", "yes", "on"}
    selectable = meta.get("selectable", "1").strip().lower()
    if selectable not in {"0", "1", "true", "false", "yes", "no", "on", "off"}:
        raise ValueError("Invalid module selectable declaration")
    always = meta.get("kind", "").strip() == "acquisition" or selectable in {"0", "false", "no", "off"}
    return core or always


def assert_optional_package(package):
    """Release boundary only: CORE and ALWAYS are already bundled, never installed."""
    with zipfile.ZipFile(package) as archive:
        manifests = [name for name in archive.namelist() if PurePosixPath(name).name == "plugin-package.ini"]
        if len(manifests) != 1:
            raise ValueError(f"Expected one package manifest: {package}")
        data = configparser.ConfigParser(interpolation=None, strict=False)
        data.read_string(archive.read(manifests[0]).decode("utf-8-sig"))
        kind = data["package"].get("type", "").strip().lower()
        if kind not in TYPES:
            raise ValueError(f"Unsupported package type: {kind}")
        descriptor = str(PurePosixPath(manifests[0]).parent / TYPES[kind][1])
        module = configparser.ConfigParser(interpolation=None, strict=False)
        module.read_string(archive.read(descriptor).decode("utf-8-sig"))
        meta = module["meta"]
        core = meta.get("core", "0").strip().lower() in {"1", "true", "yes", "on"}
        if core or (kind == "module" and protected_module(meta)):
            raise ValueError(f"CORE/ALWAYS package cannot enter the distribution installer: {package}")


def verify_bundle():
    manifest_path = ROOT / "distribution/manifests/files.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = {}
    for item in manifest["files"]:
        name = item["path"]
        relative(name)
        if name in expected:
            raise ValueError(f"Duplicate manifest file: {name}")
        expected[name] = item
    actual = files_under(ROOT)
    actual.pop("distribution/manifests/files.json", None)
    if actual.keys() != expected.keys():
        raise ValueError(f"Bundle file closure differs: missing={sorted(expected.keys()-actual.keys())}, "
                         f"extra={sorted(actual.keys()-expected.keys())}")
    for name, path in actual.items():
        item = expected[name]
        if (path.stat().st_size != item["size"] or digest(path) != item["sha256"]
                or stat.S_IMODE(path.stat().st_mode) != item["mode"]):
            raise ValueError(f"Bundle integrity mismatch: {name}")
    packages = json.loads((ROOT / "distribution/manifests/plugins.json").read_text(encoding="utf-8"))
    for item in packages["plugins"]:
        if item["type"] not in TYPES or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", item["id"]):
            raise ValueError("Invalid package identity in manifest")
        package = ROOT / relative(item["path"])
        if digest(package) != item["sha256"]:
            raise ValueError(f"Package identity mismatch: {item['id']}")
        assert_optional_package(package)
    return manifest, packages


def read_ini(path):
    no_links(path)
    data = configparser.ConfigParser(interpolation=None, strict=False)
    data.read_string(path.read_text(encoding="utf-8-sig"))
    return data


def tree_identity(root):
    return {name: digest(path) for name, path in files_under(root).items()}


def plan_migration(old, packages):
    """Read source descriptors/registry; never transport mutable registry rows."""
    no_links(old)
    if not (old / "gxtxt_pipeline.tcl").is_file():
        raise ValueError("Migration source is not a GX-TXT installation")
    no_links(old / "VERSION.txt")
    version = (old / "VERSION.txt").read_text().strip()
    if version != "0.9.8.10-dev-111":
        raise ValueError(f"Supported migration source is DEV111, observed {version!r}")
    registry_path = old / "plugins/.registry/installed.ini"
    registered = {}
    if registry_path.is_file():
        for section in read_ini(registry_path).values():
            if "id" in section and "type" in section:
                registered[section["id"]] = dict(section)
    supplied = {item["id"]: item for item in packages["plugins"]}
    demo_ids = set(json.loads((ROOT / "distribution/module_packaging.json").read_text())["demo_ids"])
    operations, snapshots, limitations = [], {}, []
    for kind, (folder, descriptor) in TYPES.items():
        parent = old / "plugins" / folder
        if not parent.is_dir():
            continue
        no_links(parent)
        for source in sorted(parent.iterdir()):
            if source.name.startswith("."):
                continue
            no_links(source)
            if not source.is_dir():
                continue
            ini = source / descriptor
            if not ini.is_file():
                continue
            meta = read_ini(ini)["meta"]
            identity = meta.get("id", "")
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", identity) or identity != source.name:
                raise ValueError(f"Malformed migration plugin identity: {source}")
            if identity in demo_ids:
                limitations.append(f"Demo package remains separate; install through the dedicated demo installer if required: {identity}")
                continue
            baseline = ROOT / "plugins" / folder / identity
            baseline_descriptor = baseline / descriptor
            if baseline_descriptor.is_file():
                baseline_meta = read_ini(baseline_descriptor)["meta"]
                if (kind == "module" and protected_module(baseline_meta)) or baseline_meta.get("core", "0").strip().lower() in {"1", "yes", "true", "on"}:
                    # The owner-designated release class is authoritative even
                    # where the older DEV111 descriptor lacked a CORE flag.
                    continue
            if kind == "module" and protected_module(meta):
                # CORE/ALWAYS are supplied by the consolidated framework.
                # No installation, registration or update operation is planned
                # for them, including personal migration.
                if not (ROOT / "plugins" / folder / identity).is_dir():
                    limitations.append(f"Personal CORE/ALWAYS module retained only in old tree; outside optional installer: {identity}")
                continue
            if meta.get("core", "0").strip().lower() in {"1", "yes", "true", "on"}:
                continue
            # Baseline modules without a standalone manifest remain bundled
            # according to accepted P035, never reclassified by this tool.
            if identity not in supplied and baseline.is_dir():
                if tree_identity(source) != tree_identity(baseline):
                    raise ValueError(f"Legacy bundled plugin has local changes; source retained for explicit recovery: {identity}")
                continue
            manifest = source / "plugin-package.ini"
            if not manifest.is_file():
                raise ValueError(f"Personal plugin lacks an installable package; old source retained: {source}")
            info = read_ini(manifest)["package"]
            for field, value in (("id", identity), ("type", kind), ("version", meta.get("version", ""))):
                if info.get(field, "").strip() != value:
                    raise ValueError(f"Migration package/descriptor {field} mismatch: {source}")
            if identity in registered and registered[identity].get("type") != kind:
                raise ValueError(f"Migration registry/type conflict: {identity}")
            snapshots[str(source)] = tree_identity(source)
            if identity in supplied:
                if supplied[identity]["type"] != kind:
                    raise ValueError(f"Distribution/personal package type conflict: {identity}")
                # CORE decides the ordering of versions and refuses downgrades.
                # Same-version conflicts are detected by accepted source hashes
                # by the worker's migration helper below, never overwritten.
                operations.append({"id": identity, "type": kind, "path": str(source),
                                   "old_version": meta.get("version", ""),
                                   "baseline_version": supplied[identity]["version"], "mode": "compare"})
            else:
                operations.append({"id": identity, "type": kind, "path": str(source), "mode": "install"})
    for identity, entry in registered.items():
        if entry.get("type") not in TYPES:
            raise ValueError(f"Unsupported registered personal plugin type: {identity}")
        folder = TYPES[entry["type"]][0]
        if not (old / "plugins" / folder / identity).is_dir():
            limitations.append(f"Stale DEV111 registry row not migrated: {identity}")
    return operations, snapshots, limitations


def worker(target, items, state, label):
    plan = state / f"{label}.tsv"
    rows = []
    for item in items:
        values = (item["id"], item["type"], str(item["path"]), item.get("mode", "install"))
        if any(any(c in value for c in "\t\r\n") for value in values):
            raise ValueError("Tabs/newlines are not supported in installation plan paths")
        rows.append("\t".join(values))
    plan.write_text("\n".join(rows) + "\n", encoding="utf-8")
    env = {key: value for key, value in os.environ.items() if not key.startswith("GXTXT_")}
    for key, suffix in (("USERPROFILE", "profile"), ("XDG_CONFIG_HOME", "config"),
                        ("XDG_CACHE_HOME", "cache"), ("XDG_DATA_HOME", "data"),
                        ("XDG_STATE_HOME", "state"), ("GXTXT_JOB_ROOT", "jobs"),
                        ("GXTXT_INSTALLATION_ROOT", "installation"),
                        ("GXTXT_RESOURCE_ROOT", "resources"),
                        ("GXTXT_RESOURCE_STORAGE", "resource-storage"),
                        ("GXTXT_SCIENTIFIC_LIBRARY_ROOT", "scientific-libraries")):
        env[key] = str(state / suffix)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    process = subprocess.Popen(["tclsh", str(target / "distribution/install_worker.tcl"), str(plan)],
                               cwd=target, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    timed_out = False
    try:
        output, _ = process.communicate(timeout=1200)
    except subprocess.TimeoutExpired:
        timed_out = True
        # This group was created exclusively for this worker and its children.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            output, _ = process.communicate()
    (state / f"{label}.log").write_text(output, encoding="utf-8")
    print(output, end="", flush=True)
    if process.returncode or timed_out:
        raise RuntimeError(f"Official Plugin Install API refused an operation; see {state / (label+'.log')}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--migrate-from", type=Path, required=True)
    parser.add_argument("--stopped", action="store_true", help="Confirm both applications are closed")
    parser.add_argument("--config-source", type=Path)
    parser.add_argument("--config-target", type=Path)
    args = parser.parse_args()
    target = canonical(ROOT)
    if bool(args.config_source) != bool(args.config_target):
        raise ValueError("Configuration source and target must be specified together")
    if not args.stopped:
        raise ValueError("Migration requires --stopped: close both applications first")
    manifest, packages = verify_bundle()
    old = canonical(args.migrate_from)
    if target == old or target in old.parents or old in target.parents:
        raise ValueError("Migration source/target must be separate installation trees")
    operations, snapshots, limitations = plan_migration(old, packages)
    config_hash = None
    if args.config_source:
        config_source, config_destination = canonical(args.config_source), canonical(args.config_target)
        if not config_source.is_file() or config_destination.exists():
            raise ValueError("Configuration migration needs an ordinary source and fresh destination")
        if config_destination == old or old in config_destination.parents:
            raise ValueError("Configuration destination must not modify the old installation")
        if target == config_destination or config_destination in target.parents:
            raise ValueError("Configuration destination conflicts with the installation target")
        config_hash = digest(config_source)
    for tool in ("tclsh", "unzip", "python3"):
        if not shutil.which(tool):
            raise ValueError(f"Required installation tool missing: {tool}")
    # All non-demo modules are already provided. There is no framework or
    # baseline-package installation here; only personal migration operations.
    # For migration compare versions with the SAME Tcl comparator used by CORE.
    migration = []
    for item in operations:
        if item["mode"] == "compare":
            # The package comparator itself is independent from CORE bootstrap.
            # Use Tcl package vcompare with its exact documented fallback.
            comparison_script = "set a [lindex $argv 0];set b [lindex $argv 1]\nif {[catch {package vcompare $a $b} c]} {set c [string compare $a $b]}\nputs $c\n"
            comparison = subprocess.run(["tclsh", "/dev/stdin", item["old_version"], item["baseline_version"]],
                                         input=comparison_script,
                                         text=True, capture_output=True, check=True)
            cmp = int(comparison.stdout.strip())
            if cmp == 0:
                folder = TYPES[item["type"]][0]
                if tree_identity(Path(item["path"])) != tree_identity(target / "plugins" / folder / item["id"]):
                    raise ValueError(f"Same-version personal package differs; retained unchanged in old installation: {item['id']}")
                continue
            if cmp < 0:
                limitations.append(f"Accepted DEV112 package supersedes older DEV111 copy; old installation retained: {item['id']}")
                continue
            item = dict(item, mode="update")
        migration.append(item)
    state = Path(tempfile.mkdtemp(prefix=".gxtxt-dev112-migrate-" + target.name + "-", dir=target.parent))
    if migration:
        worker(target, migration, state, "personal-plugins")
    for source_name, before in snapshots.items():
        if tree_identity(Path(source_name)) != before:
            raise RuntimeError(f"Migration source changed concurrently: {source_name}")
    if args.config_source:
        if digest(config_source) != config_hash:
            raise RuntimeError("Configuration source changed concurrently")
        config_destination.parent.mkdir(parents=True, exist_ok=True)
        with config_destination.open("xb") as output, config_source.open("rb") as input_stream:
            shutil.copyfileobj(input_stream, output)
        if digest(config_destination) != config_hash:
            raise RuntimeError("Copied Configuration integrity mismatch")
    receipt = {"release": "0.9.8.10-dev-112", "source": manifest.get("source_commit"),
               "baseline_packages_installed": 0, "personal_packages": len(migration),
               "configuration_sha256": config_hash, "limitations": limitations,
               "old_installation_modified": False, "sessions_raw_libraries_copied_or_modified": False,
               "activation": "NOT_PERFORMED"}
    receipt["private_migration_state"] = str(state)
    receipt_bytes = json.dumps(receipt, indent=2) + "\n"
    (state / "migration-receipt.json").write_text(receipt_bytes, encoding="utf-8")
    with (target / "distribution/migration-receipt.json").open("x") as output:
        output.write(receipt_bytes)
    print(f"Prepared personal migration into {target}; no launcher or installation was activated.")
    for message in limitations:
        print(f"LIMITATION: {message}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"DEV112 migration stopped: {error}", file=sys.stderr)
        sys.exit(1)
