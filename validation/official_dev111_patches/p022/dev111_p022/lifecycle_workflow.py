#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools'
def wait(expr,limit=35):
 end=time.monotonic()+limit
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  modal=g.read('grab current')
  if modal==w+'.__tk__messagebox' and g.read(f'winfo exists {modal}.ok')=='1' and g.read(f'winfo viewable {modal}.ok')=='1':
   message=g.read(f'{modal}.msg cget -text')
   if message.startswith('Editing here discards later local History steps.'):
    g.save('BRANCH_PROMPT.txt',message);g.click(modal+'.ok')
  time.sleep(.05)
 raise AssertionError(expr)
def button(path):g.reveal(path,ins);g.click(path)
def current():return g.read('set ::GX::Workbench3D::sketchComponent')
def state(name):
 sk=current();value=g.read(f'{sk} state');g.save(name+'.tcldict',value);return value
def point(c,x,y):
 _,rx,ry,width,height=g.geometry(c);assert 0<=x<width and 0<=y<height
 g.xt('mousemove',rx+x,ry+y,'click',1);time.sleep(.25)
try:
 g.activate(w);sk=current();assert sk
 doc=g.read(f'{sk} get document_id');model=g.read(f'{sk} get model');h=g.read(f'dict get [{sk} state] history');g.save('BEFORE_MODEL.tcldict',model);state('BEFORE')
 button(tools+'.cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');wait('expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}')
 displays=g.read('::GX::native3DGuiHostDocumentPresentationInspect');assert doc in g.tk.tk.splitlist(displays)
 g.save('CLOSED_DISPLAY.tcldict',displays);g.shot(w,'saved-sketch-visible-closed')
 c=w+'.body.canvas.scene_pending.geometry_viewport.native3d.canvas';_,rx,ry,width,height=g.geometry(c)
 g.xt('mousemove',rx+width//2,ry+height//2,'mousedown',1)
 for i in range(1,7):g.xt('mousemove',rx+width//2+i*5,ry+height//2+i*3);time.sleep(.025)
 g.xt('mouseup',1);time.sleep(.5);wait('expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}');g.shot(w,'closed-sketch-orbit')
 button(tools+'.cad_sketch_open');wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}')
 sk=current();assert g.read(f'{sk} get document_id')==doc;assert g.read(f'{sk} get model')==model
 now=g.read(f'dict get [{sk} state] history');assert g.tk.tk.call('dict','get',now,'count')==g.tk.tk.call('dict','get',h,'count')
 state('REOPENED');g.shot(w,'same-document-reopened')
 base=c.rsplit('.canvas',1)[0]+'.cad_tools.body.tools'
 g.click(base+'.command2');_,rx,ry,width,height=g.geometry(c);point(c,width//2,height*3//4);point(c,width//2+45,height*3//4-15)
 g.click(base+'.command5');wait(f'expr {{![{sk} pending] && [dict get [{sk} state] history pending]==0}}')
 made=g.read(f'{sk} get model');assert made!=model;g.save('FINISHED_MODEL.tcldict',made);state('FINISHED')
 g.click(base+'.command2');point(c,width//2+60,height*3//4+25);staged=state('STAGED')
 # Escape must discard only the proposal, never committed geometry/History.
 g.xt('key','Escape');wait(f'expr {{![{sk} pending]}}');assert g.read(f'{sk} get model')==made;state('CANCELLED');g.shot(w,'finish-then-cancel')
 g.click(base+'.command10');time.sleep(.5)
 g.save('RESULT.json',dict(result='PASS',document=doc,meaning='actual Close/orbit/Reopen retains saved drawing and exact scientific model/History; Line Finish then another construction Escape; explicit Save'))
finally:g.tk.destroy()
