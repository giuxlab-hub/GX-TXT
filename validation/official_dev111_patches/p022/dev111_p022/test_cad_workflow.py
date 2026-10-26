#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window

def wait(expr):
 end=time.monotonic()+30
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  modal=g.read('grab current')
  if modal==w+'.__tk__messagebox' and g.read(f'winfo exists {modal}.ok')=='1' and g.read(f'winfo viewable {modal}.ok')=='1':
   if g.read(f'{modal}.msg cget -text').startswith('Editing here discards later local History steps.'):g.click(modal+'.ok')
  time.sleep(.05)
 raise AssertionError(expr)
def button(action):
 path=g.read(f'set sk {sk};set w {w};if {{[dict exists $::GX::ViewerCommands::windows $w toolbar buttons cad_{action}]}} {{dict get $::GX::ViewerCommands::windows $w toolbar buttons cad_{action}}} else {{dict get $::GX::ViewerCommands::windows [$sk widget] toolbar buttons {action}}}')
 g.click(path)
def point(x,y):
 _,rx,ry,cw,ch=g.geometry(canvas);g.xt('mousemove',rx+x,ry+y,'click',1);time.sleep(.2)
try:
 g.activate(w);sk=g.read(f'lindex [dict values [dict get $::GX::ViewerGui::instances {w} cad_sketches]] 0');assert sk
 canvas=g.read(f'[{sk} get host] canvas');g.click(canvas.rsplit('.',1)[0]+'.tools.top');wait(f'dict get [[{sk} get projection] info] ready')
 button('fit');time.sleep(.5)
 before=g.read(f'{sk} get model');g.save('BEFORE.tcldict',g.read(f'{sk} state'))
 button('line');_,rx,ry,cw,ch=g.geometry(canvas);point(cw//2,ch*2//3);point(cw//2+55,ch*2//3-25);button('finish')
 wait(f'expr {{![{sk} pending] && [dict get [{sk} state] history pending]==0}}');after=g.read(f'{sk} get model');assert after!=before
 g.save('AFTER_MODEL.tcldict',after);g.shot(w,'constructed-line')
 button('undo');wait(f'expr {{[dict get [{sk} state] history pending]==0}}');assert g.read(f'{sk} get model')==before
 button('redo');wait(f'expr {{[dict get [{sk} state] history pending]==0}}');assert g.read(f'{sk} get model')==after
 button('line');point(cw//2+75,ch*2//3+25);g.xt('key','Escape');wait(f'expr {{![{sk} pending]}}');assert g.read(f'{sk} get model')==after
 button('save');time.sleep(.3)
 surface=g.read(f'{sk} get surface');rect=list(map(int,g.tk.tk.splitlist(g.read(f'{surface} cubeRect'))));l,t,r,b=rect
 viewport=g.read(f'{sk} get viewport');previous=g.read(f'dict get [::GX::native3DViewportInspect {viewport}] camera')
 # Pick a visible edge cell of the native Navigation Cube. Exact native reply,
 # rather than a click receipt, establishes that camera navigation occurred.
 point(l+(r-l)//4,(t+b)//2);time.sleep(.5)
 wait(f'expr {{[dict get [::GX::native3DViewportInspect {viewport}] busy] eq {{}} && ![dict get [::GX::native3DViewportInspect {viewport}] pending]}}')
 current=g.read(f'dict get [::GX::native3DViewportInspect {viewport}] camera');g.save('NAVCUBE.tcldict',g.read(f'::GX::native3DViewportInspect {viewport}'));assert current!=previous,'Native Navigation Cube did not change camera'
 g.shot(w,'native-navcube-and-cad');g.save('RESULT.json',dict(result='PASS',meaning='actual shared Line/Finish, exact GUI Undo/Redo, Escape, Save; native Navigation Cube changed camera'))
finally:g.tk.destroy()
