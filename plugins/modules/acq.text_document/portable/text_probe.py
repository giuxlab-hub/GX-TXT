# SPDX-License-Identifier: GPL-3.0-or-later
"""Framework-independent, non-executing text/code recognition and inspection.

CORE EXTRACTION CANDIDATE: this file and languages.json form a portable unit.
No GX-TXT, Tcl, GUI, Session, registry or module identity appears in this layer.
`analyze_file` returns plain Python data. Optional callbacks report byte progress,
check cancellation and copy the *same* bytes being checked. The caller owns any
output and transaction. No source code is imported, compiled, evaluated or run.

Language identification is an ordered set of hints, NOT syntax validation.
Ambiguity and conflicts remain explicit; confidence labels are not probabilities.
Encoding detection is deliberately conservative: BOM, Python coding cookie,
then strict UTF-8. Other encodings require the caller's explicit selection.
"""
from __future__ import annotations

import codecs
import io
import json
import re
import shlex
import tokenize
from pathlib import Path
from typing import Any, Callable

BLOCK = 256 * 1024
SAMPLE_LIMIT = 256 * 1024
HEAD_CHARS = 32 * 1024
TAIL_CHARS = 4096
PREVIEW_CHARS = 12000
PREVIEW_LINES = 80
CATALOG = json.loads(Path(__file__).with_name('languages.json').read_text(encoding='utf-8'))
LANGUAGES = CATALOG['languages']
ENCODINGS = ('auto', 'utf-8', 'utf-8-sig', 'ascii', 'utf-16', 'utf-16-le',
             'utf-16-be', 'utf-32', 'utf-32-le', 'utf-32-be', 'cp1252', 'iso-8859-1')


class TextError(ValueError):
    """The source cannot be accepted as a text document."""


class EncodingNeeded(TextError):
    """The source needs an explicit encoding before full validation/import."""


class Cancelled(TextError):
    """The caller requested cancellation at a chunk boundary."""


def language_id(name: str) -> str | None:
    token = name.strip().lower()
    if token in LANGUAGES:
        return token
    for key, item in LANGUAGES.items():
        if token in item['aliases']:
            return key
    return None


def filename_hint(filename: str) -> tuple[str, str]:
    # Exact filenames precede extensions: CMakeLists.txt is not plain text.
    name = Path(filename).name
    for key, item in LANGUAGES.items():
        if name.casefold() in (f.casefold() for f in item['filenames']):
            return key, 'filename'
    suffix = Path(name).suffix
    if suffix in CATALOG['case_sensitive_extensions']:
        return CATALOG['case_sensitive_extensions'][suffix], 'extension'
    for key, item in LANGUAGES.items():
        if suffix.lower() in item['extensions']:
            return key, 'extension'
    return 'unknown', 'none'


def shebang_hint(head: str) -> tuple[str, str]:
    first = head.split('\n', 1)[0].lstrip('\ufeff').rstrip('\r')[:2048]
    if not first.startswith('#!'):
        return '', ''
    try:
        words = shlex.split(first[2:].strip())
    except ValueError:
        return '', first
    if not words:
        return '', first
    name = words[0].replace('\\', '/').rsplit('/', 1)[-1]
    if name == 'env':
        # Handle normal env, env -S, simple options and NAME=value assignments.
        words = words[1:]
        index = 0
        while index < len(words):
            word = words[index]
            if word in ('-u', '--unset', '-C', '--chdir'):
                index += 2
                continue
            if word == '--':
                index += 1
                break
            if word.startswith('-') or '=' in word:
                index += 1
                continue
            break
        if index >= len(words):
            return '', first
        name = words[index].replace('\\', '/').rsplit('/', 1)[-1]
    name = name.removesuffix('.exe')
    for key, item in LANGUAGES.items():
        for interpreter in item['interpreters']:
            if re.fullmatch(re.escape(interpreter) + r'(?:[0-9]+(?:\.[0-9]+)*)?', name, re.I):
                # A common Tcl launcher starts as sh and re-execs tclsh/wish.
                # Read it as a hint only; never execute the launcher.
                if key in {'sh', 'bash'} and re.search(
                        r'(?m)^\s*exec\s+(?:\S*/)?(?:tclsh|wish)[\d.]*\s+["\']?\$0',
                        '\n'.join(head.split('\n')[:8])):
                    return 'tcl', first + ' (Tcl shell launcher)'
                return key, first
    return '', first


