#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('mode');a=p.parse_args();g=Gui(a.launch,a.output)
def wait(script):
 end=time.monotonic()+45
 while time.monotonic()<end:
  if g.read(script)=='1':return
  time.sleep(.1)
 raise AssertionError(script)
try:
 g.activate('.');g.config(a.mode)
 for label in ['TEST CAD 1','TEST CAD 2']:
  before=set(x[0] for x in g.widgets('.') if x[1]=='Toplevel')
  g.viewer(label);end=time.monotonic()+45
  while time.monotonic()<end:
   windows=[x[0] for x in g.widgets('.') if x[1]=='Toplevel' and x[0] not in before and x[0].startswith('.gxViewerDevPreview')]
   if len(windows)==1:break
   time.sleep(.1)
  assert len(windows)==1,windows
  w=windows[0];g.activate(w)
  wait(f'expr {{[dict exists $::GX::ViewerGui::instances {w} cad_sketches] && [dict size [dict get $::GX::ViewerGui::instances {w} cad_sketches]]>0}}')
  sk=g.read(f'lindex [dict values [dict get $::GX::ViewerGui::instances {w} cad_sketches]] 0');v=g.read(f'{sk} get viewport');canvas=g.read(f'[{sk} get host] canvas')
  wait(f'expr {{[dict get [::GX::native3DViewportInspect {v}] status] eq {{ready}} && [dict get [::GX::native3DViewportInspect {v}] busy] eq {{}}}}')
  top=canvas.rsplit('.',1)[0]+'.tools.top'
  wait(f'expr {{[winfo viewable {top}] && [winfo width {top}]>1}}');g.activate(w);g.click(top);time.sleep(.3)
  previous=g.read(f'dict get [::GX::native3DViewportInspect {v}] camera')
  surface=g.read(f'{sk} get surface');l,t,r,b=map(int,g.tk.tk.splitlist(g.read(f'{surface} cubeRect')))
  _,x,y,cw,ch=g.geometry(canvas);g.xt('mousemove',x+l+(r-l)//4,y+(t+b)//2,'click',1);time.sleep(.6)
  wait(f'expr {{[dict get [::GX::native3DViewportInspect {v}] busy] eq {{}} && ![dict get [::GX::native3DViewportInspect {v}] pending]}}')
  assert g.read(f'dict get [::GX::native3DViewportInspect {v}] camera')!=previous
  leaf=label.replace(' ','-');g.save(leaf+'-RENDERER.tcldict',g.read(f'::GX::native3DViewportInspect {v}'));g.shot(w,leaf+'-orbit')
  g.xt('key','--clearmodifiers','alt+F4');time.sleep(.4)
  modal=w+'.__tk__messagebox'
  if g.read(f'winfo exists {modal}.yes')=='1':g.click(modal+'.yes')
  wait(f'expr {{![winfo exists {w}]}}')
 g.save('RESULT.json',dict(status='PASS',mode=a.mode,scope='actual normal authored Test CAD1/2 startup, top-view control, Navigation Cube camera change, renderer receipts, close'))
finally:g.tk.destroy()
