#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);p.add_argument('--framework',type=Path,default=Path('.'));a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools'
def wait(expr):
 end=time.monotonic()+30
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.05)
 raise AssertionError(expr)
try:
 g.activate(w);g.reveal(tools+'.cad_sketch_open',ins);g.click(tools+'.cad_sketch_open')
 wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}')
 wait(f"expr {{[{w}.footer.status cget -text] eq {{Action 'cad_sketch_open': completed}}}}");time.sleep(.2)
 sk=g.read('set ::GX::Workbench3D::sketchComponent');g.save('BEFORE.tcldict',g.read(f'{sk} state'));g.save('MODEL.tcldict',g.read(f'{sk} get model'))
 g.reveal(tools+'.cad_sketch_close',ins);_,bx,by,bw,bh=g.geometry(tools+'.cad_sketch_close');c=g.read(f'[{sk} get host] canvas');_,rx,ry,cw,ch=g.geometry(c)
 g.read(f'source {{{a.framework.resolve()}/validation/dev111_p022/timing.tcl}};::P022Timing::start 0')
 g.read('set ::P022CloseRows {};proc ::P022CloseTrace {command args} {lappend ::P022CloseRows [list [clock microseconds] $::GX::Engine3D::workerBusy [llength $::GX::Engine3D::cameraQueue] $command]};trace add execution ::GX::Workbench3D::sketchClose enter ::P022CloseTrace')
 g.xt('mousemove',rx+cw//2,ry+ch*3//4,'click',1,'keydown','space','mousedown',1,'mousemove',rx+cw//2+10,ry+ch*3//4+5,'sleep','.01','mousemove',rx+cw//2+25,ry+ch*3//4+10,'mouseup',1,'keyup','space')
 g.xt('mousemove',bx+bw//2,by+bh//2,'click',1)
 end=time.monotonic()+30
 while time.monotonic()<end:
  if g.read('set ::GX::Workbench3D::sketchComponent')=='':break
  status=g.read(f'{w}.footer.status cget -text')
  if "Action 'cad_sketch_close': failed" in status:raise AssertionError(status)
  time.sleep(.05)
 assert g.read('set ::GX::Workbench3D::sketchComponent')==''
 g.save('DISPLAY.tcldict',g.read('::GX::native3DGuiHostDocumentPresentationInspect'));g.shot(w,'closed-after-camera-input')
 g.save('RESULT.json',dict(result='PASS',meaning='actual orbit then immediate Close; inspect ownership trace to distinguish queued input from worker overlap'))
finally:
 try:g.read(f'::P022Timing::stop {{{a.output.resolve()}/NATIVE.tsv}}');g.save('CLOSE_TRACE.tcllist',g.read('trace remove execution ::GX::Workbench3D::sketchClose enter ::P022CloseTrace;set ::P022CloseRows'))
 except Exception:pass
 g.tk.destroy()
