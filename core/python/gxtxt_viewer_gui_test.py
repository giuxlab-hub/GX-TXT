# SPDX-License-Identifier: GPL-3.0-or-later
"""Typed project mailbox for an explicitly attached Development Workspace GUI.

This transports inert data to the existing GUI owner. It cannot start a desktop,
choose a module/path, evaluate Tcl, or perform scientific work in the CLI.
"""
import os
import base64
from pathlib import Path
import re
import tempfile
import time
import uuid


def gui_test(project, payload):
    from gxtxt_viewer_development import DevelopmentError, dictionary, read_project, digest
    from gxtxt_job_supervisor import tcl_result
    read_project(project)
    shapes = {
        'open': set(), 'status': set(), 'close': set(), 'capture': set(),
        'workspace_open': {'workspace_id'},
        'workspace_save': set(),
        'workspace_review': {'workspace_id'},
        'workspace_upgrade': {'review_id'},
        'click': {'component'}, 'choice': {'component', 'value'},
        'list_select': {'component', 'index'},
        'table_select': {'component', 'index'},
        'table_scroll': {'component', 'axis', 'direction'},
        'table_copy': {'component'},
        'table_page': {'component', 'command'},
        'text': {'component', 'value'}, 'tab': {'component'},
        'source_text': {'component', 'value'},
        'source_replace': {'component', 'query', 'replacement', 'scope'},
        'pointer': {'component', 'x', 'y', 'phase'},
        'plot_pointer': {'component', 'x', 'y'},
        'key': {'component', 'key'},
        'document_find': {'component', 'value', 'direction'},
        'document_pointer': {'component', 'x', 'y', 'phase'},
        'document_zoom': {'component', 'value'},
        'pdf_control': {'component', 'command'},
        'pdf_pointer': {'component', 'x', 'y', 'phase'},
        'pdf_key': {'component', 'key'},
        'pdf_resize': {'component', 'width', 'height'},
        'pdf_close': {'component'},
        'property': {'component', 'field', 'value'},
        'wire_route': {'component', 'command'},
        'properties_commit': {'component'}, 'properties_close': {'component'},
        'capture_verify': {'capture_id'},
        'capture_preview': {'capture_id'},
        'label': {'component', 'field', 'value'},
        'label_apply': {'component'}, 'label_close': {'component'},
        'resize': {'width', 'height'},
    }
    if isinstance(payload, dict) and payload.get('operation') == 'capture' and set(payload) == {'operation', 'component', 'dialog'}:
        shapes['capture'] = {'component', 'dialog'}
    if isinstance(payload, dict) and payload.get('operation') == 'plot_pointer' and 'phase' in payload:
        shapes['plot_pointer'] = {'component', 'x', 'y', 'phase'}
    if isinstance(payload, dict) and payload.get('operation') == 'wire_route' and payload.get('command') == 'select':
        shapes['wire_route'] = {'component', 'command', 'index'}
    if isinstance(payload, dict) and payload.get('operation') == 'table_page' and payload.get('command') == 'goto':
        shapes['table_page'] = {'component', 'command', 'row'}
    if not isinstance(payload, dict) or payload.get('operation') not in shapes or set(payload) != {'operation'} | shapes[payload['operation']]:
        raise DevelopmentError('Use an enumerated typed GUI test action', 'GUI_TEST_REQUEST')
    for key, value in payload.items():
        if key in {'width', 'height'}:
            minimum, maximum = (640, 1880) if key == 'width' else (480, 1100)
            if type(value) is not int or not minimum <= value <= maximum:
                raise DevelopmentError('Native Viewer size must be640..1880 by480..1100 integer client pixels', 'GUI_TEST_REQUEST')
        elif key == 'index':
            limit = 1000 if payload['operation'] in {'list_select', 'table_select'} else 128
            if type(value) is not int or not 0 <= value < limit:
                raise DevelopmentError(f'Native row index must be0..{limit-1}', 'GUI_TEST_REQUEST')
        elif key in {'x', 'y'}:
            if type(value) not in (int, float) or not -1000000 <= value <= 1000000:
                raise DevelopmentError('Pointer world coordinates are outside bounds', 'GUI_TEST_REQUEST')
        elif not isinstance(value, str) or '\0' in value or len(value.encode()) > 4096:
            raise DevelopmentError('GUI action fields must be bounded text', 'GUI_TEST_REQUEST')
    if 'component' in payload and not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,63}', payload['component']):
        raise DevelopmentError('Use a declared logical component identity', 'GUI_TEST_REQUEST')
    if payload['operation'] == 'wire_route' and payload['command'] not in {'select', 'add', 'replace', 'remove', 'up', 'down'}:
        raise DevelopmentError('Unknown typed wire bend action', 'GUI_TEST_REQUEST')
    if payload['operation'] == 'table_scroll' and (payload['axis'] not in {'x', 'y'} or payload['direction'] not in {'backward', 'forward'}):
        raise DevelopmentError('Table scroll uses axis x|y and direction backward|forward', 'GUI_TEST_REQUEST')
    if payload['operation'] == 'table_page':
        if payload['command'] not in {'previous', 'next', 'first', 'last', 'goto', 'schema'}:
            raise DevelopmentError('Table paging command must be previous, next, first, last, goto or schema', 'GUI_TEST_REQUEST')
        if payload['command'] == 'goto' and (len(payload['row']) > 32 or not re.fullmatch(r'[+-]?[0-9]+', payload['row'])):
            raise DevelopmentError('Enter a bounded integer source-row literal', 'GUI_TEST_REQUEST')
    if 'workspace_id' in payload and (len(payload['workspace_id']) > 128 or not re.fullmatch(r'idoc_[0-9]{4,}', payload['workspace_id'])):
        raise DevelopmentError('Use a canonical current-Session Workspace identity', 'GUI_TEST_REQUEST')
    if 'capture_id' in payload and not re.fullmatch(r'[0-9a-f]{32}', payload['capture_id']):
        raise DevelopmentError('Use an exact native capture identity', 'GUI_TEST_REQUEST')
    if 'review_id' in payload and not re.fullmatch(r'review-[0-9a-f]+-[0-9a-f]+', payload['review_id']):
        raise DevelopmentError('Use an exact live Workspace review identity', 'GUI_TEST_REQUEST')
    if 'dialog' in payload and payload['dialog'] not in {'net_label', 'properties', 'pdf_reader'}:
        raise DevelopmentError('Choose an existing owned net_label, properties or pdf_reader window', 'GUI_TEST_REQUEST')
    phases = {'click', 'double', 'press', 'move', 'release'}
    if payload['operation'] in {'pointer', 'plot_pointer', 'document_pointer', 'pdf_pointer'}:
        phases |= {'wheel_up', 'wheel_down'}
    if payload.get('phase', 'click') not in phases:
        raise DevelopmentError('Unknown bounded pointer phase', 'GUI_TEST_REQUEST')
    if payload.get('key', 'Escape') not in {'Escape', 'Delete', 'BackSpace', 'Return', 'r', 'w', 'j', 'p', 'f', 'ctrl+z', 'ctrl+y', 'ctrl+h', 'ctrl+f', 'F3', 'shift+F3', 'ctrl+a', 'ctrl+c', 'ctrl+plus', 'ctrl+equal', 'ctrl+minus', 'ctrl+0', 'Home', 'End', 'ctrl+Home', 'ctrl+End', 'Page_Up', 'Page_Down', 'PageUp', 'PageDown', 'Up', 'Down', 'Left', 'Right', 'Tab', 'shift+Tab'}:
        raise DevelopmentError('Key is outside the declared native input contracts', 'GUI_TEST_REQUEST')
    if payload['operation']=='document_find' and payload['direction'] not in {'forward','backward'}:
        raise DevelopmentError('Document find direction must be forward or backward','GUI_TEST_REQUEST')
    if payload['operation']=='document_find' and any(ord(c)<32 or ord(c)==127 for c in payload['value']):
        raise DevelopmentError('Native Find accepts a single-line literal query without control characters','GUI_TEST_REQUEST')
    if payload['operation']=='source_replace':
        if payload['scope'] not in {'current','all'} or not payload['query'] or any(ord(c)<32 or ord(c)==127 for key in ('query','replacement') for c in payload[key]):
            raise DevelopmentError('Native Replace requires a nonempty single-line query, literal single-line replacement and scope current|all','GUI_TEST_REQUEST')
    if payload['operation']=='document_zoom' and payload['value'] not in {'in','out','reset'}:
        raise DevelopmentError('Document zoom must be in, out or reset','GUI_TEST_REQUEST')
    if payload['operation']=='pdf_control' and payload['command'] not in {'previous','next','zoom_out','zoom_in','fit_page','fit_width'}:
        raise DevelopmentError('Choose an enumerated native PDF reader control','GUI_TEST_REQUEST')
    if payload['operation']=='pdf_key' and payload['key'] not in {'Left','Right','Up','Down','Tab','shift+Tab'}:
        raise DevelopmentError('PDF keys scroll or change focus only','GUI_TEST_REQUEST')
    folder = project / 'derived' / 'gui-test'
    for path in (project / 'derived', folder):
        if not path.is_dir() or path.is_symlink():
            raise DevelopmentError('Enable native GUI testing for this project in Development Workspace first', 'GUI_TEST_NOT_ATTACHED')
    connection = folder / 'connection.tcldict'
    if connection.is_symlink() or not connection.is_file() or connection.stat().st_size > 16384:
        raise DevelopmentError('No valid GUI attachment', 'GUI_TEST_NOT_ATTACHED')
    attached = dictionary(connection.read_text())
    snapshot = {key: digest((project / name).read_bytes()) for name, key in [('handlers.cpp', 'source_sha256'), ('design.gxtxt-viewer', 'design_sha256'), ('project.json', 'project_sha256')]}
    if dictionary(attached.get('snapshot', '')) != snapshot:
        raise DevelopmentError('Source changed; reattach GUI testing in Workspace', 'SOURCE_CHANGED')
    request_id = uuid.uuid4().hex
    request = dict(payload, request_id=request_id, connection=attached['connection'], snapshot=snapshot)
    target = folder / 'request.tcldict'
    # A single owner action at a time, exactly like debugger command transport.
    if target.exists():
        raise DevelopmentError('Another GUI action is pending', 'GUI_TEST_BUSY')
    data = tcl_result(request).encode()
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as stream:
        stream.write(data); stage = Path(stream.name)
    try:
        os.link(stage, target)
    finally:
        stage.unlink()
    response = folder / ('response-' + request_id + '.tcldict')
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if response.exists():
            if response.is_symlink() or response.stat().st_size > 1048576:
                raise DevelopmentError('Invalid GUI action receipt', 'GUI_TEST_RESPONSE')
            result = dictionary(response.read_text())
            if result.get('request_id') != request_id:
                raise DevelopmentError('GUI receipt identity mismatch', 'GUI_TEST_RESPONSE')
            if result.get('ok') != '1':
                raise DevelopmentError(result.get('error', 'GUI action rejected'), result.get('code', 'GUI_TEST_DENIED'))
            answer = {'status': 'COMPLETED', 'gui_receipt': result, 'receipt_path': str(response), 'scope': 'Actual explicitly attached native GUI; source-bound Development Workspace owner'}
            if payload['operation'] == 'capture_preview':
                from gxtxt_viewer_manual_assets import regular_bytes
                from gxtxt_viewer_icons import png
                captured = dictionary(result.get('result', ''))
                image_path = folder / ('capture-' + payload['capture_id'] + '.png')
                if captured.get('operation') != 'capture_preview' or captured.get('screenshot') != str(image_path) or dictionary(captured.get('source_snapshot', '')) != snapshot:
                    raise DevelopmentError('Preview must identify the live source-bound native capture', 'GUI_TEST_RESPONSE')
                data = regular_bytes(image_path, 2 * 1024 * 1024)
                width, height, _ = png(data, max_bytes=2 * 1024 * 1024, max_dimension=4096, capture_metadata=True)
                if digest(data) != captured.get('screenshot_sha256'):
                    raise DevelopmentError('Native capture changed during preview delivery', 'GUI_TEST_RESPONSE')
                answer['image_content'] = dict(mime_type='image/png', data=base64.b64encode(data).decode('ascii'), width=width, height=height, capture_id=payload['capture_id'], sha256=digest(data), source_snapshot=snapshot, session=captured['session'], geometry=captured['geometry'])
            return answer
        time.sleep(.05)
    raise DevelopmentError('Attached GUI did not answer; inspect it before retrying pending action', 'GUI_TEST_TIMEOUT')
