# SPDX-License-Identifier: GPL-3.0-or-later
"""Trusted finite paired-source staging only; no canonical Document writer.

Unwired SOURCE proposal. Parent ScriptJob/Resource and serialized Document owners
retain authorization, cancellation, last-yield proof, commit and GUI lifetimes.
"""
from __future__ import annotations
from collections import Counter
from decimal import Decimal, localcontext
import hashlib
import json
import math
import os
from pathlib import Path
import re
import resource
import stat
import sys
import time
from xml.etree.ElementTree import Element
from xml.parsers import expat

# -I excludes ambient import paths. Reuse the actual existing trusted CORE codec.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gxtxt_job_supervisor import request_process_group, tcl_result

VERSION = 'gxtxt.eagle_paired_source.v1'
RAID = Path('/srv/gxtxt/agents')
MAX_SOURCE = 4 * 1024 * 1024
MAX_JSON = 16 * 1024 * 1024
MAX_STAGED_BYTES = 96 * 1024 * 1024 # All attempted artifact writes, including mirrors/receipts.
MAX_OBJECTS = 16384                 # This adapter's bound, not a native limit.
MAX_POINTS = 65536
VISIBLE_POINT_BUDGET = 4096         # Existing Native2D viewport draw budget.
APPROVED = {
    'board': '550d7d86ff63cd1e7672fb5c9a4860798ff868ece50b7e40ee9aedff153445ca',
    'schematic': 'f073caca2fc4fb4d24c942dbdb2dfb9edee17221adfd8ed175b7ceb359be5639',
}
UPSTREAM = 'https://github.com/sparkfun/SparkFun_Buck_Regulator_AP63357DV-7'
UPSTREAM_COMMIT = '2daeae4799b416ed27fc1dfa3123d6cc68747f38'
LICENSE = Path(__file__).resolve().parents[2] / 'docs/development/task210/pcb_paired_source/SOURCE_LICENSE.md'
LICENSE_SHA = '6532771f09b24eadc3e75b9c2ecb035c38ebea295542833e892fab9018c678da'
LIMITATIONS = [
    'One approved source pair; historical7.7/current-help qualified mm subset, not full9.6.2 certification.',
    'Pad/via centres, trace centre lines and polygon boundary definitions only; no finished copper or drill-as-diameter.',
    'Mirrored/fractional/spin transforms, curves and other artwork explicitly excluded; no guessed placement or flattened arcs.',
    'No pour, manufacturing, DRC/ERC, material/stackup, physical continuity, 3D, EM/SI or scientific result.',
    'Visible Native2D point_budget4096 must be exposed by the parent; complete primitive visibility is not guaranteed.',
    'Only staged source prepared; no canonical Document/Session, GUI, native projection or source commit performed.',
]


class AdmissionError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def require(condition, code, message):
    if not condition:
        raise AdmissionError(code, message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True,
                      separators=(',', ':')).encode('utf-8')


def no_duplicate_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'REQUEST', 'Duplicate JSON field')
        result[key] = value
    return result


def identity(info):
    return dict(device=info.st_dev, inode=info.st_ino, size=info.st_size,
                mode=stat.S_IMODE(info.st_mode), uid=info.st_uid, gid=info.st_gid,
                links=info.st_nlink, mtime_ns=info.st_mtime_ns, ctime_ns=info.st_ctime_ns)


def read_regular(path, limit):
    require(path.is_absolute() and path == path.resolve(strict=True), 'PATH', 'Real absolute ordinary source required')
    named = path.lstat()
    require(stat.S_ISREG(named.st_mode) and named.st_nlink == 1 and 0 <= named.st_size <= limit,
            'FILE', 'Source must be a bounded singly linked regular file')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        require(identity(before) == identity(named), 'SOURCE_CHANGED', 'Original FD/path identity changed')
        raw = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    require(len(raw) <= limit and identity(before) == identity(after) == identity(path.lstat())
            and path == path.resolve(strict=True), 'SOURCE_CHANGED', 'Source changed during bounded read')
    return raw, identity(before)


def write_exclusive(root, name, raw, limit=MAX_JSON, *, staged_bytes):
    require(len(raw) <= limit, 'OUTPUT_BUDGET', 'Staged artifact exceeds its finite bound')
    require(len(raw) <= MAX_STAGED_BYTES - staged_bytes[0],
            'OUTPUT_BUDGET', 'Cumulative staged artifact byte budget exceeded')
    # Charge before opening: a partial failed write also consumes this allowance.
    staged_bytes[0] += len(raw)
    path = root / name
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    actual, stamp = read_regular(path, limit)
    require(actual == raw and stamp['mode'] == 0o600, 'READBACK', 'Staged artifact bytes/mode readback failed')
    return dict(name=name, sha256=digest(raw), bytes=len(raw), mode=stamp['mode'])


