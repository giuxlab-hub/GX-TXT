# SPDX-License-Identifier: GPL-3.0-or-later
"""Development-owned handoff from native GUI receipts to Module manual resources.

No author path, image processing, runtime privilege or global registry is added.
The project resource inventory preserves the exact original capture provenance.
"""
import json
import os
from pathlib import Path
import re
import stat
import tempfile

MAX_IMAGE = 8 * 1024 * 1024
MAX_TOTAL = 16 * 1024 * 1024
MAX_ASSETS = 32


def regular_bytes(path, limit):
    from gxtxt_viewer_development import DevelopmentError
    path = Path(path)
    if path.resolve() != path.absolute():
        raise DevelopmentError('Manual resource links are refused', 'MANUAL_ASSET')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
            raise DevelopmentError('Manual resource must be an ordinary bounded file', 'MANUAL_ASSET')
        with os.fdopen(fd, 'rb', closefd=False) as stream:
            data = stream.read(limit + 1)
        after = os.fstat(fd)
        if len(data) > limit or (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise DevelopmentError('Manual resource changed during admission', 'MANUAL_ASSET')
        return data
    finally:
        os.close(fd)


def asset_id(value):
    from gxtxt_viewer_development import DevelopmentError
    if not isinstance(value, str) or not re.fullmatch(r'[a-z][a-z0-9_-]{0,63}', value):
        raise DevelopmentError('Use a logical manual image ID; paths are refused', 'MANUAL_ASSET')
    return value


def inventory(project):
    from gxtxt_viewer_development import DevelopmentError
    path = project / 'manual-assets.json'
    if not path.exists() and not path.is_symlink():
        return {'schema': 'gxtxt.viewer_manual_assets.v1', 'assets': {}}
    value = json.loads(regular_bytes(path, 131072))
    if not isinstance(value, dict) or set(value) != {'schema', 'assets'} or value['schema'] != 'gxtxt.viewer_manual_assets.v1' or not isinstance(value['assets'], dict) or len(value['assets']) > MAX_ASSETS:
        raise DevelopmentError('Invalid project manual resource inventory', 'MANUAL_ASSET')
    return value


def resources(project):
    from gxtxt_viewer_development import DevelopmentError, digest
    from gxtxt_viewer_icons import png
    value = inventory(project)
    result = {}
    total = 0
    for name, item in value['assets'].items():
        asset_id(name)
        if not isinstance(item, dict) or set(item) != {'sha256', 'bytes', 'width', 'height', 'capture_id', 'source_snapshot', 'session', 'geometry'} or not re.fullmatch(r'[0-9a-f]{64}', item['sha256']):
            raise DevelopmentError('Invalid manual resource provenance', 'MANUAL_ASSET')
        data = regular_bytes(project / 'manual-assets' / (item['sha256'] + '.png'), MAX_IMAGE)
        width, height, _ = png(data, max_bytes=MAX_IMAGE, max_dimension=4096, capture_metadata=True)
        total += len(data)
        if digest(data) != item['sha256'] or len(data) != item['bytes'] or (width, height) != (item['width'], item['height']) or total > MAX_TOTAL:
            raise DevelopmentError('Manual image identity, dimensions or total size differs', 'MANUAL_ASSET')
        result['images/' + name + '.png'] = data
    if value['assets']:
        result['review/manual-assets.json'] = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    return result, value


def manual_asset(project, request):
    from gxtxt_viewer_development import DevelopmentError, dictionary, digest, read_project, write_json
    read_project(project)
    if not isinstance(request, dict) or request.get('operation') not in {'list', 'add', 'remove'}:
        raise DevelopmentError('Use list/add/remove manual resource operations', 'MANUAL_ASSET')
    operation = request['operation']
    required = {'operation'} | ({'asset_id', 'capture_id'} if operation == 'add' else {'asset_id'} if operation == 'remove' else set())
    if set(request) != required:
        raise DevelopmentError('Unexpected manual resource request fields', 'MANUAL_ASSET')
    _, value = resources(project)
    if operation == 'list':
        return {'status': 'COMPLETED', 'inventory': value, 'installed_paths': {name: 'images/' + name + '.png' for name in value['assets']}}
    name = asset_id(request['asset_id'])
    if operation == 'remove':
        if name not in value['assets']:
            raise DevelopmentError('Manual image ID is not present', 'MANUAL_ASSET')
        del value['assets'][name]
        # Content-addressed source bytes stay available for older project receipts.
        write_json(project / 'manual-assets.json', value)
        return {'status': 'SAVED', 'removed': name, 'inventory': value}
    capture_id = request['capture_id']
    if not isinstance(capture_id, str) or not re.fullmatch(r'[0-9a-f]{32}', capture_id):
        raise DevelopmentError('Use the exact native capture request identity', 'MANUAL_ASSET')
    folder = project / 'derived' / 'gui-test'
    response = dictionary(regular_bytes(folder / ('response-' + capture_id + '.tcldict'), 1048576).decode('utf-8'))
    captured = dictionary(response.get('result', ''))
    snapshot = {key: digest((project / filename).read_bytes()) for filename, key in [('handlers.cpp', 'source_sha256'), ('design.gxtxt-viewer', 'design_sha256'), ('project.json', 'project_sha256')]}
    path = folder / ('capture-' + capture_id + '.png')
    if response.get('ok') != '1' or response.get('request_id') != capture_id or captured.get('operation') != 'capture' or dictionary(captured.get('source_snapshot', '')) != snapshot or captured.get('screenshot') != str(path):
        raise DevelopmentError('Capture must be a successful source-identical project native GUI receipt', 'MANUAL_ASSET')
    # A project-local fabricated receipt cannot establish GUI origin. Require
    # confirmation from the live owner, which retains its issued capture IDs.
    from gxtxt_viewer_gui_test import gui_test
    verified = dictionary(gui_test(project, {'operation': 'capture_verify', 'capture_id': capture_id})['gui_receipt']['result'])
    for key in ('source_snapshot', 'screenshot', 'screenshot_sha256', 'session', 'geometry'):
        if verified.get(key) != captured.get(key):
            raise DevelopmentError('Capture receipt differs from the live GUI owner', 'MANUAL_ASSET')
    data = regular_bytes(path, MAX_IMAGE)
    from gxtxt_viewer_icons import png
    width, height, _ = png(data, max_bytes=MAX_IMAGE, max_dimension=4096, capture_metadata=True)
    sha = digest(data)
    if sha != captured.get('screenshot_sha256'):
        raise DevelopmentError('Native screenshot SHA differs from capture receipt', 'MANUAL_ASSET')
    item = {'sha256': sha, 'bytes': len(data), 'width': width, 'height': height, 'capture_id': capture_id, 'source_snapshot': snapshot, 'session': captured.get('session', ''), 'geometry': captured.get('geometry', '')}
    value['assets'][name] = item
    if len(value['assets']) > MAX_ASSETS or sum(item['bytes'] for item in value['assets'].values()) > MAX_TOTAL:
        raise DevelopmentError('Manual resources exceed32 images/16MiB total', 'MANUAL_ASSET')
    target = project / 'manual-assets'
    if target.exists() and (target.is_symlink() or not target.is_dir()):
        raise DevelopmentError('Manual resource directory must be project-owned', 'MANUAL_ASSET')
    target.mkdir(exist_ok=True)
    destination = target / (sha + '.png')
    if destination.exists() or destination.is_symlink():
        if regular_bytes(destination, MAX_IMAGE) != data:
            raise DevelopmentError('Existing resource identity differs', 'MANUAL_ASSET')
    else:
        with tempfile.NamedTemporaryFile(dir=target, delete=False) as stream:
            stream.write(data)
            stage = Path(stream.name)
        os.replace(stage, destination)
    write_json(project / 'manual-assets.json', value)
    return {'status': 'SAVED', 'asset_id': name, 'installed_path': 'images/' + name + '.png', 'provenance': item}
