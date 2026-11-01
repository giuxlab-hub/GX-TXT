# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk 2.0.12 GUI smoke for a vertically scrollable Calibration page."""
from pathlib import Path
import sys, tkinter as tk
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,PLUGIN_VERSION
def records(*rows):
    return "\n".join("\t".join([key]+[b64e(str(x)) for x in vals]) for key,vals in rows)
class RPC:
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        raise AssertionError((cmd,args))
root=tk.Tk()
root.geometry("1200x730+4200+4200")
try:
    app=CurveDigitizerApp(root,RPC(),bootstrap_payload=records(("SESSION",["test"])))
    assert PLUGIN_VERSION=="2.0.25"
    app.notebook.select(app.calibration_tab);root.update()
    scroll=app.calibration_scroll_canvas
    assert app._calibration_page_scrollable,(scroll.bbox("all"),scroll.winfo_height())
    assert app.calibration_scrollbar.winfo_ismapped()
    scroll.yview_moveto(1);root.update()
    assert scroll.yview()[0]>.01,scroll.yview()
    assert app.measurement_table.winfo_ismapped()
    root.geometry("1050x500+4200+4200");root.update()
    scroll.yview_moveto(1);root.update()
    assert scroll.yview()[0]>.05
    pointer=scroll.winfo_pointerxy
    scroll.winfo_pointerxy=lambda:(app.measurement_table.winfo_rootx()+5,app.measurement_table.winfo_rooty()+5)
    before=scroll.yview()[0]
    try:
        assert app._calibration_mousewheel(SimpleNamespace(delta=-120,num=None))=="break"
        assert abs(scroll.yview()[0]-before)<1e-7
    finally:scroll.winfo_pointerxy=pointer
    app.notebook.select(app.curves_tab);root.update()
    assert app._calibration_mousewheel(SimpleNamespace(delta=-120,num=None)) is None
    print("PASS scrollable Calibration, nested table, window resizing, tab isolation")
finally:root.destroy()
