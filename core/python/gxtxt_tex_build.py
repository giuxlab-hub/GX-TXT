# SPDX-License-Identifier: GPL-3.0-or-later
"""Native TeX worker for Script Job; canonical documents remain CORE-owned.

The caller stages an immutable source/assets snapshot in a Resource Management
allocation. This worker neither reads a Session nor publishes a document. The
existing auxiliary request owner provides process-group cancellation, bounded
native execution, descendant reaping and the single Tcl result protocol.
"""
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tkinter

from gxtxt_job_supervisor import auxiliary_request_run, request_process_group, tcl_result


OUTPUT = '.gxtxt-build'
INPUT_LIMIT = 268435456
PDF_LIMIT = 134217728
LOG_LIMIT = 8388608
TEX_WARNING = re.compile(r'(?:LaTeX(?: [A-Za-z]+)?|Package .+?|Class .+?) Warning:|Overfull \\[hv]box|Underfull \\[hv]box')


def dictionary(interpreter, value):
    parts = interpreter.splitlist(value)
    if len(parts) % 2 or len(set(parts[::2])) != len(parts) // 2:
        raise ValueError('Malformed or duplicate TeX request keys')
    return dict(zip(parts[::2], parts[1::2]))


def relative_name(value):
    path = PurePosixPath(value)
    if (not value or path.is_absolute() or str(path) != value or
            any(part in {'', '.', '..', OUTPUT} for part in path.parts) or
            '\\' in value or any(ord(c) < 32 for c in value)):
        raise ValueError('Project asset needs a normalized relative filename')
    return path


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            result.update(block)
    return result.hexdigest()


def verify_inputs(root, expected):
    actual = {}
    total = 0
    for name, expected_sha in expected.items():
        relative = relative_name(name)
        path = root
        for part in relative.parts:
            path = path / part
            if path.is_symlink():
                raise ValueError('A staged TeX input was replaced by a symlink')
        if not path.is_file() or not re.fullmatch('[0-9a-f]{64}', expected_sha):
            raise ValueError('Missing or invalid staged TeX input')
        total += path.stat().st_size
        if total > INPUT_LIMIT:
            raise ValueError('Staged TeX inputs exceed the 256 MiB request budget')
        actual[name] = digest(path)
        if actual[name] != expected_sha:
            raise ValueError('TeX source/asset snapshot changed: ' + name)
    return actual


def _native_log_source_lines(text, names):
    """Track native input scopes; only exact staged filenames authorize links.

    TeX's parenthesized input transcript includes distribution files too. A line
    in shellesc.sty is not a line in main.tex. Unrecognized/wrapped scopes are
    deliberately unlinked. Diagnostic prose cannot open an input-file scope.
    """
    scopes = []
    for line in text.splitlines():
        if re.match(r'^This is (?:pdfTeX|XeTeX|Lua(?:HB)?TeX)\b', line):
            scopes.clear()
        diagnostic = TEX_WARNING.search(line)
        prefix = line[:diagnostic.start()] if diagnostic else line
        # Error/missing-glyph prose is not an input transcript either.
        if line.startswith(('! ', 'Missing character:')):
            prefix = ''
        index = 0
        while index < len(prefix):
            char = prefix[index]
            if char == '(':
                tail = prefix[index + 1:]
                token = re.match(r'"([^"\r\n]+)"|([^\s()]+)', tail)
                filename = ''
                if token:
                    raw = token.group(1) or token.group(2)
                    candidate = raw[2:] if raw.startswith('./') else raw
                    if candidate in names:
                        filename = candidate
                        # Parentheses in a quoted filename are not scope marks.
                        index += token.end()
                    elif re.match(r'^(?:/|\./|\.gxtxt-build/)', raw):
                        index += token.end()
                scopes.append(filename)
            elif char == ')':
                if scopes:
                    scopes.pop()
            index += 1
        yield line, scopes[-1] if scopes else ''


def diagnostics(text, names):
    """Expose native engine locations; never infer a successful TeX parse."""
    rows = []
    for line, native_source in _native_log_source_lines(text, names):
        match = re.match(r'^(?:\./)?(.+?\.tex):(\d+):\s*(.*)$', line)
        if match:
            name, number, message = match.groups()
            rows.append(dict(file=name, line=int(number), column=1,
                             severity='warning' if TEX_WARNING.search(message) else 'error', message=message,
                             source_link=name in names))
        elif line.startswith('! '):
            rows.append(dict(file='', line=0, column=0, severity='error',
                             message=line[2:], source_link=False))
        elif line.startswith('Missing character:'):
            # A native engine can exit successfully while omitting a glyph.
            # Surface the exact warning without guessing a project source line.
            rows.append(dict(file='', line=0, column=0, severity='warning',
                             message=line, source_link=False))
        elif TEX_WARNING.search(line):
            location = re.search(r'on input line (\d+)', line)
            # Only the native open-input scope and this immutable staged input
            # manifest can authenticate the filename. Preserve unavailable
            # locations for distribution files, ambiguous scopes or no line.
            linked = bool(location and native_source)
            rows.append(dict(file=native_source if linked else '',
                             line=int(location.group(1)) if location else 0,
                             column=1 if linked else 0, severity='warning',
                             message=line, source_link=linked))
        if len(rows) >= 2000:
            break
    return rows