def modeline_hint(head: str, tail: str) -> str:
    # Modelines are metadata hints only. Never apply editor commands/options.
    lines = head.splitlines()[:5] + tail.splitlines()[-5:]
    for line in lines:
        line = line[:2000]
        match = re.search(r'-\*-\s*(?:mode:\s*)?([\w+.-]+)(?:\s*;|\s*-\*-)', line, re.I)
        if not match:
            match = re.search(r'(?:vi|vim|ex):.*?\b(?:ft|filetype|syntax)=([\w+.-]+)', line, re.I)
        if match and (key := language_id(match.group(1))):
            return key
    return ''


def content_hint(head: str, hint: str) -> str:
    """Small, deliberately specific signatures; no generic keyword scoring."""
    if hint in {'matlab-octave', 'c-cpp', 'unknown', 'plaintext'}:
        if re.search(r'(?m)^\s*@(?:interface|implementation|protocol)\b', head):
            return 'objective-c'
    if hint == 'matlab-octave':
        if re.search(r'(?m)^\s*(?:endfunction|endif|endfor|endwhile|unwind_protect|pkg\s+load)\b', head):
            return 'octave'
    if hint == 'c-cpp':
        if re.search(r'(?m)^\s*(?:namespace\s+\w+\s*\{|template\s*<|class\s+\w+\s*[:{])', head):
            return 'cpp'
    if hint == 'perl-prolog':
        if re.search(r'(?m)^\s*(?:use\s+(?:strict|warnings)\s*;|my\s+[$@%])', head):
            return 'perl'
        if re.search(r'(?m)^\s*:-\s*(?:module|use_module|initialization)\s*\(', head):
            return 'prolog'
    if hint not in {'unknown', 'plaintext'}:
        return ''
    if re.search(r'(?m)^\s*(?:proc\s+\S+\s*\{[^\n]*\}\s*\{|namespace\s+eval\s+\S+\s*\{)', head):
        return 'tcl'
    if (re.search(r'(?m)^\s*(?:async\s+)?def\s+\w+\([^\n]*\)(?:\s*->[^\n:]+)?\s*:', head)
            and re.search(r'(?m)^\s*(?:from\s+\S+\s+import\b|import\s+\w+|return\b)', head)):
        return 'python'
    if re.match(r'\s*<\?php\b', head):
        return 'php'
    if re.match(r'\s*<\?xml\s', head):
        return 'xml'
    if re.match(r'\s*<!doctype\s+html\b', head, re.I):
        return 'html'
    return ''


