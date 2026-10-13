# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only Script Execution provenance and bounded job-log projection.

Called by the existing host-only Job API. Never reads the current Script Registry
or follows a recorded arbitrary path; all files belong to one exact Session run.
"""
from pathlib import Path
import configparser, contextlib, hashlib, json, os, re, stat

LIMIT = 262144

def submission_identity(record):
    """Project absent legacy list columns from the immutable execution runtime."""
    try:
        with run_directory(record['session'], record['id']) as (fd, path):
            cfg = ini(fd, 'runtime.ini', []).get('config', {})
        for key, name in (('script_version', 'script_version'), ('script_id', 'script_id'),
                          ('script_name', 'script_name'), ('script_revision', 'script_revision')):
            if not record.get(key) and cfg.get(name): record[key] = cfg[name]
    except (OSError, ValueError):
        pass
    return record

def run_summaries(session, records):
    """Bounded captions for Session File Explorer; never a new run registry."""
    root = Path(session).resolve(strict=True)
    directory = root / 'analysis' / 'scripts'
    if (not directory.is_dir() or directory.is_symlink() or
            (root / 'analysis').is_symlink()): return []
    by_id = {r['id']: r for r in records if Path(r['session']).resolve() == root}
    result = []
    for p in sorted(directory.iterdir()):
        if len(result) >= 4096: break
        if not re.fullmatch(r'script-[A-Za-z0-9-]+', p.name): continue
        try:
            r = inspect_run(str(root), p.name, by_id.get(p.name), verify=False)
            result.append({k: r.get(k, '') for k in ('id', 'script_name', 'reference', 'state', 'started', 'finished', 'diagnostics', 'archived')})
        except (OSError, ValueError) as exc:
            result.append(dict(id=p.name, script_name='', diagnostics=[str(exc)]))
    return result

@contextlib.contextmanager
def run_directory(session, run_id):
    if not re.fullmatch(r'script-[A-Za-z0-9-]+', run_id):
        raise ValueError('Invalid Script Execution run ID')
    root = Path(session).resolve(strict=True)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for component in ('analysis', 'scripts', run_id):
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        if os.fstat(fd).st_uid != os.getuid():
            raise ValueError('Execution directory belongs to another account')
        yield fd, root / 'analysis' / 'scripts' / run_id
    finally:
        os.close(fd)

@contextlib.contextmanager
def run_file(fd, name):
    f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        s = os.fstat(f)
        if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or s.st_nlink != 1:
            raise ValueError('Execution file must be an owned regular file without links')
        with os.fdopen(f, 'rb', closefd=False) as stream:
            yield stream, s
    finally:
        os.close(f)

def ini(fd, name, diagnostics):
    try:
        with run_file(fd, name) as (f, s):
            if s.st_size > LIMIT:
                raise ValueError('Metadata exceeds bounded inspection limit')
            c = configparser.ConfigParser(interpolation=None, strict=False)
            c.read_string(f.read(LIMIT + 1).decode('utf-8'))
        return {section: dict(c[section]) for section in c.sections()}
    except (OSError, ValueError, UnicodeError, configparser.Error) as exc:
        diagnostics.append(f'{name}: unavailable or corrupt ({exc})')
        return {}

def inspect_run(session, run_id, record=None, verify=True):
    r = dict(record or {})
    r.update(id=run_id, session=str(Path(session).resolve()), archived=record is None)
    diagnostics = []
    with run_directory(session, run_id) as (fd, path):
        runtime = ini(fd, 'runtime.ini', diagnostics)
        report = ini(fd, 'execution.ini', diagnostics)
        cfg, execution = runtime.get('config', {}), report.get('execution', {})
        fields = {'reference': ('registered_script', 'script_reference'),
                  'script_id': ('script_id', 'script_id'),
                  'script_name': ('script_name', 'script_name'),
                  'script_version': ('script_version', 'script_version'),
                  'script_revision': ('script_revision', 'script_revision'),
                  'source_sha256': ('script_sha256', 'script_sha256'),
                  'language': ('script_language', 'language')}
        for key, (a, b) in fields.items():
            if not r.get(key):
                r[key] = cfg.get(a) or execution.get(b) or execution.get(key) or ''
        if record is None:
            r['state'] = execution.get('status', 'not recorded')
            if r['state'] == 'PASS': r['state'] = 'COMPLETED'
            for key, old in (('created', 'created'), ('started', 'started_at'),
                             ('finished', 'finished_at'), ('exit_code', 'exit_code')):
                r[key] = execution.get(key, execution.get(old, ''))
            for key in ('launched_at', 'session_name', 'session_id', 'peak_rss_bytes', 'peak_processes', 'peak_threads'):
                if execution.get(key): r[key] = execution[key]
            r['error'] = execution.get('reason', '')
            if r['state'] not in ('QUEUED','PREPARING','RUNNING','FINALIZING','COMPLETED','FAILED','CANCELLED','INTERRUPTED','not recorded'):
                diagnostics.append('execution.ini: execution state is corrupt or unsupported')
                r['state'] = 'not recorded'
        r.setdefault('session_name', '')
        r.setdefault('session_id', '')
        r.setdefault('parameters', report.get('parameters') or {k[len('script_parameter.'):]: v.get('value', '') for k, v in runtime.items() if k.startswith('script_parameter.')})
        r.setdefault('inputs', {k[len('job_input.'):]: v for k, v in runtime.items() if k.startswith('job_input.')})
        r.setdefault('output', runtime.get('job_output', {}))
        r['analysis_sources'] = {k: v for k, v in runtime.items() if k.startswith('analysis_source.') or k == 'bindings'}
        r['runtime_metadata'] = ini(fd, 'python_runtime.ini', []) if r['language'] == 'Python' else {}
        r['execution_report'] = execution
        r['output_dir'] = str(path)
        language = r['language']
        r['log_streams'] = 'stdout and stderr merged in the execution log'
        r['log_path'] = str(path / ('python.log' if language == 'Python' else 'octave.log')) if language in ('Python', 'Octave') else ''
        r['snapshot_validation'] = 'not verified'
        if verify and language in ('Python', 'Octave'):
            snapshot = 'registered_script.py' if language == 'Python' else 'registered_script.m'
            r['snapshot'] = str(path / snapshot)
            try:
                with run_file(fd, snapshot) as (f, s):
                    actual = hashlib.file_digest(f, 'sha256').hexdigest()
                r['snapshot_actual_sha256'] = actual
                r['snapshot_validation'] = ('verified' if actual == r['source_sha256'] else
                                            'SHA mismatch' if r['source_sha256'] else 'expected SHA not recorded')
            except (OSError, ValueError) as exc:
                r['snapshot_validation'] = f'unavailable ({exc})'
        # Receipt file is written only by the existing Publication authority.
        try:
            with run_file(fd, 'published_datasets.json') as (f, s):
                if s.st_size > LIMIT: raise ValueError('Publication receipt exceeds inspection limit')
                published = json.loads(f.read(LIMIT + 1))
            if not isinstance(published, list): raise ValueError('Invalid Publication receipt')
            r['published_datasets'] = published
        except FileNotFoundError:
            r['published_datasets'] = r.get('published_datasets', [])
        except (OSError, ValueError) as exc:
            diagnostics.append(f'Publication receipt unavailable or corrupt ({exc})')
            r['published_datasets'] = []
        r['diagnostics'] = diagnostics
    return r

def log_read(session, run_id, record, offset=0, count=65536, tail=False):
    offset, count = int(offset), int(count)
    tail = bool(int(tail))
    if offset < 0 or not 4 <= count <= LIMIT:
        raise ValueError('Log range requires offset >= 0 and count 4..262144 bytes')
    language = record.get('language', '')
    if language not in ('Python', 'Octave'):
        return dict(available=False, diagnostic='Log unavailable: execution language not recorded', content='', offset=offset, next_offset=offset, size=0, eof=True)
    name = 'python.log' if language == 'Python' else 'octave.log'
    try:
        with run_directory(session, run_id) as (fd, path), run_file(fd, name) as (f, s):
            size = s.st_size
            if tail: offset = max(0, size - count)
            if offset > size: raise ValueError('Log shrank or requested offset is outside retained data')
            f.seek(offset)
            raw = f.read(min(count, size - offset))
            # Page boundaries never split a valid UTF-8 codepoint. A tail starts
            # on the next complete codepoint; invalid source bytes stay diagnosed.
            if offset:
                while raw and raw[0] & 0xc0 == 0x80:
                    raw = raw[1:]; offset += 1
            if offset + len(raw) < size:
                for n in range(1, min(3, len(raw)) + 1):
                    try: raw.decode('utf-8'); break
                    except UnicodeDecodeError as exc:
                        if exc.reason == 'unexpected end of data': raw = raw[:exc.start]
                        else: break
            next_offset = offset + len(raw)
            diagnostic = ''
            try: content = raw.decode('utf-8')
            except UnicodeDecodeError:
                content = raw.decode('utf-8', errors='replace')
                diagnostic = 'Invalid UTF-8 bytes shown as replacement characters'
            return dict(available=True, diagnostic=diagnostic, content=content, offset=offset,
                        next_offset=next_offset, size=size, eof=next_offset >= size,
                        content_base64=__import__('base64').b64encode(raw).decode('ascii'),
                        receipt=f'{s.st_dev}:{s.st_ino}:{s.st_mtime_ns}:{size}', path=str(path / name))
    except (OSError, ValueError) as exc:
        return dict(available=False, diagnostic=f'Log unavailable, expired or unsafe: {exc}',
                    content='', offset=offset, next_offset=offset, size=0, eof=True)
