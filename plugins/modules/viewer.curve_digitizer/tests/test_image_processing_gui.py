"""Smoke-test image processing workflow in the actual Tk viewer under Xvfb."""
# SPDX-License-Identifier: GPL-3.0-or-later
import sys,time,tempfile,tkinter as tk,uuid,os
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,b64d
from image_processing import ProcessingError


def records(*rows):
    return '\n'.join('\t'.join([name]+[b64e(str(v)) for v in fields]) for name,fields in rows)

class Rpc:
    def __init__(self): self.published=[]
    def attach(self,root): pass
    def call(self, cmd, *args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'user']) for k,v in CORE_PREFS.items()))
        if cmd=='IMAGE_TOOL':return '/opt/imagemagick/bin/magick\tImageMagick 7 test'
        if cmd=='DOC_UPDATE':return args[0]+'\t'+uuid.uuid4().hex
        if cmd=='IMAGE_STAGE':
            fd,path=tempfile.mkstemp(suffix='.stage');os.close(fd);return path
        if cmd=='IMAGE_STAGE_CANCEL':
            try:os.remove(args[1])
            except FileNotFoundError:pass
            return 'cancelled'
        if cmd=='IMAGE_PUBLISH':
            assert Image.open(args[6]).size==(130,90)
            md={b64d(k):b64d(v) for k,v in (line.split('\t') for line in args[7].splitlines())}
            assert md['curve_digitizer.image_processing.operation_count']=='2'
            assert md['curve_digitizer.image_processing.operation.1.kind']=='gamma'
            assert md['curve_digitizer.image_processing.source_dataset_id']=='sem.original'
            assert md['curve_digitizer.image_processing.pixel_transform']=='identity'
            assert args[8]=='Processed SEM image notes.'
            self.published.append(md)
            os.unlink(args[6])
            return args[4]+'\t'+'e'*64
        raise AssertionError(cmd)
root=tk.Tk();root.withdraw();rpc=Rpc()
app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(('SESSION',['session'])))
app.current_doc_id='idoc_001';app.document_sha['idoc_001']='a'*64
app.config=app.new_configuration('SEM image')
app.config['source']={'dataset_id':'sem.original','sha256':'a'*64,'width':130,'height':90}
app.image=Image.new('RGB',(130,90),(100,150,220));app.canvas.set_image(app.image)
app.processing_executable='/opt/imagemagick/bin/magick'
app.processing_engine_version='ImageMagick 7 test'
app.processing_operations=[{'kind':'grayscale','value':''},{'kind':'gamma','value':'0.85'}]
app._refresh_processing_list()
app.process_image_preview()
for _ in range(140):
    root.update();time.sleep(.015)
    if not app.processing_active and app.processed_image is not None:break
assert app.processed_image is not None, app.processing_status.get()
assert app.canvas.original_image == app.processed_image
assert app.image.size==app.processed_image.size==(130,90)
from tkinter import messagebox
old=messagebox.askyesno
messagebox.askyesno=lambda *a,**kwargs: True
app.processing_dataset_id.set('sem.processed')
app.notes.insert('1.0','Processed SEM image notes.')
app.check_dataset_catalog = lambda force=False: None
try:app.publish_processed_image()
finally:messagebox.askyesno=old
assert len(rpc.published)==1
app.processing_show_result.set(False);app._switch_processing_preview()
assert app.canvas.original_image is app.image
app.reset_processing();assert not app.processing_operations
root.destroy()
print('PASS Tk Image Processing preview, original restore, processed-image publication and metadata')
