#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original analytic sources; no CAD engine, solver or Workbench import."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import zlib

from session_recipe import configure

BOX_VERTICES = [(0, 0, 0), (20, 0, 0), (20, 10, 0), (0, 10, 0),
                (0, 0, 6), (20, 0, 6), (20, 10, 6), (0, 10, 6)]
# Consistent outward winding. The final two triangles are the z=6 top face.
BOX_FACES = [(0, 2, 1), (0, 3, 2), (0, 1, 5), (0, 5, 4),
             (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6),
             (3, 0, 4), (3, 4, 7), (4, 5, 6), (4, 6, 7)]
TETRA_VERTICES = [(0, 0, 0), (6, 0, 0), (0, 8, 0), (0, 0, 10)]
TETRA_FACES = [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)]


def stl(path, vertices, faces):
    lines = ['solid original_analytic_mm']
    for face in faces:
        a, b, c = [vertices[i] for i in face]
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
        length = math.sqrt(sum(x*x for x in n))
        lines.append('  facet normal ' + ' '.join(format(x/length, '.17g') for x in n))
        lines.append('    outer loop')
        lines.extend('      vertex ' + ' '.join(str(x) for x in p) for p in (a, b, c))
        lines.extend(['    endloop', '  endfacet'])
    path.write_text('\n'.join(lines + ['endsolid original_analytic_mm', '']), encoding='ascii')


def rgba(path):
    """64x64 original calibration image, RGBA8; no ancillary metadata."""
    pixels = bytearray()
    for y in range(64):
        for x in range(64):
            # Visible orientation, four distinct alpha bands, exact pixel corners.
            color = (x*4, y*4, 255-x*4, (0, 85, 170, 255)[x//16])
            if x in (8, 56) and y in (8, 56):
                color = (255, 0, 0, 255)
            pixels.extend(color)

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))

    rows = b''.join(b'\0' + pixels[y*256:(y+1)*256] for y in range(64))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 6, 0, 0, 0))
    path.write_bytes(png + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))
    return hashlib.sha256(pixels).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    args = parser.parse_args()
    root = Path(args.target_session).resolve()
    if not root.is_dir():
        raise ValueError('The normal host must supply an existing fresh target Session')
    names = ['box_closed_mm.stl', 'box_open_mm.stl', 'tetrahedron_mm.stl',
             'rectangle_mm.csv', 'calibration_rgba.png']
    if any((root/'raw'/name).exists() for name in names) or (root/'STUDENT_GUIDE.md').exists():
        raise FileExistsError('Refusing existing practice sources')
    (root/'raw').mkdir(exist_ok=True)
    (root/'reference').mkdir(exist_ok=True)
    stl(root/'raw'/names[0], BOX_VERTICES, BOX_FACES)
    stl(root/'raw'/names[1], BOX_VERTICES, BOX_FACES[:-2])
    stl(root/'raw'/names[2], TETRA_VERTICES, TETRA_FACES)
    (root/'raw'/names[3]).write_text('x_mm,y_mm\n0,0\n20,0\n20,10\n0,10\n', encoding='ascii')
    pixel_sha = rgba(root/'raw'/names[4])
    truth = {
        'reference_kind': 'independent analytic source specification, not computed analysis',
        'license': 'GPL-3.0-or-later; original synthetic coordinates and image',
        'length_unit': 'mm', 'stl_unit_policy': 'STL is unitless; explicitly declare input mm',
        'box_closed': {'bounds_mm': [[0, 0, 0], [20, 10, 6]], 'triangles': 12,
                       'area_mm2': 760, 'volume_mm3': 1200, 'boundary_edges': 0},
        'box_open': {'missing_face': 'z=6 top, area 200 mm^2', 'triangles': 10,
                     'area_mm2': 560, 'volume_mm3': None, 'boundary_edges': 4,
                     'boundary_loops': 1, 'boundary_length_mm': 60},
        'tetrahedron': {'axis_intercepts_mm': [6, 8, 10], 'triangles': 4,
                        'bounds_mm': [[0, 0, 0], [6, 8, 10]], 'volume_mm3': 80,
                        'surface_area_formula_mm2': '24+30+40+sqrt(80^2+60^2+48^2)/2',
                        'boundary_edges': 0},
        'profile': {'source': 'rectangle_mm.csv', 'closure': 'last point to first, explicitly closed',
                    'orientation': 'counterclockwise in XY viewed from +Z',
                    'area_mm2': 200, 'perimeter_mm': 60,
                    'extrusion_6_mm_volume_mm3': 1200},
        'image': {'width': 64, 'height': 64, 'color_type': 'RGBA8', 'rgba_sha256': pixel_sha,
                  'pixel_origin': 'top left; integer pixel centres',
                  'fiducials_pixel_xy': [[8, 56], [56, 56], [8, 8], [56, 8]],
                  'fiducials_physical_xy_mm': [[0, 0], [20, 0], [0, 10], [20, 10]],
                  'mapping': 'x_mm=(pixel_x-8)*20/48; y_mm=(56-pixel_y)*10/48',
                  'explicit_decorative_size_mm': [20, 10],
                  'decorative_resize_is_calibration': False},
        'source_sha256': {name: hashlib.sha256((root/'raw'/name).read_bytes()).hexdigest() for name in names},
        'excluded': ['STEP/B-Rep source', 'completed Workspaces', 'precomputed analysis', 'Jobs'],
    }
    (root/'reference/cad_truth.json').write_text(json.dumps(truth, indent=2)+'\n', encoding='utf-8')
    sources = [dict(source='raw/'+name, id='cad.'+name.removesuffix('.stl'), binary=True,
                    kind='geometry.mesh', format='stl', media_type='application/octet-stream') for name in names[:3]]
    sources.extend([
        dict(source='raw/rectangle_mm.csv', id='cad.rectangle', kind='table.generic',
             units={'x_mm': 'mm', 'y_mm': 'mm'}, roles={'x_mm': 'independent', 'y_mm': 'independent'},
             variable_ids={'x_mm': 'x_mm', 'y_mm': 'y_mm'}),
        dict(source='raw/calibration_rgba.png', id='cad.calibration.image', binary=True,
             kind='image.raster', format='png', media_type='image/png')])
    configure(root, 'cad_geometry_practice', sources, [], 'Independent CAD geometry practice')
    shutil.copyfile(Path(__file__).with_name('STUDENT_GUIDE.md'), root/'STUDENT_GUIDE.md')
    print('Generated independent CAD raw sources and analytic references; no completed geometry')


if __name__ == '__main__':
    main()
