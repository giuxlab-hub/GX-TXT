#!/usr/bin/env python3
"""Framework-owned execution adapter for exact researcher Python snapshots."""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import argparse
import configparser
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import os
from pathlib import Path
import runpy
import shutil
import sys
import traceback

import gxtxt


def timestamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def report(path, fields):
    with path.open("w", encoding="utf-8") as stream:
        for key, value in fields.items():
            stream.write(f"{key}: {str(value).replace(chr(10), ' ')}\n")


def main(runtime_path):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(runtime_path, encoding="utf-8")
    runtime = config["runtime"]
    settings = config["config"]
    outdir = Path(runtime["output_dir"]).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "python_runtime.ini").write_text(
        "[runtime]\npython_executable=" + sys.executable +
        "\npython_version=" + sys.version.split()[0] + "\n", encoding="utf-8")
    source = Path(settings["script_file"]).resolve()
    snapshot = outdir / "executed_script.py"
    project = None
    if config.has_section('script_project'):
        from script_project import verify
        project,_,_=verify(Path(config['script_project']['project_manifest']).parent)
        if project['sha256'] != settings['script_sha256']:
            raise ValueError('Whole-project execution snapshot differs')
        snapshot = source
    started = timestamp()
    fields = {
        "Status": "FAIL", "Language": "Python", "Module ID": runtime.get("module_id", "analysis.python_script"),
        "Python runtime": sys.executable, "Python version": sys.version.split()[0],
        "Source mode": settings.get("source_mode", "registered_script"),
        "Script reference": settings.get("registered_script", ""),
        "Script ID": settings.get("script_id", ""),
        "Script scope": settings.get("script_scope", ""),
        "Script version": settings.get("script_version", ""),
        "Script revision": settings.get("script_revision", ""),
        "Expected SHA-256": settings.get("script_sha256", ""),
        "Required APIs": settings.get("required_apis", ""),
        "Started at": started,
    }
    for package in ("numpy", "scipy"):
        try:
            fields[f"{package} version"] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            fields[f"{package} version"] = "not installed"
    try:
        fields["Module version"] = settings.get("module_version", "")
        if settings.get("script_language", "Python") != "Python":
            raise ValueError("registered script language is not Python")
        if source.suffix.lower() != ".py" or not source.is_file():
            raise ValueError(f"Python script snapshot is missing: {source}")
        reference = settings.get("registered_script", "")
        if fields["Source mode"] == "registered_script" and reference != f"{settings.get('script_scope', '')}:{settings.get('script_id', '')}":
            raise ValueError("registered Python script identity is incomplete")
        if project is None: shutil.copyfile(source, snapshot)
        digest = hashlib.sha256(snapshot.read_bytes()).hexdigest()
        fields["Script SHA-256"] = digest
        expected = config['script_project']['entrypoint_sha256'] if project else settings.get("script_sha256", "").lower()
        if expected and digest != expected:
            raise ValueError("registered Session Python script SHA-256 differs from its execution snapshot")
        execution = {
            "script_name": settings.get("script_name", source.name),
            "script_sha256": project['sha256'] if project else digest,
            "arguments_raw": settings.get("arguments", ""),
            "script_reference": reference,
            "script_id": settings.get("script_id", ""),
            "script_scope": settings.get("script_scope", ""),
            "script_version": settings.get("script_version", ""),
            "script_revision": settings.get("script_revision", ""),
        }
        gxtxt._activate(runtime_path, execution)
        try:
            info = gxtxt.gxtxt_bridge_info()
            fields["Bridge API ID"] = info["api_id"]
            fields["Discovered APIs"] = ";".join(entry["api_id"] for entry in gxtxt.gxtxt_api_list())
            requirements = [entry.strip() for entry in settings.get("required_apis", "").replace(",", ";").split(";") if entry.strip()]
            gxtxt.gxtxt_api_require(requirements)
            context = gxtxt.gxtxt_context()
            if context.get("module_id") != runtime.get("module_id"):
                raise ValueError("Script Bridge execution context belongs to another module")
            fields["Context run ID"] = context.get("run_id", "")
            working = settings.get("working_directory", "").strip()
            if working:
                os.chdir(working)
            project_paths = []
            project_guard = None
            if project:
                from script_project import ProjectImportGuard
                project_root=Path(config['script_project']['project_root']).resolve()
                project_paths=[str(project_root)]
                sys.path[:0]=project_paths
                project_guard=ProjectImportGuard(project_root,project).__enter__()
            bundle_dir = settings.get("bundle_dir", "").strip()
            if bundle_dir:
                bundle = Path(bundle_dir).resolve()
                if not bundle.is_dir():
                    raise ValueError(f"packaged script bundle is missing: {bundle}")
                sys.path.insert(0, str(bundle))
            import builtins
            export_sentinel = object(); previous_export = getattr(builtins, 'gxtxt_api_export', export_sentinel)
            builtins.gxtxt_api_export = gxtxt.gxtxt_api_export
            code = None if config.has_section("provided_api") else compile(snapshot.read_bytes(), str(snapshot), "exec")
            package=Path(project['entrypoint']).parent.as_posix().replace('/','.') if project else '.'
            namespace = {"__name__": "__main__", "__file__": str(snapshot), "__package__": None if package=='.' else package, 'gxtxt_parameter_declare':gxtxt.gxtxt_parameter_declare}
            if config.has_section('provided_api'):
                from gxtxt_script_provided_runtime import execute_python
                execute_python(config, project, outdir)
                fields['Provided operation'] = config['provided_api']['request_json']
            elif config.getboolean('debug','enabled',fallback=False):
                from gxtxt_python_debug import run_debug
                breakpoints=[int(x) for x in config.get('debug','breakpoints',fallback='').split(';') if x]
                if project:
                    breakpoints={config[s]['path']:[int(x) for x in config[s]['lines'].split(';') if x] for s in config.sections() if s.startswith('debug_file.')}
                run_debug(code,namespace,snapshot,breakpoints,project_root if project else None,project['sha256'] if project else None)
            else:exec(code, namespace)
            if config.has_section('registered_callable'):
                from gxtxt_registered_callable import execute
                invocation = config['registered_callable']
                execute(namespace, invocation, outdir)
                fields['Registered callable'] = invocation['callable_id']
                fields['Callable declaration SHA-256'] = invocation['declaration_sha256']
        finally:
            if 'export_sentinel' in locals():
                if previous_export is export_sentinel: del builtins.gxtxt_api_export
                else: builtins.gxtxt_api_export = previous_export
            if locals().get('project_guard') is not None:project_guard.__exit__(None,None,None)
            for path in locals().get('project_paths',[]):
                if path in sys.path:sys.path.remove(path)
            if settings.get("bundle_dir", "").strip():
                bundle_path = str(Path(settings["bundle_dir"]).resolve())
                if bundle_path in sys.path:
                    sys.path.remove(bundle_path)
            gxtxt._deactivate()
        fields["Status"] = "PASS"
        fields["Message"] = "Researcher Python script completed successfully."
        return 0
    except BaseException as exc:
        fields["Message"] = f"{type(exc).__name__}: {exc}"
        fields["Traceback"] = traceback.format_exc()
        traceback.print_exc()
        return 1
    finally:
        fields["Finished at"] = timestamp()
        report(outdir / "python_script_run_report.txt", fields)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    sys.exit(main(args.config.resolve()))
