#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixed CORE CSV recipe adapter, using the bundled canonicalizer, never publishing.

The Tcl owner supplies an immutable definition and an owned temporary allocation.
Preview reads at most 65536 source bytes and displays at most 30 physical lines;
it reports a prefix digest, never a full-file digest. Test streams the entire
source for its digest and runs the SAME parser, with managed cancellation.
"""
from __future__ import annotations
import codecs
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import stat
import sys
import tkinter
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gxtxt_job_supervisor import request_process_group, tcl_result

FRAMEWORK = Path(__file__).resolve().parents[2]
PARSER = FRAMEWORK / 'plugins/modules/acq.generic_csv/runtime/canonicalize_csv.py'
MAX_CONTROL = 1048576
PREVIEW_BYTES = 65536
PREVIEW_LINES = 30
SCHEMA = 'gxtxt.importer_builder_request.v1'
TCL = tkinter.Tcl()


def dictionary(value):
    parts = TCL.splitlist(value)
    if len(parts) % 2 or len(set(parts[::2])) != len(parts) // 2:
        raise ValueError('Malformed or duplicate dictionary field')
    return dict(zip(parts[::2], parts[1::2]))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(value):
    d = dictionary(value)
    d['mappings'] = [dictionary(m) for m in TCL.splitlist(d['mappings'])]
    # Python codec lookup is authoritative for preview, header and full parser.
    codec = codecs.lookup(d['encoding'])
    # Text decoder required: binary transforms such as base64/zlib are not encodings.
    decoded = codecs.getincrementaldecoder(codec.name)(errors='strict').decode(b'', final=False)
    if not isinstance(decoded, str):
        raise ValueError('Choose a Python text encoding')
    d['encoding'] = codec.name
    for k in ('header_rows', 'skip_leading', 'footer_rows'):
        d[k] = int(d[k])
    # Normalize numeric spellings without applying a scientific conversion.
    import math
    for m in d['mappings']:
        m['column'] = int(m['column'])
        for key in ('scale', 'offset'):
            if m[key] != '':
                number = float(m[key])
                if not math.isfinite(number):
                    raise ValueError(f'Mapping {key} must be finite')
                m[key] = format(number, '.17g')
    science = {key: value for key, value in d.items() if key not in {'name', 'description'}}
    encode = lambda obj: json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)
    full, config = encode(d), encode(science)
    return dict(schema=SCHEMA, definition=d, definition_json=full,
                definition_sha256=digest(full.encode()), config_json=full,
                config_sha256=digest(full.encode()), science_sha256=digest(config.encode()), science_json=config, parser_sha256=digest(PARSER.read_bytes()),
                codec=codec.name)


def identity(s):
    return dict(device=s.st_dev, inode=s.st_ino, size_bytes=s.st_size,
                mtime_ns=s.st_mtime_ns, ctime_ns=s.st_ctime_ns)


def source_open(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    stream = os.fdopen(fd, 'rb')
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        stream.close()
        raise ValueError('Source must be an ordinary file, not a link or device')
    return stream


def source_check(path, stream, before):
    if identity(os.fstat(stream.fileno())) != before or identity(os.stat(path, follow_symlinks=False)) != before:
        raise ValueError('Source changed during inspection/Test; review it again')


def prefix(stream, codec, limit=PREVIEW_BYTES):
    raw = stream.read(limit)
    at_eof = len(raw) == os.fstat(stream.fileno()).st_size
    # final=False permits only a genuine incomplete trailing character at a byte
    # boundary. Invalid bytes/overlong UTF8/surrogates are strict decode errors.
    text = codecs.getincrementaldecoder(codec)(errors='strict').decode(raw, final=at_eof)
    if '\x00' in text:
        raise ValueError('Decoded text contains NUL; this CSV recipe requires text')
    return raw, text, at_eof


def parser_args(d, source, output):
    args = ['--input', str(source), '--output', str(output), '--delimiter', d['delimiter'],
            '--header-rows', str(d['header_rows']), '--encoding', d['encoding'],
            '--skip-leading', str(d['skip_leading']), '--footer-rows', str(d['footer_rows']),
            '--comment-prefix', d['comment_prefix'], '--decimal', d['decimal']]
    if d['delimiter'] == 'whitespace':
        args += ['--whitespace']
    for m in d['mappings']:
        args += ['--map', f"{m['column']}={m['name']}"]
        for key in ('scale', 'offset'):
            if m[key] != '':
                args += ['--' + key, f"{m['name']}={m[key]}"]
    return args


def inventory_names(data):
    root = Path(data['root'])
    limit, entry_limit = int(data['file_limit']), int(data['entry_limit'])
    if not 1 <= limit <= 64 or not 1 <= entry_limit <= 256:
        raise ValueError('Inventory limits exceed64 files /256 entries')
    expected = data.get('root_identity', 'absent')
    if not root.exists():
        if expected != 'absent': raise ValueError('Recipe inventory root was removed after admission')
        return dict(names=[], truncated=False, scanned_entries=0)
    st = root.lstat()
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise ValueError('Recipe inventory root must be an ordinary directory')
    if expected == 'absent' or [st.st_dev, st.st_ino] != [int(v) for v in TCL.splitlist(expected)]:
        raise ValueError('Recipe inventory root changed after admission')
    names, scanned, truncated = [], 0, False
    with os.scandir(root) as entries:
        for entry in entries:
            if scanned >= entry_limit:
                truncated = True
                break
            scanned += 1
            if entry.name.endswith('.ini'):
                if len(names) >= limit:
                    truncated = True
                    break
                names.append(entry.name)
    return dict(names=sorted(names), truncated=truncated, scanned_entries=scanned)


def execute(data, mode):
    if mode == 'inventory':
        expected_paths = {'core/tcl/importer_builder_api_v1.tcl', 'core/tcl/importer_builder_inventory_request.tcl', 'core/python/gxtxt_importer_builder_worker.py', 'app/configuration_manifest.tcl'}
        pins = dictionary(data['code_pins'])
        if set(pins) != expected_paths: raise ValueError('Inventory requires exact fixed owner source pins')
        def verify_code():
            for name, sha in pins.items():
                if digest((FRAMEWORK/name).read_bytes()) != sha: raise ValueError('Inventory source owner changed after admission')
        verify_code()
        names = inventory_names(data)
        request = dict(data, **names, python_executable=sys.executable)
        # One fixed trusted Tcl owner, in this same managed process/group. It
        # reuses actual Read/Describe/parseIni; no authored Tcl is evaluated.
        TCL.tk.wantobjects(False)
        TCL.setvar('argv0', '__gxtxt_csv_inventory_request__')
        TCL.call('source', str(FRAMEWORK / 'core/tcl/importer_builder_inventory_request.tcl'))
        result = TCL.call('::GX::_importerBuilderInventoryRun', tcl_result(request))
        verify_code()
        root = Path(data['root'])
        expected = data.get('root_identity', 'absent')
        if expected == 'absent':
            if root.exists(): raise ValueError('Recipe inventory root changed after admission')
        else:
            current = root.lstat()
            if not stat.S_ISDIR(current.st_mode) or [current.st_dev, current.st_ino] != [int(v) for v in TCL.splitlist(expected)]:
                raise ValueError('Recipe inventory root changed during read')
        return result
    if mode == 'ini':
        with source_open(data['source']) as ch:
            raw = ch.read(MAX_CONTROL + 1)
            if len(raw) > MAX_CONTROL: raise ValueError('Importer INI exceeds1MiB')
            return dict(text=raw.decode('utf-8', errors='strict'), ini_sha256=digest(raw))
    receipt = snapshot(data['definition'])
    if mode == 'snapshot':
        if data.get('source'):
            with source_open(data['source']) as ch:
                receipt['source_identity'] = identity(os.fstat(ch.fileno()))
        return receipt
    source = Path(data['source'])
    with source_open(source) as stream:
        before = identity(os.fstat(stream.fileno()))
        if data.get('expected_source_identity') and before != {k: int(v) for k, v in dictionary(data['expected_source_identity']).items()}:
            raise ValueError('Selected source changed after request admission')
        if data.get('expected_config_sha256') and data['expected_config_sha256'] != receipt['config_sha256']:
            raise ValueError('Immutable definition differs after request admission')
        if data.get('expected_parser_sha256') and data['expected_parser_sha256'] != receipt['parser_sha256']:
            raise ValueError('Bundled parser changed after request admission')
        raw, header, at_eof = prefix(stream, receipt['codec'])
        spec = importlib.util.spec_from_file_location('gxtxt_csv_canonicalizer', PARSER)
        parser = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(parser)
        if mode == 'header':
            source_check(source, stream, before)
            args = parser.arguments(parser_args(receipt['definition'], source, os.devnull))
            if args.delimiter == 'auto' and not at_eof and '\n' not in header and '\r' not in header:
                raise ValueError('Automatic delimiter needs a complete first physical line within64KiB; choose a delimiter')
            resolved = parser.resolve_delimiter(args, io.StringIO(header, newline=''))
            effective = dict(receipt['definition'], delimiter='whitespace' if args.whitespace else resolved)
            encoded = json.dumps(effective, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
            receipt.update(header_text=header[:32768], source_identity=before, prefix_sha256=digest(raw), digest_scope='prefix',
                           effective_config_json=encoded, effective_config_sha256=digest(encoded.encode()),
                           effective_delimiter=effective['delimiter'], bytes_read=len(raw), header_complete=at_eof and len(header)<=32768)
            return receipt
        root = Path(data['root'])
        st = root.lstat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_ISLNK(st.st_mode):
            raise ValueError('Missing owned temporary allocation')
        output = root / 'canonical.csv'
        if os.path.lexists(output):
            raise ValueError('Temporary output already exists')
        progress_path = root / 'progress.tcldict'
        def progress(phase, **extra):
            value = dict(phase=phase, **extra)
            tmp = root / 'progress.tmp'
            with tmp.open('w', encoding='utf-8') as ch:
                ch.write(tcl_result(value))
            tmp.replace(progress_path)
        args = parser.arguments(parser_args(receipt['definition'], source, output))
        progress(mode, bytes_read=0, total_bytes=before['size_bytes'], rows=0)
        source_sha = ''
        if mode == 'test':
            stream.seek(0)
            sha = hashlib.sha256()
            while chunk := stream.read(1048576):
                sha.update(chunk)
                progress('hash', bytes_read=stream.tell(), total_bytes=before['size_bytes'], rows=0)
            source_sha = sha.hexdigest()
            source_check(source, stream, before)
            # Reuse the same open inode, so a path replacement cannot substitute
            # different bytes between hash and parse; final stat rechecks both.
            stream.seek(0)
            decoded = io.TextIOWrapper(stream, encoding=receipt['codec'], errors='strict', newline='')
            # canonicalize owns its input context; preserve stream for final stat.
            class Borrowed:
                def __getattr__(self, name): return getattr(decoded, name)
                def __iter__(self): return iter(decoded)
                def __enter__(self): return decoded
                def __exit__(self, *_): return False
            class SampleSink:
                def __init__(self): self.text = ''; self.remaining = 65536
                def write(self, value):
                    encoded = value.encode('utf-8')
                    # encoded is valid UTF8; only a trailing cut scalar is omitted.
                    if self.remaining:
                        self.text += encoded[:self.remaining].decode('utf-8', errors='ignore')
                        self.remaining = max(0, self.remaining - len(encoded))
                    return len(value)
            sink = SampleSink()
            result = parser.canonicalize(args, input_stream=Borrowed(), output_stream=sink, progress=lambda rows: progress('parse', rows=rows, total_bytes=before['size_bytes']))
            decoded.detach()
            preview_source = ''.join(list(io.StringIO(header, newline=''))[:PREVIEW_LINES])
            complete = True
        else:
            # Only complete physical lines enter the parser on a truncated prefix;
            # never present a partial field/row as a successful scientific sample.
            lines = list(io.StringIO(header, newline=''))
            selected = lines[:PREVIEW_LINES]
            if selected and not at_eof and not selected[-1].endswith(('\r', '\n')):
                selected = selected[:-1]
            preview_source = ''.join(lines[:PREVIEW_LINES])
            complete = at_eof and len(lines) <= PREVIEW_LINES
            try:
                result = parser.canonicalize(args, input_stream=io.StringIO(''.join(selected), newline=''), max_rows=12)
            except (ValueError, SystemExit, __import__('csv').Error) as error:
                if complete: raise
                result = dict(rows=0, kinds=[], diagnostic=f'Bounded prefix cannot complete parser validation: {error}')
        source_check(source, stream, before)
        canonical_preview = sink.text if mode == 'test' else ''
        if output.is_file():
            with output.open('rb') as ch:
                canonical_preview = codecs.getincrementaldecoder('utf-8')(errors='strict').decode(ch.read(65536), final=False)
        progress('complete', bytes_read=before['size_bytes'] if mode == 'test' else len(raw), rows=result['rows'], total_bytes=before['size_bytes'])
        effective = dict(receipt['definition'], delimiter=result.get('delimiter', receipt['definition']['delimiter']))
        effective_json = json.dumps(effective, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        receipt.update(effective_config_json=effective_json, effective_config_sha256=digest(effective_json.encode()), operation=mode, status='PASS' if mode == 'test' else 'PREVIEW',
                       source_identity=before, source_sha256=source_sha, prefix_sha256=digest(raw),
                       digest_scope='full' if mode == 'test' else 'prefix', bytes_read=before['size_bytes'] if mode == 'test' else len(raw),
                       source_preview=preview_source, effective_delimiter=result.get('delimiter', receipt['definition']['delimiter']), header_text=header[:32768], complete=complete,
                       preview=canonical_preview, parser_result=result,
                       report=f"{mode}: rows={result['rows']}; codec={receipt['codec']}; " + ('complete validation' if mode == 'test' else 'bounded sample only'))
        return receipt


def main():
    if len(sys.argv) == 2 and sys.argv[1] in {'preview', 'test', 'inventory'}:
        request_process_group()
    import resource
    resource.setrlimit(resource.RLIMIT_AS, (536870912, 536870912))
    resource.setrlimit(resource.RLIMIT_CPU, (600, 600))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in {'snapshot', 'header', 'preview', 'test', 'ini', 'inventory'}:
            raise ValueError('Unknown fixed CSV Builder operation')
        raw = sys.stdin.read(MAX_CONTROL + 1)
        if len(raw.encode('utf-8')) > MAX_CONTROL:
            raise ValueError('CSV Builder request exceeds1MiB')
        response = dict(ok=True, result=execute(dictionary(raw), sys.argv[1]))
    except (Exception, SystemExit) as error:
        response = dict(ok=False, error=str(error), error_type=type(error).__name__)
    print(tcl_result(response), flush=True)


if __name__ == '__main__':
    main()