def detect_language(filename: str, head: str, tail: str = '', override: str = 'auto') -> dict[str, Any]:
    hint, method = filename_hint(filename)
    interpreter, shebang = shebang_hint(head)
    modeline = modeline_hint(head, tail)
    content = content_hint(head, hint)
    warnings: list[str] = []
    chosen, confidence, evidence = hint, ('medium' if hint != 'unknown' else 'none'), filename
    if content:
        chosen, method, confidence, evidence = content, 'content', 'medium', 'Specific source-text signature'
    if hint in CATALOG['ambiguities'] and not content:
        method, confidence = 'ambiguous_extension', 'low'
    if modeline:
        chosen, method, confidence, evidence = modeline, 'modeline', 'high', 'Editor language hint (not executed)'
    if interpreter:
        if modeline and interpreter != modeline:
            warnings.append(f'Shebang suggests {interpreter}, while the modeline suggests {modeline}; the shebang takes precedence.')
        chosen, method, confidence, evidence = interpreter, 'shebang', 'high', shebang
    if chosen != hint and hint not in {'unknown', 'plaintext', chosen}:
        compatible = (chosen in CATALOG['ambiguities'].get(hint, [])
                      or {chosen, hint} <= {'sh', 'bash', 'zsh', 'fish'})
        if not compatible:
            warnings.append(f'Language hints disagree: filename suggests {hint}; {method} suggests {chosen}.')
    detected = chosen
    candidates = CATALOG['ambiguities'].get(chosen, [])
    if candidates:
        warnings.append(f'Ambiguous language: {", ".join(candidates)}. Use Language override or edit code.language after import.')
    if chosen == 'unknown':
        # Unknown extension remains unknown; it is still a valid text document.
        warnings.append('No reliable language hint was found. Imported as a text document with code.language=unknown.')
    if override.strip().lower() not in {'', 'auto'}:
        normalized = language_id(override)
        if normalized is None:
            raise TextError(f'Unknown Language override: {override}. Choose a catalog language ID.')
        chosen, method, confidence, evidence = normalized, 'manual', 'explicit', 'User-selected import setting'
        if chosen != detected:
            warnings.append(f'Manual language {chosen} overrides detected language {detected}.')
    item = LANGUAGES[chosen]
    return dict(id=chosen, label=item['label'], category=item['category'], method=method,
                confidence=confidence, evidence=evidence, detected=detected, candidates=candidates,
                shebang=shebang, warnings=warnings, version=CATALOG['detection_version'])


def _encoding(sample: bytes, filename: str, selected: str) -> tuple[str, str, str]:
    bom = ''
    detected_bom = ''
    for signature, codec, label in (
        (codecs.BOM_UTF32_LE, 'utf-32', 'UTF-32LE'),
        (codecs.BOM_UTF32_BE, 'utf-32', 'UTF-32BE'),
        (codecs.BOM_UTF8, 'utf-8-sig', 'UTF-8'),
        (codecs.BOM_UTF16_LE, 'utf-16', 'UTF-16LE'),
        (codecs.BOM_UTF16_BE, 'utf-16', 'UTF-16BE'),
    ):
        if sample.startswith(signature):
            detected_bom, bom = codec, label
            break
    selected = selected.strip().lower() or 'auto'
    if selected != 'auto':
        # Stored Python-cookie codecs may be outside the GUI's common choices.
        # Resolve only built-in bytes-to-text codecs; never a source-side codec.
        try:
            info = codecs.lookup(selected)
            if not getattr(info, '_is_text_encoding', False) or info.incrementaldecoder is None:
                raise LookupError(selected)
        except LookupError as exc:
            raise TextError(f'Unsupported text encoding selection: {selected}.') from exc
        codec = selected
        # Consume a matching BOM in the decoded view only. Source bytes are
        # copied unchanged. Reject conflicting BOM/explicit-endian declarations.
        allowed = {'UTF-8': {'utf-8', 'utf-8-sig'}, 'UTF-16LE': {'utf-16', 'utf-16-le'},
                   'UTF-16BE': {'utf-16', 'utf-16-be'}, 'UTF-32LE': {'utf-32', 'utf-32-le'},
                   'UTF-32BE': {'utf-32', 'utf-32-be'}}
        if bom:
            if selected not in allowed[bom]:
                raise TextError(f'Encoding selection {selected} conflicts with the {bom} BOM.')
            codec = detected_bom
        return codec, 'manual', bom or 'none'
    python_hint = filename_hint(filename)[0] == 'python'
    shebang, _ = shebang_hint(sample[:4096].decode('ascii', errors='replace'))
    python_hint = python_hint or shebang == 'python'
    if python_hint and (detected_bom in {'', 'utf-8-sig'}):
        # tokenize only reads up to two lines; it never parses/runs the program.
        try:
            # Only feed complete header lines to tokenize. A giant first line
            # may end mid-codepoint at the preview boundary. With no complete
            # line/cookie, UTF-8 is validated incrementally below instead.
            parts = sample.splitlines(keepends=True)[:2]
            if parts and not parts[-1].endswith((b'\n', b'\r')) and len(sample) == SAMPLE_LIMIT:
                parts[-1] = re.sub(br'[\x80-\xff]+$', b'', parts[-1])
            header = b''.join(parts)
            codec, _ = tokenize.detect_encoding(io.BytesIO(header).readline)
            codec_info = codecs.lookup(codec)
            if not getattr(codec_info, '_is_text_encoding', False):
                raise EncodingNeeded('Python coding cookie does not name a text encoding.')
            cookie = re.search(br'coding[:=]\s*([-\w.]+)', b'\n'.join(sample.split(b'\n', 2)[:2]))
            return codec, ('python_cookie' if cookie else ('bom' if bom else 'utf8_validation')), bom or 'none'
        except (SyntaxError, LookupError) as exc:
            raise EncodingNeeded(f'Python source encoding could not be established: {exc}. Select Encoding explicitly.') from exc
    if detected_bom:
        return detected_bom, 'bom', bom
    if b'\0' in sample:
        raise EncodingNeeded('NUL bytes without a BOM: possible binary data or BOM-less UTF-16/32. Select the correct Encoding explicitly; automatic import will not guess.')
    return 'utf-8', 'utf8_validation', 'none'