def executable(value):
    path = Path(value)
    if not path.is_absolute() or not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError('TeX tools must be resolved by the configured runtime owner')
    return str(path)


def build(request, interpreter):
    root = Path(request['directory'])
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise ValueError('An existing managed TeX allocation is required')
    expected = dictionary(interpreter, request['inputs'])
    if not expected or len(expected) > 4096 or 'main.tex' not in expected:
        raise ValueError('A bounded source/assets snapshot including main.tex is required')
    before = verify_inputs(root, expected)
    # An allocation is single-use. Unexpected files cannot become implicit input.
    actual_files = set()
    for directory, directories, files in os.walk(root, followlinks=False):
        if any((Path(directory) / name).is_symlink() for name in directories + files):
            raise ValueError('Symlinks are not staged TeX assets')
        actual_files.update(str((Path(directory) / name).relative_to(root)) for name in files)
    if actual_files != set(expected):
        raise ValueError('Managed TeX allocation contains unregistered inputs')
    runtime = executable(request['runtime'])
    driver = request['driver']
    engine = request.get('engine', 'pdflatex')
    if driver not in {'latexmk', 'pdflatex', 'xelatex', 'lualatex'} or engine not in {'pdflatex', 'xelatex', 'lualatex'}:
        raise ValueError('Unsupported configured TeX driver/engine identity')
    (root / OUTPUT).mkdir(mode=0o700)
    os.chdir(root)
    environment = dict(os.environ)
    # Match TeX Live's normal input policy: Lua's font loader opens packaged
    # Unicode tables by their kpathsea-resolved absolute paths. Source integrity
    # is checked separately against the caller's staged immutable manifest.
    environment.update(openin_any='a', openout_any='p', shell_escape='f',
                       TEXMFOUTPUT=str(root / OUTPUT))
    # Lua's font loader tests cache writability through native TeX I/O. A
    # caller's absolute cache outside TEXMFOUTPUT can be rejected even when its
    # POSIX permissions allow writes. Keep generated font/cache data in this
    # existing managed build allocation, alongside other compiler outputs.
    cache = root / OUTPUT / 'texmf-cache'
    cache.mkdir(mode=0o700)
    for key in ('TEXMFCACHE', 'TEXMFVAR', 'TEXMFCONFIG'):
        environment[key] = str(cache)
    # Do not inherit a caller-supplied source search path or preload TeX options.
    for key in ('TEXINPUTS', 'BIBINPUTS', 'BSTINPUTS', 'TEXMF_OUTPUT_DIRECTORY'):
        environment.pop(key, None)
    native_options = ['-no-shell-escape', '-interaction=nonstopmode',
                      '-halt-on-error', '-file-line-error', '-recorder']
    if driver == 'latexmk':
        mode = {'pdflatex': '-pdf', 'xelatex': '-pdfxe', 'lualatex': '-pdflua'}[engine]
        command = [runtime, '-norc', mode, '-outdir=' + OUTPUT, *native_options]
        if engine == 'lualatex':
            # TeX Live's standard luaotfload explicitly rejects --safer.
            # Native no-shell-escape and the managed build scope still apply.
            command += ['-latexoption=--nosocket']
    else:
        command = [runtime, '-output-directory=' + OUTPUT, *native_options]
        if driver == 'lualatex':
            command += ['--nosocket']
    command += ['main.tex']
    invocations = []
    combined = []
    log_path = root / OUTPUT / 'gxtxt-native-output.txt'
    log_path.write_text('', encoding='utf-8')
    convergence = 'driver_managed' if driver == 'latexmk' else 'not_checked'
    last_engine_invocation = 0

    def run(arguments, *, bibliography_directory=None):
        nonlocal last_engine_invocation
        remaining = LOG_LIMIT - sum(len(item.encode('utf-8')) for item in combined)
        if remaining < 1024:
            raise ValueError('Native TeX diagnostics exceed the 8 MiB request budget')
        native_environment = environment
        if bibliography_directory is not None:
            # BibTeX's ordinary output policy rejects a dot-directory in its
            # output filename. Run in the already owned output directory with
            # basename main; resolve explicit project bibliography assets from
            # the staged root, followed by the distribution's normal defaults.
            native_environment = dict(environment,
                                      BIBINPUTS=str(root) + os.pathsep,
                                      BSTINPUTS=str(root) + os.pathsep)
            os.chdir(bibliography_directory)
        try:
            result = auxiliary_request_run(arguments, timeout_seconds=180,
                                           max_bytes=remaining,
                                           environment=native_environment)
        finally:
            os.chdir(root)
        combined.append(result['output'])
        # Preserve every completed native invocation even if a later dependency
        # or process fails before the result protocol can be completed.
        with log_path.open('a', encoding='utf-8') as stream:
            stream.write(result['output'] + '\n')
        invocations.append(dict(command=arguments, returncode=result['returncode'],
                                working_directory=str(bibliography_directory or root),
                                elapsed_ms=result['elapsed_ms']))
        if arguments == command:
            last_engine_invocation = len(invocations)
        return result

    result = run(command)
    if driver != 'latexmk' and result['returncode'] == 0:
        # Native engines do not own bibliography orchestration. Use their actual
        # emitted control files and runtime-owner-resolved bibliography tools.
        bcf = root / OUTPUT / 'main.bcf'
        aux = root / OUTPUT / 'main.aux'
        if bcf.exists():
            tool = executable(request.get('biber', ''))
            result = run([tool, '--input-directory=' + OUTPUT,
                          '--output-directory=' + OUTPUT, 'main'])
        elif aux.exists() and b'\\bibdata{' in aux.read_bytes():
            tool = executable(request.get('bibtex', ''))
            result = run([tool, 'main'], bibliography_directory=root / OUTPUT)
        if result['returncode'] == 0:
            previous = None
            # Actual aux/toc/out bytes, not a guessed document structure, drive
            # convergence; unresolved references remain genuine diagnostics.
            for _ in range(5):
                state = {p.name: digest(p) for p in (root / OUTPUT).iterdir()
                         if p.is_file() and p.suffix in {'.aux', '.toc', '.out'}}
                if state == previous:
                    convergence = 'stable_auxiliary_files'
                    break
                previous = state
                result = run(command)
                if result['returncode'] != 0:
                    break
            else:
                state = {p.name: digest(p) for p in (root / OUTPUT).iterdir()
                         if p.is_file() and p.suffix in {'.aux', '.toc', '.out'}}
                convergence = ('stable_auxiliary_files' if state == previous
                               else 'pass_limit_reached')
    after = verify_inputs(root, expected)
    # The engine's current native log is replaced on each TeX pass. Earlier
    # unresolved-reference warnings remain in the complete transcript, without
    # being mislabeled as warnings about the final typeset document.
    current_log = root / OUTPUT / 'main.log'
    if current_log.is_file() and not current_log.is_symlink():
        with current_log.open('rb') as stream:
            current_bytes = stream.read(LOG_LIMIT + 1)
        if len(current_bytes) > LOG_LIMIT:
            raise ValueError('Final native TeX log exceeds the 8 MiB request budget')
        text = current_bytes.decode('utf-8', errors='replace')
        diagnostic_scope = 'final_native_engine_log'
    else:
        text = result['output']
        diagnostic_scope = 'last_native_driver_output'
    current_diagnostics = diagnostics(text, expected)
    for row in current_diagnostics:
        row['scope'] = diagnostic_scope
        row['native_invocation'] = (last_engine_invocation if diagnostic_scope == 'final_native_engine_log'
                                    else len(invocations))
    if convergence == 'pass_limit_reached':
        current_diagnostics.append(dict(file='', line=0, column=0,
                                        severity='warning', source_link=False,
                                        scope='core_convergence_check',
                                        native_invocation=last_engine_invocation,
                                        message='Native auxiliary files did not stabilize within six engine passes'))
    if result['returncode'] != 0:
        # Bibliography/driver errors may occur after the most recent engine log.
        # Retain their exact last output separately in the complete transcript.
        current_diagnostics.append(dict(file='', line=0, column=0,
                                        severity='error', source_link=False,
                                        scope='native_driver_exit_status',
                                        native_invocation=len(invocations),
                                        message='Native driver exited with status ' + str(result['returncode'])))
    pdf = root / OUTPUT / 'main.pdf'
    valid_pdf = False
    if pdf.is_file() and not pdf.is_symlink() and 0 < pdf.stat().st_size <= PDF_LIMIT:
        with pdf.open('rb') as stream:
            valid_pdf = stream.read(5) == b'%PDF-'
    success = result['returncode'] == 0 and valid_pdf
    return dict(status='succeeded' if success else 'failed', source_revision=request['source_revision'],
                session_token=request['session_token'], owner_generation=request['owner_generation'],
                inputs=before, inputs_after=after, source_integrity=before == after,
                configured_runtime=runtime, driver=driver, engine=engine if driver == 'latexmk' else driver,
                invocations=invocations, diagnostics=current_diagnostics,
                diagnostics_scope=diagnostic_scope, convergence=convergence,
                log_path=str(log_path), log_sha256=digest(log_path),
                log_bytes=log_path.stat().st_size,
                pdf_path=str(pdf) if success else '', pdf_sha256=digest(pdf) if success else '',
                pdf_bytes=pdf.stat().st_size if success else 0,
                export_authority='CORE revision/session/owner checks required')


def main():
    request_process_group()
    interpreter = tkinter.Tcl()
    raw = sys.stdin.read(2097153)
    if len(raw.encode('utf-8')) > 2097152:
        raise ValueError('TeX build request exceeds 2 MiB')
    request = dictionary(interpreter, raw)
    print(tcl_result(dict(ok=True, result=build(request, interpreter))), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(tcl_result(dict(ok=False, error=str(error))), flush=True)
        raise SystemExit(1)