def tcl_data_mirror(kind, value, json_artifact):
    """Existing trusted codec, complete domain data; never executable Tcl."""
    require(kind in {'index', 'layout', 'receipt'}, 'OUTPUT', 'Closed prepared data mirror kind required')
    projection = dict(value)
    if kind in {'index', 'layout'}:
        collection = 'records' if kind == 'index' else 'objects'
        rows = []
        for original in value[collection]:
            row = dict(original)
            # Existing tcl_result represents None as empty. Preserve the known
            # optional domain fields' presence separately, without a new codec.
            for field in ('net', 'declared_net', 'layer'):
                if field in original:
                    row[field + '_present'] = original[field] is not None
            rows.append(row)
        projection[collection] = rows
    return tcl_result(dict(ok=True, result=dict(
        schema='gxtxt.eagle_pair_tcl_data.v1', kind=kind,
        json_artifact=json_artifact, data=projection))).encode('utf-8')


class Budget:
    def __init__(self, deadline):
        self.deadline = deadline
        self.records = []
        self.bytes = 0

    def check(self):
        require(time.monotonic() < self.deadline, 'TIMEOUT', 'Finite worker staging deadline expired')

    def add(self, row):
        self.check()
        size = len(encoded(row))
        require(size <= 65536 and self.bytes + size <= MAX_JSON - 65536
                and len(self.records) < 65536, 'INDEX_BUDGET', 'Finite record/index budget exceeded')
        self.bytes += size
        self.records.append(row)


def derived_xml(raw):
    """Locate actual prolog tokens; never globally replace declaration text."""
    require(isinstance(raw, bytes) and 0 < len(raw) <= MAX_SOURCE, 'XML_BUDGET', 'Finite staged XML bytes required')
    text = raw.decode('utf-8', errors='strict')
    declaration = '<?xml version="1.0" encoding="utf-8"?>'
    require(text.startswith(declaration) and '\x00' not in text, 'XML_ENCODING', 'Exact UTF-8 XML1.0 declaration required')
    cursor = len(declaration)
    admitted = None
    token = '<!DOCTYPE eagle SYSTEM "eagle.dtd">'
    while True:
        while cursor < len(text) and text[cursor] in ' \t\r\n':
            cursor += 1
        if text.startswith('<!--', cursor):
            end = text.find('-->', cursor + 4)
            require(end >= 0 and '--' not in text[cursor + 4:end], 'XML_PROLOG', 'Invalid prolog comment')
            cursor = end + 3
        elif text.startswith(token, cursor):
            require(admitted is None, 'XML_DTD', 'Only one exact inert EAGLE declaration is admitted')
            admitted = (cursor, cursor + len(token))
            cursor += len(token)
        else:
            require(text.startswith('<eagle', cursor) and cursor + 6 < len(text)
                    and text[cursor + 6] in ' \t\r\n>', 'XML_PROLOG', 'Unsupported prolog/root declaration')
            break
    if admitted is not None:
        start, end = admitted
        text = text[:start] + ' ' * (end - start) + text[end:]
    return text.encode('utf-8'), dict(policy='exact-prolog-token-whitespace-view-no-resolution.v1',
                                     inert_doctype_count=int(admitted is not None))


def parse_staged(raw, role, budget):
    require(role in {'board', 'schematic'}, 'PAIR_ROLE', 'Closed EAGLE source role required')
    view, policy = derived_xml(raw)
    parser = expat.ParserCreate('utf-8')
    parser.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_NEVER)
    stack = []
    roots = []
    tags = Counter()
    totals = dict(nodes=0, attributes=0, text=0)

    def forbidden(*args):
        raise AdmissionError('XML_DTD_ENTITY_PI', 'DTD/entity/PI/external resolution is forbidden in the derived view')

    def start(name, attributes):
        budget.check()
        require(len(stack) < 64 and totals['nodes'] < 50000, 'XML_BUDGET', 'XML depth/node budget exceeded')
        require(re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,63}', name) is not None
                and len(attributes) <= 64, 'XML_BUDGET', 'XML tag/attribute budget exceeded')
        size = sum(len(key.encode('utf-8')) + len(value.encode('utf-8')) for key, value in attributes.items())
        require(all(len(key) <= 128 and len(value) <= 4096 for key, value in attributes.items())
                and totals['attributes'] + size <= MAX_SOURCE, 'XML_BUDGET', 'XML attribute text budget exceeded')
        node = Element(name, attributes)
        if stack:
            stack[-1][0].append(node)
        else:
            roots.append(node)
        stack.append([node, [], 0])
        totals['nodes'] += 1
        totals['attributes'] += size
        tags[name] += 1

    def characters(value):
        size = len(value.encode('utf-8'))
        require(totals['text'] + size <= MAX_SOURCE, 'XML_BUDGET', 'XML text budget exceeded')
        totals['text'] += size
        if stack:
            require(stack[-1][2] + size <= 65536, 'XML_BUDGET', 'Individual XML text exceeds64KiB')
            stack[-1][1].append(value)
            stack[-1][2] += size

    def end(name):
        node, pieces, _ = stack.pop()
        node.text = ''.join(pieces)

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = characters
    parser.StartDoctypeDeclHandler = forbidden
    parser.EntityDeclHandler = forbidden
    parser.ExternalEntityRefHandler = forbidden
    parser.ProcessingInstructionHandler = forbidden
    parser.SkippedEntityHandler = forbidden
    for offset in range(0, len(view), 8192):
        budget.check()
        parser.Parse(view[offset:offset + 8192], False)
    parser.Parse(b'', True)
    require(len(roots) == 1 and roots[0].tag == 'eagle'
            and roots[0].attrib == {'version': '9.6.2'}, 'XML_VERSION', 'Only the finite EAGLE9.6.2 root is admitted')
    drawing = one(roots[0], 'drawing')
    require(not [node for node in drawing if node.tag in {'board', 'schematic'} and node.tag != role],
            'PAIR_ROLE', 'Unexpected paired source role')
    return one(drawing, role), drawing, dict(**policy, counts=totals, tags=dict(tags))


