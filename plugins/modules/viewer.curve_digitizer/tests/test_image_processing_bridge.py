"""Provider-owned Script Bridge contract: metadata, argument and result shape."""
# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util, pathlib, sys, tkinter
from types import ModuleType
root = pathlib.Path(__file__).resolve().parents[1]
fake = ModuleType('gxtxt_script_bridge_server')
class BridgeError(Exception):
    pass
fake.BridgeError = BridgeError
sys.modules['gxtxt_script_bridge_server'] = fake
path = root / 'api' / 'script_bridge_binding.py'
spec = importlib.util.spec_from_file_location('digitizer_binding_test', path)
mod = importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
assert mod.REGISTRATION['api_id']=='CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1'
assert mod.REGISTRATION['provider_id']=='viewer.curve_digitizer'
assert mod.REGISTRATION['api_version']==1
assert set(mod.REGISTRATION['operations'])=={'read','lineage','operations','has_manifest'}
for item in mod.REGISTRATION['operations'].values():
    assert item['arguments'][0]['name']=='dataset_id' and item['result_contract']

class Host:
    def __init__(self):
        self.tcl=tkinter.Tcl()
        sha='a'*64
        shaout='b'*64
        self.tcl.eval('''
        namespace eval ::GX {}
        proc ::GX::sessionInspectionCurrentSession {} {return /tmp/tcl-bridge-case}
        proc ::GX::sessionInspectionDataset {did session} {
            if {$did eq {proc}} {return [dict create contract image.raster canonical_sha256 BVAL]}
            if {$did eq {src}} {return [dict create contract image.raster canonical_sha256 AVAL]}
            error {Unknown Dataset}
        }
        proc ::GX::datasetMetadataRead {session did} {
            if {$did ne {proc}} {return [dict create]}
            return [dict create \\
              curve_digitizer.image_processing.schema_version 1 \\
              curve_digitizer.image_processing.producer_id viewer.curve_digitizer \\
              curve_digitizer.image_processing.source_dataset_id src \\
              curve_digitizer.image_processing.source_display_name {SEM sample} \\
              curve_digitizer.image_processing.source_sha256 AVAL \\
              curve_digitizer.image_processing.engine ImageMagick \\
              curve_digitizer.image_processing.engine_version {ImageMagick 7.1} \\
              curve_digitizer.image_processing.geometry_preserved 1 \\
              curve_digitizer.image_processing.pixel_transform identity \\
              curve_digitizer.image_processing.image_width 40 \\
              curve_digitizer.image_processing.image_height 20 \\
              curve_digitizer.image_processing.operation_count 1 \\
              curve_digitizer.image_processing.operation.0.kind gamma \\
              curve_digitizer.image_processing.operation.0.value 0.7 \\
              curve_digitizer.image_processing.fingerprint CVAL]
        }
        '''.replace('AVAL',sha).replace('BVAL',shaout).replace('CVAL','c'*64))
    def call(self,proc,*args):return self.tcl.call(proc,*args)
    def as_list(self,x):return list(self.tcl.splitlist(x))
    def as_dict(self,x):
        parts=self.as_list(x)
        return {str(parts[i]): (str(self.tcl.call('format','%s',parts[i+1]))
                if type(parts[i+1]).__name__=='Tcl_Obj' else parts[i+1])
                for i in range(0,len(parts),2)}

host=Host()
result=mod.invoke(host,'read',['proc'])
assert result['source_dataset_id']=='src'
assert result['geometry_preserved'] is True
assert result['processing_operations']==[{'kind':'gamma','value':'0.7'}]
assert mod.invoke(host,'has_manifest',['proc']) is True
assert mod.invoke(host,'has_manifest',['src']) is False
assert mod.invoke(host,'operations',['proc'])==[{'kind':'gamma','value':'0.7'}]
chain=mod.invoke(host,'lineage',['proc'])
assert len(chain)==2 and int(chain[-1]['original'])==1
try:
    mod.invoke(host,'read',[])
    raise AssertionError('Missing Dataset accepted')
except BridgeError:pass
print('PASS module Script Bridge binding: read, operations, lineage, has_manifest and errors')
