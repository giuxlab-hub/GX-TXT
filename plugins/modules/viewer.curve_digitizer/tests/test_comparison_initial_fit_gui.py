"""Regression: Image Processing split views fit the real canvas, not Tk's 1x1 placeholder."""
# SPDX-License-Identifier: GPL-3.0-or-later
import sys,tkinter as tk
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e

def records(*rows):
    return '\n'.join('\t'.join([key]+[b64e(str(value)) for value in values]) for key,values in rows)

class Rpc:
    def attach(self, root):pass
    def call(self, cmd, *args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[key,value,'user']) for key,value in CORE_PREFS.items()))
        if cmd=='CONFIG_COMMIT':return records(*(('SETTING',[key,value,'session']) for key,value in CORE_PREFS.items()))
        if cmd=='IMAGE_TOOL':return ''
        if cmd=='DOC_UPDATE':return args[0]+'\t'+'a'*64
        raise AssertionError((cmd,args))

def close(a,b,tolerance=1e-5):
    assert abs(a-b)<tolerance,(a,b)

root=tk.Tk()
root.geometry('1250x800')
app=CurveDigitizerApp(root,Rpc(),bootstrap_payload=records(('SESSION',['session'])))
app.config=app.new_configuration('split image')
app.config['source']={'dataset_id':'image_A','sha256':'a'*64,'width':720,'height':560}
# Load image BEFORE mainloop has computed widget dimensions (former failure).
app.set_image(Image.new('RGB',(720,560),'#404040'))
root.update()
a,b=app.compare_original_canvas,app.compare_processed_canvas
app.notebook.select(app.processing_tab)
app.processing_compare.set(True)
app._update_processing_view_layout()
root.update()
for c in (a,b):
    vw,vh=c.winfo_width(),c.winfo_height()
    expected=min(vw/720,vh/560)
    close(c.scale,expected)
    cx,cy=c.canvas_to_image(vw/2,vh/2)
    close(cx,360);close(cy,280)
assert a.scale>0.1 and b.scale>0.1,'Previously both had erroneous 0.01 zoom'
# User navigates independently; tab return must not silently reset view.
a.zoom_at(55,80,1.4)
root.update()
a_state=(a.scale,a.offset_x,a.offset_y)
b_state=(b.scale,b.offset_x,b.offset_y)
app.notebook.select(app.curves_tab);root.update()
app.notebook.select(app.processing_tab);root.update()
for actual,expected in zip((a.scale,a.offset_x,a.offset_y),a_state):close(actual,expected)
for actual,expected in zip((b.scale,b.offset_x,b.offset_y),b_state):close(actual,expected)
# Move divider and verify zoom remains user-selected rather than auto-refit.
old_scale=a.scale
app.comparison_view.sashpos(0, int(app.comparison_view.winfo_width()*0.60))
root.update()
close(a.scale,old_scale)
# New image SOURCE with same raster dimensions still restores sensible full fits.
app.set_image(Image.new('RGB',(720,560),'#c0c0c0'))
root.update()
for c in (a,b):
    vw,vh=c.winfo_width(),c.winfo_height()
    close(c.scale,min(vw/720,vh/560))
    cx,cy=c.canvas_to_image(vw/2,vh/2)
    close(cx,360);close(cy,280)
# Optional synchronization maps same raster center even if panels differ in width.
app.processing_sync_views.set(True)
a.zoom_at(110,100,1.3);root.update()
close(a.scale,b.scale)
x1,y1=a.canvas_to_image(a.winfo_width()/2,a.winfo_height()/2)
x2,y2=b.canvas_to_image(b.winfo_width()/2,b.winfo_height()/2)
close(x1,x2);close(y1,y2)
root.destroy()
print('PASS automatic first fit, independent views, tab restoration, resizing, source reset and sync')