def one(parent, tag, required=True):
    values = [node for node in parent if node.tag == tag]
    require(len(values) <= 1 and (not required or len(values) == 1), 'STRUCTURE', 'Missing/duplicate structural section: ' + tag)
    return values[0] if values else None


def named(parent, tag):
    result = {}
    if parent is None:
        return result
    for node in parent:
        if node.tag != tag:
            continue
        require('name' in node.attrib and len(node.attrib['name']) <= 512
                and node.attrib['name'] not in result, 'STRUCTURE', 'Missing/duplicate source name: ' + tag)
        result[node.attrib['name']] = node
    return result


def number(node, key):
    value = node.attrib[key]
    require(len(value) <= 64 and re.fullmatch(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)', value) is not None,
            'DECIMAL', 'Ordinary bounded decimal required')
    result = Decimal(value)
    require(result.is_finite() and abs(result) <= Decimal('1000000')
            and result.as_tuple().exponent >= -18, 'DECIMAL', 'Finite mm/degree subset exceeded')
    return result


def rotation(node):
    raw = node.attrib.get('rot', 'R0')
    if not re.fullmatch(r'R[+-]?[0-9]+(?:\.0+)?', raw) or len(raw) > 16:
        return None
    angle = Decimal(raw[1:])
    if angle % 90:
        return None
    return int(angle) % 360


def point(node, x='x', y='y'):
    return number(node, x), number(node, y)


def place(element, local):
    angle = rotation(element)
    x, y = local
    if angle == 90:
        x, y = -y, x
    elif angle == 180:
        x, y = -x, -y
    elif angle == 270:
        x, y = y, -x
    return x + number(element, 'x'), y + number(element, 'y')


def package_maps(owner):
    result = {}
    for name, library in named(one(owner, 'libraries'), 'library').items():
        result[name] = dict(node=library, packages=named(one(library, 'packages', False), 'package'),
                            devicesets=named(one(library, 'devicesets', False), 'deviceset'),
                            symbols=named(one(library, 'symbols', False), 'symbol'))
    return result


def pads(package):
    result = {}
    for child in package:
        if child.tag in {'pad', 'smd'}:
            name = child.attrib['name']
            require(name not in result and len(name) <= 512, 'PAD', 'Duplicate/oversize package pad name')
            result[name] = child
    return result


def reference(pair, role, path):
    return dict(source_id='eagle:' + pair + ':' + digest(encoded([role, path])), role=role, path=path)