class _Stats:
    """Counts CR, LF and CRLF exactly, including sequences across chunks."""
    def __init__(self) -> None:
        self.characters = self.cr = self.lf = self.crlf = self.controls = self.tabs = 0
        self.last = ''
        self.head = ''
        self.tail = ''

    def feed(self, value: str) -> None:
        if not value:
            return
        if '\0' in value:
            raise TextError('Decoded text contains NUL characters; binary data is not a text/code Dataset.')
        self.crlf += value.count('\r\n') + int(self.last == '\r' and value.startswith('\n'))
        self.cr += value.count('\r')
        self.lf += value.count('\n')
        self.tabs += value.count('\t')
        # Reject binary/control-heavy inputs after strict decoding. Form feed
        # is a valid source-text separator. A few ANSI log escapes are retained
        # in the payload and escaped only in the read-only preview.
        self.controls += len(re.findall(r'[\x01-\x08\x0b\x0e-\x1f\x7f-\x9f]', value))
        self.characters += len(value)
        self.last = value[-1]
        if len(self.head) < HEAD_CHARS:
            self.head += value[:HEAD_CHARS-len(self.head)]
        self.tail = (self.tail + value)[-TAIL_CHARS:]

    def result(self) -> dict[str, Any]:
        if self.controls * 100 > max(1, self.characters):
            raise TextError('Decoded source contains too many binary/control characters to be accepted as text.')
        endings = {'CRLF': self.crlf, 'LF': self.lf-self.crlf, 'CR': self.cr-self.crlf}
        present = [name for name, count in endings.items() if count]
        return dict(character_count=self.characters,
                    line_count=self.cr+self.lf-self.crlf+int(self.characters > 0 and self.last not in {'\r', '\n'}),
                    newline_style=('mixed' if len(present) > 1 else (present[0] if present else 'none')),
                    newline_counts=endings, has_final_newline=self.last in {'\r', '\n'},
                    tab_count=self.tabs, control_count=self.controls, empty=self.characters == 0)


def safe_preview(value: str) -> tuple[str, bool]:
    # Display only: newline presentation is normalized; authoritative bytes are
    # never changed. Escape controls and bidi overrides in the read-only snippet.
    value = value.replace('\r\n', '\n').replace('\r', '\n')
    lines = value.split('\n')
    clipped = len(value) > PREVIEW_CHARS or len(lines) > PREVIEW_LINES
    value = '\n'.join(lines[:PREVIEW_LINES])[:PREVIEW_CHARS]
    value = re.sub(r'[\x00-\x08\x0b\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]',
                   lambda m: f'\\u{ord(m.group(0)):04x}', value)
    return value, clipped


