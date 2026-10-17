"""Headless: consistent repeated calibrations survive publication without statistics."""
import copy, json, re, sys, uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from digitizer_model import Project, AxisConfig
from calibration_manifest import build_manifest,metadata_fields

src={'dataset_id':'img_a', 'sha256':'a'*64}
p=Project()
p.auto_calibrate_full_image(720,560)
p.scale_full_image(720,560,150,10,'µm')
state={'axes': {'x':p.x_axis.to_dict(),'y':p.y_axis.to_dict()}, 'calibration':p.calibration.to_dict(), 'scale_reference': None}
# Independently selected corners for repeat #2
p2=copy.deepcopy(p)
p2.calibration.pixels['bottom_left']=(0.5,558.7)
p2.recalculate_all_points()
trial2={'axes': {'x':p2.x_axis.to_dict(),'y':p2.y_axis.to_dict()}, 'calibration':p2.calibration.to_dict(), 'scale_reference':None}
ids=['meas_'+uuid.uuid4().hex for i in range(3)]
items=[dict(id=ids[0],label='First',state='accepted',**state),
       dict(id=ids[1],label='Second',state='accepted',**trial2),
       dict(id=ids[2],label='Bad trial',state='rejected',axes=state['axes'], calibration={'points':{}},scale_reference=None)]
config={'source':src,'configuration_id':'digcfg_x', 'calibration_measurements':{
  'group_id':'calgrp_'+uuid.uuid4().hex,'active_id':ids[0],'items':items}}
manifest=build_manifest(config,p,720,560)
rows=manifest['calibration_measurements'];assert len(rows)==3
assert [x['valid'] for x in rows]==[True,True,False]
assert rows[0]['calibration_sha256']!=rows[1]['calibration_sha256']
assert 'uncertainty' not in manifest
md=metadata_fields(manifest)
assert md['curve_digitizer.measurement_count']=='3'
assert md['curve_digitizer.measurement.2.valid']=='0'
assert md['curve_digitizer.active_measurement_id']==ids[0]
assert len(md['curve_digitizer.calibration_measurements'])>500
bad=copy.deepcopy(config);bad['calibration_measurements']['active_id']=ids[2]
try: build_manifest(bad,p,720,560)
except ValueError: pass
else: raise AssertionError('Rejected active calibration should block publication')
print('PASS repeat publication: distinct mappings, accepted/rejected states, IDs, no fabricated uncertainty')