def reconcile(board, schematic, pair, index):
    board_libs, sch_libs = package_maps(board), package_maps(schematic)
    elements = named(one(board, 'elements'), 'element')
    parts = named(one(schematic, 'parts'), 'part')
    part_data, device_cache, pin_nets, expected, board_contacts = {}, {}, {}, {}, {}
    for name, part in parts.items():
        index.check()
        lib, ds, selection = (part.attrib[key] for key in ('library', 'deviceset', 'device'))
        key = (lib, ds, selection)
        if key not in device_cache:
            library = sch_libs[lib]
            deviceset = library['devicesets'][ds]
            device = named(one(deviceset, 'devices'), 'device')[selection]
            gates = named(one(deviceset, 'gates'), 'gate')
            pins_by_gate = {gate: named(library['symbols'][node.attrib['symbol']], 'pin') for gate, node in gates.items()}
            package_name = device.attrib.get('package', '')
            package = library['packages'][package_name] if package_name else None
            local_pads = pads(package) if package is not None else {}
            connections = {}
            connects = one(device, 'connects', False)
            for connect in ([] if connects is None else connects):
                require(connect.tag == 'connect', 'CONNECT', 'Unexpected connects child')
                gate, pin = connect.attrib['gate'], connect.attrib['pin']
                mapped = connect.attrib['pad'].split()
                require(gate in pins_by_gate and pin in pins_by_gate[gate] and mapped
                        and len(mapped) <= 64 and len(set(mapped)) == len(mapped)
                        and all(pad in local_pads for pad in mapped) and (gate, pin) not in connections,
                        'CONNECT', 'Ambiguous/missing gate/pin/package pad in selected device')
                connections[(gate, pin)] = mapped
            device_cache[key] = dict(package=package_name, pads=local_pads, connections=connections, pins=pins_by_gate)
        data = device_cache[key]
        if data['package']:
            require(name in elements and elements[name].attrib['library'] == lib
                    and elements[name].attrib['package'] == data['package'], 'PAIR_ELEMENT', 'Part/device package does not match board element')
            board_pads = pads(board_libs[lib]['packages'][data['package']])
            require(set(board_pads) == set(data['pads'])
                    and all(board_pads[pad].tag == data['pads'][pad].tag
                            and point(board_pads[pad]) == point(data['pads'][pad]) for pad in board_pads),
                    'PAIR_PACKAGE', 'Selected board/schematic package pad names/local coordinates differ')
        else:
            require(name not in elements and not data['connections'], 'PAIR_SYMBOL', 'Package-less symbol cannot become a board element/contact')
        part_data[name] = data
        index.add(dict(kind='schematic_part', **reference(pair, 'schematic', ['parts', name]), raw=dict(part.attrib),
                       selected_device_ref=reference(pair, 'schematic', ['libraries', lib, 'devicesets', ds, 'devices', selection]),
                       selected_package=data['package'], package_present=bool(data['package']),
                       electrical_device=bool(data['connections'])))
    sch_nets = {}
    for sheet in one(schematic, 'sheets'):
        require(sheet.tag == 'sheet', 'SCHEMATIC', 'Unexpected sheet record')
        for net in ([] if one(sheet, 'nets', False) is None else one(sheet, 'nets')):
            require(net.tag == 'net' and 'name' in net.attrib, 'NET', 'Named net required')
            net_name = net.attrib['name']
            sch_nets.setdefault(net_name, [])
            for segment in net:
                require(segment.tag == 'segment', 'NET', 'Only explicit net segments admitted')
                for pinref in segment:
                    if pinref.tag != 'pinref':
                        continue
                    part, gate, pin = (pinref.attrib[key] for key in ('part', 'gate', 'pin'))
                    data = part_data[part]
                    require(gate in data['pins'] and pin in data['pins'][gate]
                            and (part, gate, pin) not in pin_nets, 'PINREF', 'Missing/duplicate/ambiguous actual schematic pinref')
                    pin_nets[(part, gate, pin)] = net_name
                    mapped = data['connections'].get((gate, pin), [])
                    require(not data['package'] or mapped, 'PINREF', 'Physical pinref lacks its selected device pad mapping')
                    for pad in mapped:
                        target = (part, pad)
                        require(target not in expected or expected[target] == net_name, 'NET', 'One board pad maps to conflicting schematic nets')
                        expected[target] = net_name
                    sch_nets[net_name].append(dict(part=part, gate=gate, pin=pin, pads=mapped,
                                                   package_less=not bool(data['package'])))
    for signal in one(board, 'signals'):
        require(signal.tag == 'signal' and 'name' in signal.attrib, 'SIGNAL', 'Named board signal required')
        for contact in signal:
            if contact.tag != 'contactref':
                continue
            target = (contact.attrib['element'], contact.attrib['pad'])
            require(target not in board_contacts, 'CONTACT', 'Duplicate board contactref')
            board_contacts[target] = signal.attrib['name']
    require(expected == board_contacts, 'PAIR_CONTACTS', 'Structural schematic pin-to-pad nets differ from actual board contacts')
    for name, data in part_data.items():
        for (gate, pin), mapped in data['connections'].items():
            net = pin_nets.get((name, gate, pin))
            index.add(dict(kind='device_pin', **reference(pair, 'schematic', ['parts', name, 'gates', gate, 'pins', pin]),
                           part=name, gate=gate, pin=pin, pads=mapped, declared_net=net,
                           state='pinref_present' if net is not None else 'source_pinref_absent',
                           all_mapped_pads_unconnected=all((name, pad) not in board_contacts for pad in mapped)))
    for name, refs in sch_nets.items():
        index.add(dict(kind='net', **reference(pair, 'schematic', ['nets', name]), name=name, pinrefs=refs))
    classes = Counter()
    package_seen = set()
    for name, element in elements.items():
        lib, package_name = element.attrib['library'], element.attrib['package']
        package = board_libs[lib]['packages'][package_name]
        data = part_data.get(name)
        category = 'electrical_device' if data and data['connections'] else ('packaged_without_connects' if data else 'board_only_unmapped')
        classes[category] += 1
        package_ref = reference(pair, 'board', ['libraries', lib, 'packages', package_name])
        if (lib, package_name) not in package_seen:
            package_seen.add((lib, package_name))
            index.add(dict(kind='board_package', **package_ref, library=lib, package=package_name,
                           raw=dict(package.attrib), pad_names=list(pads(package))))
        index.add(dict(kind='board_element', **reference(pair, 'board', ['elements', name]), raw=dict(element.attrib),
                       package_ref=package_ref, category=category))
        for pad_name, pad in pads(package).items():
            refs = [] if data is None else [dict(gate=gate, pin=pin) for (gate, pin), values in data['connections'].items() if pad_name in values]
            index.add(dict(kind='board_pad', **reference(pair, 'board', ['elements', name, 'package', lib, package_name, pad.tag, pad_name]),
                           element=name, package=package_name, library=lib, pad=pad_name, primitive=pad.tag,
                           reference_kind='instanced_pad_binding_not_an_XPath',
                           definition_ref=reference(pair, 'board', ['libraries', lib, 'packages', package_name, pad.tag, pad_name]),
                           element_ref=reference(pair, 'board', ['elements', name]),
                           raw=dict(pad.attrib), placement=dict(element.attrib), logical_pins=refs,
                           net=board_contacts.get((name, pad_name)), category=category))
    return elements, board_libs, board_contacts, dict(parts=len(parts), elements=len(elements),
            element_classes=dict(classes), board_contacts=len(board_contacts), nets=len(sch_nets),
            schematic_pinrefs=len(pin_nets), electrical_pads=sum(len(pads(board_libs[e.attrib['library']]['packages'][e.attrib['package']]))
                for name, e in elements.items() if name in part_data and part_data[name]['connections']))


