#!/usr/bin/env python3
"""Synthetic 60,000-row Digitalizer publication packets using installed domain owners."""
from pathlib import Path
import base64
import copy
import hashlib
import json
import sys
from PIL import Image, ImageDraw

root, out = (Path(p).resolve() for p in sys.argv[1:])
out.mkdir(exist_ok=False)
sys.path.insert(0, str(root / 'plugins/modules/viewer.curve_digitizer/python'))
from digitizer_model import Project, AxisConfig, Series, DigitizedPoint, CORNER_ORDER
from gxtxt_curve_digitizer import CurveDigitizerApp
from calibration_manifest import build_manifest, metadata_fields, encode_metadata_records
from quality_diagnostics import inspect as inspect_quality
from uncertainty_engine import propagate, compact_factors

image = Image.new('RGB', (100, 100), 'white')
ImageDraw.Draw(image).line([(20, 80), (40, 60), (60, 40), (80, 20)], fill='black', width=2)
image.save(out / 'image.png')
sha = hashlib.sha256((out / 'image.png').read_bytes()).hexdigest()
b64 = lambda v: base64.b64encode(str(v).encode()).decode()
for mode in ('none',):
    p = Project()
    p.x_axis = AxisConfig('Time', 's', 0, 8, 'linear')
    p.y_axis = AxisConfig('Voltage', 'V', -2, 2, 'linear')
    for name, xy in zip(CORNER_ORDER, [(10, 90), (90, 90), (10, 10), (90, 10)]):
        p.calibration.set_corner(name, *xy)
    for j in range(20):
        series = Series(id=f'curve103-{j}', name='Duplicate human label', parameter_value=str(280 + j*20), parameter_name='Temperature', parameter_unit='K')
        for i in range(1500):
            import math
            x=12+76*i/1499
            y=15+3*j+2*math.sin(i/120)
            pt = DigitizedPoint(id=f'point103-{j}-{i}', manual_pixel_x=x, manual_pixel_y=y+j*3, pixel_x=x, pixel_y=y+j*3)
            p.update_point_calibration(pt)
            series.points.append(pt)
        p.series.append(series)
    cfg = CurveDigitizerApp.new_configuration('Synthetic dev103 load test ' + mode)
    cfg.update(source=dict(dataset_id='image103', sha256=sha, width=100, height=100),
               axes=dict(x=p.x_axis.to_dict(), y=p.y_axis.to_dict()),
               calibration=p.calibration.to_dict(), curves=[s.to_dict() for s in p.series])
    mids = ['meas_' + '1'*32, 'meas_' + '2'*32] if mode == 'none' else ['meas_' + '1'*32]
    items = [dict(id=mid, label=f'Calibration realization {i+1}', state='accepted', axes=cfg['axes'], calibration=cfg['calibration'], scale_reference=None) for i, mid in enumerate(mids)]
    cfg['calibration_measurements'] = dict(group_id='calgroup098', active_id=mids[0], items=items)
    layout = 'combined' if mode == 'none' else 'separate'
    spec = dict(mode='pixel_calibration', pixel_distribution='normal_standard_uncertainty', pixel_scale=[0, 0], calibration_standard_uncertainty=[0]*12,
                rationale='Disposable integration fixture: explicitly declared exact raster localization and independently declared calibration evidence.')
    if mode == 'zero_shared':
        spec['calibration_standard_uncertainty'] = [.1]*12
    elif mode == 'one_zero':
        spec['pixel_scale'] = [0, 2]
    elif mode == 'independent':
        spec['pixel_scale'] = [1, 2]
    cfg['uncertainty'] = {'mode': 'none'} if mode == 'none' else spec
    manifest = build_manifest(cfg, p, 100, 100)
    manifest['publication_calibration_mode'] = layout
    manifest['publication_calibration_ids'] = mids
    metadata = metadata_fields(manifest)
    rows = []
    uncertainty_rows = []
    points = [pt for s in p.series for pt in s.points]
    result = None
    if mode != 'none':
        result = propagate(p, [(pt.pixel_x, pt.pixel_y) for pt in points], spec)
    for mid in mids:
        at = 0
        for series in p.series:
            for i, point in enumerate(series.points):
                xy = [format(point.calibrated_x, '.17g'), format(point.calibrated_y, '.17g')]
                fields = [b64(series.id), b64(series.name), str(i), *xy, series.parameter_value, str(point.pixel_x), str(point.pixel_y)]
                if layout == 'combined':
                    fields += [b64(mid), b64(items[mids.index(mid)]['label'])]
                fields += [b64(point.id)]
                rows.append('\t'.join(fields))
                if result is not None:
                    uncertainty_rows.append('\t'.join([b64(series.id), b64(point.id), b64(mid), *xy,
                        format(result['sigma_x'][at], '.17g'), format(result['sigma_y'][at], '.17g'), format(result['covariance_xy'][at], '.17g')]))
                at += 1
    quality = inspect_quality(cfg, p, image.size, measurements=items, publication_layout=layout, published_row_count=len(rows), raster_image=image)
    metadata.update({
        'curve_digitizer.quality_schema_version': '2',
        'curve_digitizer.quality_report_json': json.dumps(quality, ensure_ascii=False, separators=(',', ':'), allow_nan=False),
        'curve_digitizer.quality_status': quality['status'],
        'curve_digitizer.quality_issue_count': str(quality['issues']['total']),
        'curve_digitizer.quality_source_point_count': str(quality['publication']['unique_raster_point_count']),
        'curve_digitizer.quality_published_row_count': str(quality['publication']['published_row_count']),
        'curve_digitizer.quality_curve_count': str(quality['publication']['curve_count']),
        'curve_digitizer.quality_calibration_realizations': str(quality['publication']['calibration_realization_count']),
        'curve_digitizer.quality_segment_count': str(quality['publication']['source_segment_count']),
        'curve_digitizer.quality_evidence_available': str(int(quality['image_evidence']['available'])),
        'curve_digitizer.publication_calibration_mode': layout,
        'curve_digitizer.publication_calibration_ids': json.dumps(mids, separators=(',', ':')),
        'curve_digitizer.publication_measurement_id': mids[0],
        'curve_digitizer.publication_measurement_label': items[0]['label'],
    })
    target = out / mode
    target.mkdir()
    (target / 'configuration.json').write_text(json.dumps(cfg, ensure_ascii=False, separators=(',', ':')))
    (target / 'rows.tsv').write_text('\n'.join(rows))
    (target / 'metadata.records').write_text(encode_metadata_records(metadata))
    (target / 'layout.txt').write_text(layout)
    if result is not None:
        factors = compact_factors([result['local_factors']], [result['shared_factors']])
        report = dict(schema='gxtxt.curve_digitizer.uncertainty.v2', mode=spec['mode'], declaration=spec, row_count=len(rows),
                      calibrations=[], units=['s', 'V'], shared_calibration=result['shared_calibration'], within_point_correlation=result['within_point_correlation'])
        (target / 'uncertainty.tsv').write_text('\n'.join([b64(json.dumps(report, separators=(',', ':'))), b64(json.dumps(factors, separators=(',', ':'))), *uncertainty_rows]))
        (target / 'inline.tsv').write_text(CurveDigitizerApp._core_inline_uncertainty(p.calibration_linearization([(pt.pixel_x, pt.pixel_y) for pt in points]), spec, mids[0]))
        (target / 'factors.json').write_text(json.dumps(factors, separators=(',', ':')))
print('Created one synthetic 20-curve / 2-calibration performance packet:', out)
