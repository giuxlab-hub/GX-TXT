#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""GX-TXT process/metadata adapter for the portable text inspector.

Only this layer knows GX-TXT metadata keys and Dataset contracts. It writes a
single exact-byte payload under the supplied staging directory. CORE owns RAW,
registration, hashes, metadata persistence, commit and rollback. User source is
never imported or evaluated. All arbitrary command-line data is base64 encoded
by the Tcl adapter so even redirection-like filenames remain literal data.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'portable'))
from text_probe import analyze_file, detect_language, EncodingNeeded, TextError, Cancelled  # noqa: E402


def string(value: Any) -> str:
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (list, dict)):
        return json.dumps(value, ensure_ascii=True, separators=(',', ':'))
    return str(value)


def b64(value: Any) -> str:
    return base64.b64encode(string(value).encode('utf-8')).decode('ascii')


def unb64(value: str) -> str:
    return base64.b64decode(value, validate=True).decode('utf-8')


def emit(kind: str, *values: Any) -> None:
    print('\t'.join([kind, *(b64(v) for v in values)]), flush=True)


class Progress:
    def __init__(self) -> None:
        self.last = 0.0

    def __call__(self, current: int, total: int, stage: str) -> None:
        now = time.monotonic()
        if now - self.last > .1 or current >= total:
            print(f'P\t{current}\t{max(1,total)}\t{b64(stage)}', flush=True)
            self.last = now


def metadata(result: dict[str, Any]) -> dict[str, Any]:
    """Explicit, versioned mapping; move this adapter only with the contract.

    Extraction candidates: portable/ contains detection/statistics. This mapping
    can become a future generic text-Dataset metadata schema without requiring
    portable/ to know Session storage or application-specific key names.
    """
    language, metrics = result['language'], result['text']
    md = {
        'source.original_filename': result['filename'],
        'source.size_bytes': result['size_bytes'],
        'source.extension': Path(result['filename']).suffix,
        'text.metadata_schema_version': 1,
        'text.encoding': result['encoding'],
        'text.decoder': result['decoder'],
        'text.encoding_detection': result['encoding_method'],
        'text.bom': result['bom'],
        'text.is_ascii': result['ascii_only'],
        'text.bytes_scanned': result['bytes_scanned'],
        'text.scan_complete': result['complete'],
        'text.validation_scope': 'full' if result['complete'] else 'sample',
        'text.category': language['category'],
        'text.line_count': metrics['line_count'],
        'text.character_count': metrics['character_count'],
        'text.newline_style': metrics['newline_style'],
        'text.newline_counts_json': metrics['newline_counts'],
        'text.has_final_newline': metrics['has_final_newline'],
        'text.tab_count': metrics['tab_count'],
        'text.empty': metrics['empty'],
        'code.language': language['id'],
        'code.language_name': language['label'],
        'code.language_detection': language['method'],
        'code.language_confidence': language['confidence'],
        'code.language_evidence': language['evidence'],
        'code.detected_language': language['detected'],
        'code.language_candidates_json': language['candidates'],
        'code.detector_version': language['version'],
        'code.shebang': language['shebang'],
        'code.executed_by_importer': False,
    }
    return md


def main() -> int:
    print('GXTEXTIMPORT1', flush=True)
    parser = argparse.ArgumentParser(description='Inspect or preserve a text/code Dataset; never execute its contents.')
    parser.add_argument('--source-b64', required=True)
    parser.add_argument('--original-name-b64', required=True)
    parser.add_argument('--import-source', action='store_true')
    parser.add_argument('--output-dir-b64')
    parser.add_argument('--dataset-id')
    parser.add_argument('--encoding-b64', default=b64('auto'))
    parser.add_argument('--language-b64', default=b64('auto'))
    parser.add_argument('--import-as-b64', default=b64('auto'))
    parser.add_argument('--cancel-file-b64')
    destination: Path | None = None
    owned = False
    try:
        args = parser.parse_args()
        source = Path(unb64(args.source_b64))
        name = unb64(args.original_name_b64)
        selected_encoding = unb64(args.encoding_b64)
        selected_language = unb64(args.language_b64)
        import_as = unb64(args.import_as_b64)
        if import_as not in {'auto', 'text_document', 'source_code'}:
            raise TextError('Import as must be Auto, Text document or Source code.')
        marker = Path(unb64(args.cancel_file_b64)) if args.cancel_file_b64 else None
        cancelled = lambda: marker is not None and marker.exists()
        kwargs = dict(original_name=name, encoding=selected_encoding, language=selected_language,
                      full=args.import_source, progress=Progress(), cancel=cancelled)
        if args.import_source:
            if not args.dataset_id or not re.fullmatch(r'[A-Za-z0-9_.-]+', args.dataset_id) or args.dataset_id in {'.','..'}:
                raise TextError('A framework-safe Dataset ID is required.')
            out = Path(unb64(args.output_dir_b64 or ''))
            if not args.output_dir_b64 or not out.is_dir():
                raise TextError('The framework-owned output directory does not exist.')
            # Preserve useful extensions; original filename always travels in
            # metadata, so extensionless scripts and Makefile are not lost.
            suffix = Path(name).suffix
            if not re.fullmatch(r'\.[A-Za-z0-9_+-]{1,20}', suffix):
                suffix = '.txt'
            relative = args.dataset_id + suffix
            destination = out / relative
            with destination.open('xb') as target:
                owned = True
                result = analyze_file(source, on_chunk=target.write, **kwargs)
                target.flush()
                os.fsync(target.fileno())
        else:
            try:
                result = analyze_file(source, **kwargs)
            except EncodingNeeded as exc:
                # Inspection has no module config in API v1. Let the source
                # reach import settings instead of blocking explicit encodings.
                # Import always performs full validation and never uses this
                # permissive candidate branch.
                lang = detect_language(name, '')
                emit('F', 'status', 'needs_encoding')
                emit('F', 'format', 'text')
                emit('F', 'preview', '')
                emit('M', 'source.original_filename', name)
                emit('M', 'source.size_bytes', source.stat().st_size)
                emit('M', 'code.language', lang['id'])
                emit('M', 'text.encoding', 'undetermined')
                emit('M', 'text.validation_scope', 'unvalidated_encoding_candidate')
                emit('W', str(exc))
                emit('W', 'Set the Encoding import field before importing this source. This candidate has not passed text validation.')
                print('OK', flush=True)
                return 0
        language = result['language']
        is_code = (import_as == 'source_code' or
                   (import_as == 'auto' and language['category'] == 'code'))
        fields = dict(status='ready', format='source_code' if is_code else 'text',
                      contract='code.source' if is_code else 'document.text',
                      media_type='text/plain', label=language['label'],
                      preview=result['preview'], preview_truncated=result['preview_truncated'])
        md = metadata(result)
        md['text.import_as'] = import_as
        if args.import_source:
            fields['path'] = relative
            md['text.source_bytes_preserved'] = True
            md['text.import_warnings_json'] = result['warnings']
        for key, value in fields.items():
            emit('F', key, value)
        for key, value in md.items():
            emit('M', key, value)
        for warning in result['warnings']:
            emit('W', warning)
        if cancelled():
            raise Cancelled('Text import cancelled.')
        print('OK', flush=True)
        return 0
    except Exception as exc:
        if owned and destination is not None:
            destination.unlink(missing_ok=True)
        emit('E', f'{type(exc).__name__}: {exc}')
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