def project_layout(board, drawing, schematic, elements, libraries, contacts, pair, budget):
    objects = Budget(budget.deadline)
    excluded = Counter()
    points = 0
    layers = {}
    for layer in one(drawing, 'layers'):
        require(layer.tag == 'layer' and layer.attrib.get('number', '').isdigit()
                and 0 <= int(layer.attrib['number']) <= 255 and layer.attrib['number'] not in layers,
                'LAYER', 'Duplicate/invalid declared source layer')
        layers[layer.attrib['number']] = dict(layer.attrib)

    def exclude(scope, tag, reason, count=1):
        excluded[(scope, tag, reason)] += count

    def add(kind, path, coords, raw, layer=None, **metadata):
        nonlocal points
        require(len(objects.records) < MAX_OBJECTS and points + len(coords) <= MAX_POINTS,
                'LAYOUT_BUDGET', 'Adapter object/point budget exceeded; nothing is silently truncated')
        require(layer is None or layer in layers, 'LAYER', 'Geometry references undeclared source layer')
        exact = [[str(x), str(y)] for x, y in coords]
        approx = [[float(x), float(y)] for x, y in coords]
        require(all(math.isfinite(value) for xy in approx for value in xy), 'VIEW_COORDINATES', 'Nonfinite approximate view coordinate')
        objects.add(dict(kind=kind, **reference(pair, 'board', path), exact_mm=exact,
                         approximate_view_mm=approx, raw=raw, layer=layer, **metadata))
        points += len(coords)

    outline = []
    for ordinal, primitive in enumerate(one(board, 'plain')):
        if primitive.tag == 'wire' and primitive.attrib.get('layer') == '20':
            if 'curve' in primitive.attrib and number(primitive, 'curve') != 0:
                exclude('plain', 'wire', 'curved_outline_unsupported')
                continue
            outline.append((ordinal, primitive, [point(primitive, 'x1', 'y1'), point(primitive, 'x2', 'y2')]))
        else:
            exclude('plain', primitive.tag, 'outside_first_plain_subset')
    require(len(outline) == 4, 'OUTLINE', 'First subset requires four supported outline segments; supported=' + str(len(outline))
            + ', curved_excluded=' + str(excluded[('plain', 'wire', 'curved_outline_unsupported')]))
    all_points = [xy for _, _, segment in outline for xy in segment]
    xmin, xmax = min(x for x, y in all_points), max(x for x, y in all_points)
    ymin, ymax = min(y for x, y in all_points), max(y for x, y in all_points)
    rectangle = [(xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax)]
    expected = {frozenset((rectangle[i], rectangle[(i + 1) % 4])) for i in range(4)}
    require(xmin < xmax and ymin < ymax and {frozenset(segment) for _, _, segment in outline} == expected,
            'OUTLINE', 'Outline is not the admitted exact source rectangle')
    for ordinal, primitive, coords in outline:
        add('outline_definition', ['plain', 'wire', ordinal], coords, dict(primitive.attrib), '20')
    for net, signal in named(one(board, 'signals'), 'signal').items():
        for ordinal, primitive in enumerate(signal):
            path = ['signals', net, primitive.tag, ordinal]
            if primitive.tag == 'contactref':
                continue
            if primitive.tag == 'via':
                add('via_centre', path, [point(primitive)], dict(primitive.attrib), None, net=net,
                    copper_diameter='NOT_INFERRED', extent=primitive.attrib.get('extent'))
            elif primitive.tag == 'wire':
                if 'curve' in primitive.attrib and number(primitive, 'curve') != 0:
                    exclude('signal', 'wire', 'curved_wire_unsupported')
                else:
                    add('trace_centreline', path, [point(primitive, 'x1', 'y1'), point(primitive, 'x2', 'y2')],
                        dict(primitive.attrib), primitive.attrib['layer'], net=net, copper_fill='NOT_RESOLVED')
            elif primitive.tag == 'polygon':
                vertices = list(primitive)
                require(3 <= len(vertices) <= 4096 and all(v.tag == 'vertex' for v in vertices),
                        'POLYGON', 'Finite explicit polygon vertex list required')
                if any('curve' in vertex.attrib and number(vertex, 'curve') != 0 for vertex in vertices):
                    exclude('signal', 'polygon', 'curved_polygon_unsupported')
                else:
                    add('polygon_boundary_definition', path, [point(vertex) for vertex in vertices],
                        dict(primitive.attrib), primitive.attrib['layer'], net=net, closed=True,
                        vertex_raw=[dict(vertex.attrib) for vertex in vertices], copper_fill='NOT_RESOLVED')
            else:
                exclude('signal', primitive.tag, 'unsupported_signal_primitive')
    for name, element in elements.items():
        package = libraries[element.attrib['library']]['packages'][element.attrib['package']]
        for primitive in package:
            if primitive.tag not in {'smd', 'pad'}:
                reason = 'package_artwork_not_projected'
                if rotation(element) is None:
                    reason = 'package_artwork_with_unsupported_element_transform'
                elif primitive.tag == 'wire' and 'curve' in primitive.attrib and number(primitive, 'curve') != 0:
                    reason = 'curved_package_artwork_not_projected'
                exclude('placed_package', primitive.tag, reason)
                continue
            if rotation(element) is None or rotation(primitive) is None:
                exclude('placed_package', primitive.tag, 'mirrored_fractional_or_spin_rotation_unsupported')
                continue
            pad = primitive.attrib['name']
            path = ['elements', name, 'package', element.attrib['library'], element.attrib['package'], primitive.tag, pad]
            add('pad_centre', path, [place(element, point(primitive))], dict(primitive.attrib),
                primitive.attrib.get('layer'), element=name, pad=pad, net=contacts.get((name, pad)),
                placement=dict(element.attrib), exact_element_degrees=rotation(element), exact_pad_degrees=rotation(primitive),
                reference_kind='instanced_pad_binding_not_an_XPath',
                definition_ref=reference(pair, 'board', ['libraries', element.attrib['library'], element.attrib['package'], primitive.tag, pad]),
                element_ref=reference(pair, 'board', ['elements', name]),
                copper_shape='NOT_RESOLVED', primitive=primitive.tag)
    geometry_tags = {'wire', 'polygon', 'rectangle', 'circle', 'text', 'smd', 'pad', 'hole', 'frame', 'label', 'junction', 'pin', 'instance'}
    for primitive in schematic.iter():
        if primitive.tag in geometry_tags:
            exclude('schematic', primitive.tag, 'schematic_geometry_not_projected')
    return dict(schema='gxtxt.eagle_pair_layout.v1', pair_stamp=pair, units='mm',
                unit_policy='qualified-historical-XML-mm-orthogonal-subset.v1', layers=layers,
                fit_outline_exact_mm=[str(xmin), str(ymin), str(xmax), str(ymax)], objects=objects.records,
                fit_outline_approximate_view_mm=[float(xmin), float(ymin), float(xmax), float(ymax)],
                actual_object_count=len(objects.records), actual_point_count=points,
                supported_counts=dict(Counter(row['kind'] for row in objects.records)),
                excluded=[dict(scope=scope, primitive=tag, reason=reason, count=count)
                          for (scope, tag, reason), count in sorted(excluded.items())],
                adapter_object_budget=MAX_OBJECTS, adapter_point_budget=MAX_POINTS,
                visible_point_budget=VISIBLE_POINT_BUDGET, all_geometry_visible_guaranteed=False,
                exceeds_visible_point_budget=points > VISIBLE_POINT_BUDGET,
                library_definition_projection='Only placed pad centres expanded; no full package/artwork/copper coverage',
                limitations=LIMITATIONS)


