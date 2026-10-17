"""GUI publishing: verify selected calibrations, not the active one, determine X/Y."""
import copy,json,sys,uuid,tkinter as tk
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,b64d
from digitizer_model import Project,Series,DigitizedPoint,Calibration

def records(*rows):
    return '\n'.join('\t'.join([name]+[b64e(str(v)) for v in fields]) for name,fields in rows)
class Rpc:
    def __init__(self): self.publications=[]
    def attach(self,r): pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        if cmd=='DOC_UPDATE':return args[0]+'\t'+uuid.uuid4().hex
        if cmd=='PUBLISH':
            self.publications.append(args)
            return f'{args[2]}\tdata.csv\t'+('a'*64)+'\ttable.generic'
        raise ValueError(f'Unexpected host call {cmd}')
root=tk.Tk();root.withdraw()
rpc=Rpc();app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(('SESSION',['session'])))
app.current_doc_id='doc_1';app.document_sha['doc_1']='old'
app.config=app.new_configuration('Test grooves')
app.config['source']={'dataset_id':'source_img','sha256':'f'*64,'width':200,'height':100}
app.project=Project();app.project.auto_calibrate_full_image(200,100)
app.image=Image.new('RGB',(200,100));app.canvas.set_image(app.image)
s=Series(name='Line')
for x,y in [(60,30),(70,35),(80,40)]:
    pt=DigitizedPoint(pixel_x=x,pixel_y=y)
    app.project.update_point_calibration(pt);s.points.append(pt)
app.project.series=[s]
app.measurement_selected_id=None
app.refresh_measurements()
first=app._measurements()['active_id'];assert app._selected_measurement()['state']=='accepted'
# Make independent second accepted mapping: alter projective quad slightly.
app.new_measurement();second=app._measurements()['active_id']
for k,(x,y) in {
'bottom_left':(5,98),'bottom_right':(198,98),
'top_left':(5,2),'top_right':(198,2)}.items():app.project.calibration.set_corner(k,x,y)
app.project.recalculate_all_points();app._sync_active_measurement()
app.measurement_selected_id=second;app.accept_measurement()
app.measurement_selected_id=first;app.activate_measurement()
assert app._measurements()['active_id']==first
app.refresh_publish_measurements()
assert len(app.publish_measurement_ids)==2
app.select_all_publish_measurements()
app.output_dataset_id.set('my_image')
app.publish_layout.set('separate')
app.notes.insert('1.0', 'Traced edge under microscope — calibrated.')
app.publish_dataset()
assert len(rpc.publications)==2, app.publish_result.get()
assert all(x[23]=='Traced edge under microscope — calibrated.' for x in rpc.publications), 'missing GUI notes in curve publish RPC'
ids=[args[2] for args in rpc.publications]
assert ids==['my_image.measurement_1.curves','my_image.measurement_2.curves'],ids
first_row=rpc.publications[0][20].splitlines()[0].split('\t')
second_row=rpc.publications[1][20].splitlines()[0].split('\t')
assert first_row[3:5]!=second_row[3:5],(first_row,second_row)
assert first_row[6:8]==second_row[6:8]
# Default layout remains separate; explicit combined adds two stable per-row IDs.
rpc.publications.clear()
app.publish_layout.set('combined')
# fake modal confirmation
from tkinter import messagebox
orig=messagebox.askyesno;messagebox.askyesno=lambda *a,**kw: True
try:app.publish_dataset()
finally:messagebox.askyesno=orig
assert len(rpc.publications)==1,app.publish_result.get()
rows=rpc.publications[0][20].splitlines()
assert len(rows)==6,len(rows)
assert set(b64d(row.split('\t')[8]) for row in rows)=={first,second}
assert len({(row.split('\t')[6],row.split('\t')[7]) for row in rows})==3
# Quality v2 must describe ACTUAL combined publication rows (6), versus
# three original raster clicks and two accepted calibrations.
md={b64d(parts[0]):b64d(parts[1]) for record in rpc.publications[0][21].splitlines()
    if (parts:=record.split('\t')) and len(parts)==2}
assert md['curve_digitizer.quality_schema_version']=='2'
q=json.loads(md['curve_digitizer.quality_report_json'])
assert q['publication']['unique_raster_point_count']==3, q['publication']
assert q['publication']['published_row_count']==6, q['publication']
assert q['publication']['calibration_realization_count']==2, q['publication']
assert q['segments']['total']==2, q['segments']
assert [x['measurement_id'] for x in q['calibrations']]==[first,second]
assert md['curve_digitizer.quality_published_row_count']=='6'
assert md['curve_digitizer.quality_source_point_count']=='3'
assert md['curve_digitizer.quality_calibration_realizations']=='2'
assert q['metrology']['uncertainty']['status']=='not_assessed'
root.destroy()
print('PASS two separate publications with different X/Y but same raster; combined per-row IDs, GUI selection')
