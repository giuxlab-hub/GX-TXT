#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;base=w+'.body.canvas.scene_pending.geometry_viewport.native3d';scroll=base+'.side.scroll';fields=scroll+'.controls';c=base+'.canvas';bar=base+'.cad_tools.body.tools'
def wait(expr,limit=30):
 end=time.monotonic()+limit
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.08)
 raise AssertionError(expr)
def settled():wait('expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}')
def fill(name,value):g.reveal(fields+'.'+name,scroll);g.fill(fields+'.'+name,value)
def apply():g.reveal(fields+'.viewApply',scroll);g.click(fields+'.viewApply');settled();time.sleep(.1)
def clickpoint(px,py):
 _,rx,ry,width,height=g.geometry(c);g.xt('mousemove',rx+px,ry+py,'click',1);time.sleep(.2)
try:
 g.activate(w);sk=g.read('set ::GX::Workbench3D::sketchComponent');host=g.read(f'{sk} get host');projection=g.read(f'{sk} get projection')
 model=g.read(f'{sk} get model');history=g.read(f'dict get [{sk} state] history');results=[]
 for mode in ['perspective','orthographic']:
  g.click(bar+'.command7');settled();g.reveal(fields+'.projection',scroll);g.choose(fields+'.projection',mode);apply()
  g.click(bar+'.command2');_,_,_,cw,ch=g.geometry(c);clickpoint(cw//2,ch*3//4)
  staged=g.read(f'dict get [[{host} advanced] state] construction');assert staged
  for label,position,target in [('edge','0;-30;0','0;0;0'),('horizon','0;-30;1','0;0;0'),('behind','0;0;30','0;0;60')]:
   fill('cameraPosition',position);fill('cameraTarget',target);fill('cameraUp','0;1;0' if label=='behind' else '0;0;1');apply()
   info=g.read(f'{projection} info');g.save(f'{mode}-{label}.tcldict',info)
   ready=int(g.tk.tk.call('dict','get',info,'ready'))
   _,rx,ry,cw,ch=g.geometry(c);g.xt('mousemove',rx+cw//2,ry+ch//2);clickpoint(cw//2,ch//2)
   assert g.read(f'{sk} get model')==model
   assert g.read(f'dict get [[{host} advanced] state] construction')==staged,(mode,label,'staged construction lost')
   assert g.read(f'dict get [{sk} state] history')==history
   g.shot(w,f'{mode}-{label}');results.append(dict(mode=mode,case=label,editable=bool(ready),scientific_and_staged_state='unchanged'))
  g.click(bar+'.command7');settled();wait(f'dict get [{projection} info] ready');assert g.read(f'dict get [[{host} advanced] state] construction')==staged
  g.xt('mousemove',rx+cw//2,ry+ch//2,'key','Escape');wait(f'expr {{![{sk} pending]}}');assert g.read(f'{sk} get model')==model
 g.save('RESULT.json',dict(result='PASS',cases=results,meaning='actual camera controls and CAD pointer input; model, History and staged Line preserved across non-editable views; Fit and Escape restore normal interaction'))
finally:g.tk.destroy()