def pair_stamp(records):
    framed = bytearray(b'gxtxt.eagle_pair.v1\x00')
    for role in ('board', 'schematic'):
        for field in (role, str(records[role]['bytes']), records[role]['sha256']):
            value = field.encode('ascii')
            framed.extend(len(value).to_bytes(4, 'big'))
            framed.extend(value)
    return digest(framed)


def request_from_stdin(paths, workdir):
    raw = sys.stdin.buffer.read(16385)
    require(len(raw) <= 16384, 'REQUEST', 'Managed request exceeds16KiB')
    request = json.loads(raw.decode('utf-8'), object_pairs_hook=no_duplicate_pairs)
    require(isinstance(request, dict) and set(request) == {'schema', 'request_id', 'workdir', 'board', 'schematic'}
            and request['schema'] == 'gxtxt.eagle_pair_worker_request.v1'
            and isinstance(request['request_id'], str)
            and re.fullmatch(r'[A-Za-z0-9_-]{1,96}', request['request_id']) is not None
            and request['workdir'] == str(workdir) and len(str(workdir)) <= 4096
            and '\n' not in str(workdir) and '\r' not in str(workdir), 'REQUEST', 'Exact finite parent request required')
    identity_fields = set(identity(os.stat(__file__)))
    for role, path in paths.items():
        row = request[role]
        require(isinstance(row, dict) and set(row) == {'path', 'sha256', 'bytes', 'identity'}
                and row['path'] == str(path) and len(row['path']) <= 4096
                and '\n' not in row['path'] and '\r' not in row['path']
                and row['sha256'] == APPROVED[role] and type(row['bytes']) is int
                and 0 < row['bytes'] <= MAX_SOURCE and isinstance(row['identity'], dict)
                and set(row['identity']) == identity_fields
                and all(type(value) is int for value in row['identity'].values()),
                'REQUEST', 'Unapproved or malformed parent source identity')
    return request