def analyze_file(path: str | Path, *, original_name: str | None = None,
                 encoding: str = 'auto', language: str = 'auto', full: bool = False,
                 on_chunk: Callable[[bytes], Any] | None = None,
                 progress: Callable[[int, int, str], Any] | None = None,
                 cancel: Callable[[], bool] | None = None) -> dict[str, Any]:
    """Inspect text without executing it; stream the entire file when full=True.

    Preview scans are bounded to SAMPLE_LIMIT bytes. Statistics explicitly say
    whether they cover the whole file. Import must use full=True. When provided,
    on_chunk receives exactly the original bytes, not re-encoded text. It must
    only write to a caller-owned temporary output. The caller removes that output
    on any exception. full=False must never be used to validate an import.
    """
    source = Path(path)
    if not source.is_file():
        raise TextError('The source is not a regular file.')
    before = source.stat()
    name = original_name or source.name
    stats = _Stats()
    read_bytes = 0
    ascii_only = True
    if cancel and cancel():
        raise Cancelled('Text import cancelled.')
    with source.open('rb') as stream:
        first = stream.read(min(BLOCK, SAMPLE_LIMIT))
        for signature in (b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff', b'GIF87a', b'GIF89a',
                          b'%PDF-', b'PK\x03\x04', b'PK\x05\x06', b'\x1f\x8b', b'\x7fELF',
                          b'\x89HDF\r\n\x1a\n', b'SQLite format 3\0', b'\xfd7zXZ\0'):
            if first.startswith(signature):
                raise TextError('Binary/container signature detected. Use the appropriate acquisition module, not Text and Source Code Import.')
        codec, encoding_method, bom = _encoding(first, name, encoding)
        try:
            decoder = codecs.getincrementaldecoder(codec)(errors='strict')
        except LookupError as exc:
            raise EncodingNeeded(f'No decoder is available for {codec}.') from exc
        chunk = first
        while True:
            if cancel and cancel():
                raise Cancelled('Text import cancelled.')
            read_bytes += len(chunk)
            try:
                value = decoder.decode(chunk, final=False)
            except UnicodeError as exc:
                raise EncodingNeeded(f'Source is not valid {codec}: {exc}. Select the correct Encoding; source bytes will not be altered.') from exc
            if not isinstance(value, str):
                raise TextError('The selected codec did not decode to Unicode text.')
            stats.feed(value)
            ascii_only = ascii_only and all(b < 128 for b in chunk)
            if on_chunk is not None and chunk:
                on_chunk(chunk)
            if progress:
                progress(read_bytes, before.st_size, 'validate-and-preserve' if on_chunk else 'inspect')
            if not full or not chunk:
                break
            chunk = stream.read(BLOCK)
        complete = read_bytes == before.st_size
        if complete:
            try:
                stats.feed(decoder.decode(b'', final=True))
            except UnicodeError as exc:
                raise EncodingNeeded(f'Incomplete or invalid {codec} sequence at the end of the source.') from exc
    after = source.stat()
    signature = lambda s: (s.st_size, s.st_mtime_ns, s.st_ino)
    if signature(before) != signature(after) or (full and not complete):
        raise TextError('Source changed during text inspection/preservation. Retry using a stable source snapshot.')
    if cancel and cancel():
        raise Cancelled('Text import cancelled.')
    metrics = stats.result()
    detected = detect_language(name, stats.head, stats.tail if complete else '', language)
    preview, clipped = safe_preview(stats.head)
    warnings = detected.pop('warnings')
    if not complete:
        warnings.append('Preview inspects only the first 256 KiB; counts are sample-only. Import validates the entire source.')
    if metrics['control_count']:
        warnings.append('Control characters are preserved in the source and escaped in the read-only preview.')
    # UTF-16/32 endian information remains explicit even when the decoder is
    # the BOM-aware generic codec. No UTF-8 conversion is performed.
    actual = {'UTF-16LE':'utf-16-le', 'UTF-16BE':'utf-16-be',
              'UTF-32LE':'utf-32-le', 'UTF-32BE':'utf-32-be'}.get(bom, codec)
    return dict(filename=name, size_bytes=before.st_size, bytes_scanned=read_bytes,
                complete=complete, encoding=actual, decoder=codec, encoding_method=encoding_method,
                bom=bom, ascii_only=ascii_only, language=detected, text=metrics,
                preview=preview, preview_truncated=clipped or not complete,
                warnings=warnings, schema_version=1)
