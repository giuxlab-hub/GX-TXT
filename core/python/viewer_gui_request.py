# SPDX-License-Identifier: GPL-3.0-or-later
"""Managed Viewer GUI auxiliary requests; module packaging retains its owner."""
from pathlib import Path
import importlib.util
import signal
import sys
import tkinter
import json
import os
import tempfile
from gxtxt_job_supervisor import request_process_group, tcl_result

request_process_group()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))

def request():
    raw = sys.stdin.read(2097153)
    if len(raw.encode()) > 2097152: raise ValueError('Viewer request exceeds 2 MiB')
    words = tkinter.Tcl().splitlist(raw)
    if len(words) % 2: raise ValueError('Invalid inert Viewer request')
    return dict(zip(words[::2], words[1::2]))

def run(data):
    framework = Path(__file__).resolve().parents[2]
    if data['operation'] == 'diagnostic_export':
        if set(data) != {'operation', 'input', 'output'}: raise ValueError('Unknown diagnostic export argument')
        source, output = Path(data['input']), Path(data['output'])
        if source.stat().st_size > 16 * 1024 * 1024: raise ValueError('Diagnostic exceeds 16 MiB')
        interpreter = tkinter.Tcl()
        def dictionary(value):
            words = interpreter.splitlist(value)
            if len(words) % 2: raise ValueError('Invalid diagnostic dictionary')
            return dict(zip(words[::2], words[1::2]))
        object_fields = {'environment', 'font', 'inspection', 'action', 'plan', 'filter', 'detail'}
        list_fields = {'cases', 'actions', 'trace', 'boundaries', 'coverage'}
        def convert(value):
            result = dictionary(value)
            for key, item in list(result.items()):
                if key in object_fields:
                    result[key] = convert(item) if item else {}
                elif key in list_fields:
                    result[key] = [convert(row) for row in interpreter.splitlist(item)]
                elif key == 'components':
                    result[key] = {name: convert(row) for name, row in dictionary(item).items()}
                elif key in {'count', 'index', 'elapsed_ms', 'started_ms', 'api_version', 'monotonic_us', 'max_callback_interval_ms', 'last_tick_ms'}:
                    result[key] = int(item)
            return result
        report = convert(source.read_text(encoding='utf-8'))
        report['format_notes'] = 'Opaque scientific/UI values and observation details remain inert Tcl strings; no scientific payload is exported.'
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix='.gui-report-', delete=False) as temporary:
            temporary.write((json.dumps(report, indent=2, ensure_ascii=False) + '\n').encode())
            temporary_path = Path(temporary.name)
        try: os.link(temporary_path, output)
        finally: temporary_path.unlink(missing_ok=True)
        return dict(path=str(output), bytes=output.stat().st_size)
    if data['operation'] != 'generate': raise ValueError('Unknown Viewer auxiliary operation')
    if set(data) != {'operation', 'project', 'source_directory', 'output_directory'}:
        raise ValueError('Unknown Viewer generation argument')
    path = framework / 'plugins/modules/tool.script_module_builder/runtime/builder.py'
    spec = importlib.util.spec_from_file_location('gxtxt_standard_module_builder', path)
    module = importlib.util.module_from_spec(spec); sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    package, sha = module.build_viewer(Path(data['project']), Path(data['source_directory']), Path(data['output_directory']))
    return dict(package=str(package), sha256=sha, generation_report=str(Path(data['source_directory'])/'generation-report.json'))

if __name__ == '__main__':
    try:
        print(tcl_result(dict(ok=True, result=run(request()))), flush=True)
    except Exception as error:
        print(tcl_result(dict(ok=False, error=str(error))), flush=True)