def prepare(paths, output, request):
    require(output.is_absolute() and not output.exists() and not output.is_symlink()
            and output.parent == output.parent.resolve(strict=True) and output.parent.is_relative_to(RAID),
            'OUTPUT', 'Absent allocated real RAID workdir required')
    parent = output.parent.stat()
    require(parent.st_uid == os.geteuid() and stat.S_IMODE(parent.st_mode) == 0o700
            and parent.st_dev == RAID.stat().st_dev, 'OUTPUT', 'Owned private0700 RAID Resource parent required')
    mounts = []
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        left, right = line.split(' - ', 1)
        mount = Path(left.split()[4])
        if mount == output.parent or mount in output.parent.parents:
            fields = right.split()
            mounts.append((len(str(mount)), mount, fields[0], fields[1]))
    require(bool(mounts), 'STORAGE', 'No Resource mount identity')
    _, mount, filesystem, device = max(mounts)
    require(mount == RAID and filesystem == 'ext4' and device.startswith('/dev/md'),
            'STORAGE', 'Actual task MD/ext4 RAID mount required')
    free = os.statvfs(output.parent)
    require(free.f_bavail * free.f_frsize >= 134217728 and free.f_favail >= 1024,
            'STORAGE', '128MiB/1024 free inodes required before staging')
    output.mkdir(mode=0o700)
    artifacts = []
    staged_bytes = [0]
    records = {}
    budget = Budget(time.monotonic() + 60)
    try:
        for role, path in paths.items():
            require(path.suffix.lower() == ('.brd' if role == 'board' else '.sch'), 'PAIR_ROLE', 'Expected explicit board/schematic file role')
            raw, stamp = read_regular(path, MAX_SOURCE)
            expected = request[role]
            require(stamp == expected['identity'] and len(raw) == expected['bytes']
                    and digest(raw) == expected['sha256'], 'SOURCE_CHANGED', 'Authorized source identity/hash/bytes changed')
            row = write_exclusive(output, role + '.original' + path.suffix.lower(), raw, MAX_SOURCE,
                                  staged_bytes=staged_bytes)
            artifacts.append(row)
            records[role] = dict(path=str(path), original_name=path.name, sha256=row['sha256'],
                                 bytes=row['bytes'], original_identity=stamp, copy=row['name'])
        pair = pair_stamp(records)
        board_raw, _ = read_regular(output / records['board']['copy'], MAX_SOURCE)
        schematic_raw, _ = read_regular(output / records['schematic']['copy'], MAX_SOURCE)
        board, drawing, board_policy = parse_staged(board_raw, 'board', budget)
        schematic, _, schematic_policy = parse_staged(schematic_raw, 'schematic', budget)
        with localcontext() as context:
            context.prec = 96
            elements, libraries, contacts, counts = reconcile(board, schematic, pair, budget)
            layout = project_layout(board, drawing, schematic, elements, libraries, contacts, pair, budget)
        index = dict(schema='gxtxt.eagle_pair_index.v1', pair_stamp=pair, records=budget.records,
                     counts=counts, source_xml=dict(board=board_policy, schematic=schematic_policy),
                     structural_pair_reconciled=True, scientific_or_manufacturing_validation=False,
                     limitations=LIMITATIONS)
        license_raw, _ = read_regular(LICENSE, 65536)
        require(digest(license_raw) == LICENSE_SHA, 'LICENSE', 'Unchanged bundled SparkFun license notice required')
        artifacts.append(write_exclusive(output, 'SOURCE_LICENSE.md', license_raw, 65536,
                                         staged_bytes=staged_bytes))
        attribution = dict(schema='gxtxt.eagle_pair_attribution.v1', creator='SparkFun Electronics',
                           upstream=UPSTREAM, upstream_commit=UPSTREAM_COMMIT,
                           hardware_license='CC-BY-SA-4.0', license_url='https://creativecommons.org/licenses/by-sa/4.0/',
                           unchanged_notice='SOURCE_LICENSE.md', unchanged_notice_sha256=LICENSE_SHA,
                           original_sources='Unchanged full board/schematic bytes; original names/identities retained in receipt',
                           adaptations='GX-TXT finite structural index, decimal mm projection and explicit exclusions',
                           derived_index_layout_license='CC-BY-SA-4.0', endorsement='No SparkFun endorsement implied',
                           framework_code_license='Separate GPL-3.0-or-later; not applied to upstream hardware resources')
        for name, value in (('attribution.json', attribution), ('index.json', index), ('layout.json', layout)):
            budget.check()
            row = write_exclusive(output, name, encoded(value), staged_bytes=staged_bytes)
            artifacts.append(row)
            if name in {'index.json', 'layout.json'}:
                kind = name.removesuffix('.json')
                mirror = tcl_data_mirror(kind, value, row)
                budget.check()
                artifacts.append(write_exclusive(output, kind + '.tcldict', mirror,
                                                 staged_bytes=staged_bytes))
        for role, path in paths.items():
            raw, stamp = read_regular(path, MAX_SOURCE)
            require(stamp == request[role]['identity'] and digest(raw) == records[role]['sha256'],
                    'SOURCE_CHANGED', 'Original changed before staged completion; parent must still recheck after last yield')
        for artifact in artifacts:
            raw, stamp = read_regular(output / artifact['name'], MAX_JSON)
            require(digest(raw) == artifact['sha256'] and len(raw) == artifact['bytes'] and stamp['mode'] == artifact['mode'],
                    'RESOURCE_CHANGED', 'Staged artifact changed before completion')
        budget.check()
        receipt = dict(schema='gxtxt.eagle_pair_worker_receipt.v1', status='PREPARED_STAGED_SOURCE_ONLY',
                       parser=VERSION, worker_sha256=digest(Path(__file__).read_bytes()), request_id=request['request_id'],
                       worker_pid=os.getpid(), owned_process_group=os.getpgrp(),
                       pair_stamp=pair, originals=records, artifacts=artifacts, structural_counts=counts,
                       artifact_limits=dict(per_json_or_tcl_bytes=MAX_JSON,
                                            per_original_bytes=MAX_SOURCE, per_notice_bytes=65536,
                                            cumulative_attempted_bytes=MAX_STAGED_BYTES,
                                            expected_success_file_count=10,
                                            prior_artifact_count=len(artifacts),
                                            attempted_bytes_before_receipts=staged_bytes[0],
                                            receipt_inventory='Prior artifacts only; final receipt identities are in stdout'),
                       original_recheck='Worker-time exact identity+SHA only; parent final post-yield recheck still mandatory',
                       canonical_document_written=False, complete_transition_performed=False,
                       supported_counts=layout['supported_counts'], excluded=layout['excluded'],
                       visible_point_budget=VISIBLE_POINT_BUDGET, actual_point_count=layout['actual_point_count'],
                       limitations=LIMITATIONS)
        row = write_exclusive(output, 'receipt.json', encoded(receipt), staged_bytes=staged_bytes)
        mirror = tcl_data_mirror('receipt', receipt, row)
        budget.check()
        mirror_row = write_exclusive(output, 'receipt.tcldict', mirror, staged_bytes=staged_bytes)
        budget.check()
        return dict(status=receipt['status'], request_id=request['request_id'], pair_stamp=pair,
                    workdir=str(output), receipt_sha256=row['sha256'], receipt='receipt.json',
                    receipt_json_artifact=row, receipt_tcl_artifact=mirror_row,
                    cumulative_artifact_bytes=staged_bytes[0],
                    canonical_document_written=False)
    except Exception as error:
        if not (output / 'receipt.json').exists():
            failure = dict(schema='gxtxt.eagle_pair_worker_receipt.v1', status='FAILED_PARTIAL_STAGING_PRESERVED',
                           error=(type(error).__name__ + ': ' + str(error))[:4096], request_id=request['request_id'], originals=records,
                           artifacts=artifacts, canonical_document_written=False, complete_transition_performed=False)
            try:
                write_exclusive(output, 'receipt.json', encoded(failure), staged_bytes=staged_bytes)
            except Exception as receipt_error:
                raise AdmissionError(getattr(error, 'code', 'INVALID_SOURCE'),
                                     failure['error'] + '; failure receipt unavailable: '
                                     + type(receipt_error).__name__ + ': ' + str(receipt_error)[:1024]) from error
        raise


