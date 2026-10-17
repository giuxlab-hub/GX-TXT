#!/usr/bin/env python3
"""Independent source-only raster; standard library, no scientific module imports."""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import struct
import zlib

from session_recipe import configure

POINTS = [
    ('point-1', 30, 70, 2.0, -1.0),
    ('point-2', 60, 40, 5.0, 0.5),
    ('point-3', 75, 65, 6.5, -0.75),
    ('point-4', 40, 25, 3.0, 1.25),
]


def write_image(path):
    width = height = 100
    pixels = bytearray([255]) * (width * height * 3)

    def dot(x, y, color):
        start = 3 * (y * width + x)
        pixels[start:start+3] = bytes(color)

    for grid in range(10, 91, 10):
        for p in range(10, 91):
            dot(grid, p, (215, 215, 215))
            dot(p, grid, (215, 215, 215))
    for p in range(10, 91):
        for edge in (10, 90):
            dot(edge, p, (0, 0, 0))
            dot(p, edge, (0, 0, 0))
    for _, x, y, _, _ in POINTS:
        for delta in range(-2, 3):
            dot(x+delta, y, (0, 72, 180))
            dot(x, y+delta, (0, 72, 180))

    def chunk(kind, data):
        return struct.pack('>I',len(data)) + kind + data + struct.pack('>I',zlib.crc32(kind+data))

    rows = b''.join(b'\0'+pixels[y*width*3:(y+1)*width*3] for y in range(height))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))
    png += chunk(b'IDAT',zlib.compress(rows,9)) + chunk(b'IEND',b'')
    path.write_bytes(png)
    return hashlib.sha256(pixels).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target-session', required=True)
    parser.add_argument('--library-id')
    parser.add_argument('--generator-id')
    args = parser.parse_args()
    root = Path(args.target_session)
    for part in ('raw','reference'):
        (root/part).mkdir(parents=True,exist_ok=True)
    image = root/'raw/calibrated_curve.png'
    table = root/'raw/calibration_points.csv'
    if image.exists() or table.exists():
        raise FileExistsError('Refuse existing source image or reference points')
    pixel_hash = write_image(image)
    with table.open('x',newline='',encoding='utf-8') as stream:
        writer = csv.writer(stream,lineterminator='\n')
        writer.writerow(['point_id','pixel_x','pixel_y','time_s','voltage_V'])
        writer.writerows(POINTS)
    truth = {
        'schema':'gxtxt.calibrated_digitizer.reference.v1',
        'synthetic':True, 'random_seed':None, 'determinism':'fixed coordinates; no randomness',
        'image':{'dataset_id':'digitizer.calibration.image','width':100,'height':100,
                 'rgb_sha256':pixel_hash,'png_sha256':hashlib.sha256(image.read_bytes()).hexdigest()},
        'point_dataset_id':'digitizer.calibration.points',
        'point_order':[p[0] for p in POINTS],
        'corners':{'bottom_left':[10,90],'bottom_right':[90,90],
                   'top_left':[10,10],'top_right':[90,10]},
        'physical_axes':{'x':{'label':'Time','unit':'s','minimum':0,'maximum':8,'scale':'linear'},
                         'y':{'label':'Voltage','unit':'V','minimum':-2,'maximum':2,'scale':'linear'}},
        'analytical_mapping':{'x':'(pixel_x-10)/10','y':'(50-pixel_y)/20'},
        'independent_quantization':{'distribution':'rectangular_full_width','pixel_widths':[1,2],
                                    'fixed_calibration':True,
                                    'expected_standard_uncertainty':[0.02886751345948129,0.02886751345948129],
                                    'expected_cross_covariance':0},
        'physical_override':{'standard_uncertainty':[0.3,0.7],
                             'rationale':'Explicit independent physical uncertainties for comparison'},
        'invalid_cases':[
            {'name':'coincident_corners','expectation':'Reject degenerate calibration'},
            {'name':'negative_pixel_width','expectation':'Reject invalid uncertainty input'},
            {'name':'changed_point_order','expectation':'Refuse stale publication identity'},
            {'name':'shared_calibration_as_independent_sigma','expectation':'Require shared covariance treatment'},
        ],
        'licensing':'GPL-3.0-or-later; original synthetic image and reference data',
        'purpose':'Independent test references; scientific modules must not consume this reference file as computed results',
    }
    (root/'reference/calibration_truth.json').write_text(json.dumps(truth,indent=2)+'\n')
    configure(root,'calibrated_digitizer',[
        dict(source='raw/calibrated_curve.png',id='digitizer.calibration.image',binary=True,
             kind='image.raster',format='png',media_type='image/png'),
        dict(source='raw/calibration_points.csv',id='digitizer.calibration.points',kind='table.generic',
             units={'pixel_x':'px','pixel_y':'px','time_s':'s','voltage_V':'V'},
             roles={'pixel_x':'independent','pixel_y':'measured','time_s':'reference','voltage_V':'reference'},
             variable_ids={name:name for name in ['point_id','pixel_x','pixel_y','time_s','voltage_V']}),
    ],[],'Independent calibrated curve digitization')
    shutil.copyfile(Path(__file__).with_name('STUDENT_GUIDE.md'),root/'STUDENT_GUIDE.md')
    print('Generated independent calibrated image and four ordered reference points')


if __name__=='__main__':
    main()
