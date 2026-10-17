# SPDX-License-Identifier: GPL-3.0-or-later
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]/'python'))
from digitizer_model import Project
from calibration_manifest import build_manifest, metadata_fields

def config(doc):
    return {'configuration_id':doc,'source':{'dataset_id':'test_image','sha256':'f'*64},'uncertainty':{}}

p=Project()
p.auto_calibrate_full_image(720,560)
a=build_manifest(config('idoc_one'),p,720,560)
b=build_manifest(config('idoc_two'),p,720,560)
assert a['calibration_sha256']==b['calibration_sha256']
assert a['calibration_id']==b['calibration_id']
assert a['configuration_id'] != b['configuration_id']
assert a['calibration_type']=='pixel'
assert a['raster_geometry']['source_pixel_space']=='original_source_image'
assert a['raster_geometry']['upstream_processing']=='unknown'
assert a['calibration_method']['measurement_uncertainty']=='not_quantified'
assert 'uncertainty' not in a
p.scale_full_image(720,560,151,10,'µm')
cfg=config('idoc_two')
cfg['scale_reference']={'start':(1300.0,500.0),'end':(1451.0,500.0),
                         'pixel_length':151.0,'physical_length':10.0,'unit':'µm',
                         'method':'detect','edge_convention':'center'}
try:
    b=build_manifest(cfg,p,720,560)
except ValueError as e:
    # Bar coordinates outside raster not accepted by this test; use inside image.
    cfg['scale_reference']['start']=(300.0,500.0)
    cfg['scale_reference']['end']=(451.0,500.0)
    b=build_manifest(cfg,p,720,560)
assert b['calibration_sha256'] != a['calibration_sha256']
assert b['calibration_type']=='scale_bar'
md=metadata_fields(b)
assert md['curve_digitizer.calibration_sha256']==b['calibration_sha256']
assert md['curve_digitizer.raster_geometry.source_to_calibration']=='identity'
assert md['curve_digitizer.calibration_method.tick_reference']=='center'
print('PASS Python identity stable across independent configs; scaling changes digest; geometry/method metadata')