def main():
    os.umask(0o077)
    try:
        require(sys.flags.isolated and sys.dont_write_bytecode, 'CLI', 'Use normal isolated python3 -I -B')
        # Supplemental Unix worker bounds, not measured RSS/performance proof.
        # Never raise a caller's existing lower soft/hard limit.
        for kind, cap in ((resource.RLIMIT_AS, 268435456), (resource.RLIMIT_FSIZE, 20971520)):
            soft, hard = resource.getrlimit(kind)
            values = [cap] + [value for value in (soft, hard) if value != resource.RLIM_INFINITY]
            resource.setrlimit(kind, (min(values), hard))
        require(len(sys.argv) == 4, 'CLI', 'Expected BOARD.brd SCHEMATIC.sch ABSENT_RESOURCE_WORKDIR')
        paths = dict(board=Path(sys.argv[1]), schematic=Path(sys.argv[2]))
        output = Path(sys.argv[3])
        request = request_from_stdin(paths, output)
        result = prepare(paths, output, request)
        response = dict(ok=True, result=result)
        code = 0
    except Exception as error:
        response = dict(ok=False, error=(type(error).__name__ + ': ' + str(error))[:4096],
                        errorcode=['GX', 'EAGLE_PAIRED_SOURCE', getattr(error, 'code', 'INVALID_SOURCE')])
        code = 1
    message = tcl_result(response)
    require(len(message.encode('utf-8')) <= 65536, 'RESPONSE', 'Managed response exceeds64KiB')
    sys.stdout.buffer.write(message.encode('utf-8') + b'\n')
    sys.stdout.buffer.flush()
    return code


if __name__ == '__main__':
    request_process_group()
    raise SystemExit(main())
