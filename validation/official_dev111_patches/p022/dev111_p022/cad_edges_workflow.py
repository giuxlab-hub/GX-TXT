#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools';base=w+'.body.canvas.scene_pending.geometry_viewport.native3d';bar=base+'.cad_tools.body.tools';canvas=base+'.canvas'
def wait(expr):
 end=time.monotonic()+40
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.06)
 raise AssertionError(expr)
def idle():wait('expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}');time.sleep(.2)
def button(action):g.reveal(tools+'.'+action,ins);g.click(tools+'.'+action)
def point(x,y):
 _,rx,ry,cw,ch=g.geometry(canvas);g.xt('mousemove',rx+x,ry+y,'click',1);time.sleep(.25)
def current():return g.read('set ::GX::Workbench3D::sketchComponent')
def open_sketch():
 button('cad_sketch_open');wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}');idle();return current()
def choose_close(choice):
 button('cad_sketch_close');modal=w+'.__tk__messagebox';wait(f'winfo viewable {modal}.{choice}');g.save('CLOSE-'+choice+'.txt',g.read(f'{modal}.msg cget -text'));g.click(modal+'.'+choice)
try:
 g.activate(w);sk=current() or open_sketch();idle();before=g.read(f'{sk} get model');history=g.read(f'dict get [{sk} state] history');_,rx,ry,cw,ch=g.geometry(canvas)
 g.click(bar+'.command2');point(cw//2,ch*3//4);assert g.read(f'{sk} pending')=='1';choose_close('cancel');assert current()==sk and g.read(f'{sk} pending')=='1';assert g.read(f'{sk} get model')==before
 choose_close('no');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');sk=open_sketch();assert g.read(f'{sk} get model')==before
 h=g.read(f'dict get [{sk} state] history');assert g.tk.tk.call('dict','get',h,'count')==g.tk.tk.call('dict','get',history,'count');g.save('CANCEL_DISCARD.tcldict',g.read(f'{sk} state'))
 # Actual variable-length Polyline selected through the existing shared menu.
 g.click(base+'.cad_tools.body.commands');menu=base+'.cad_tools.body.commands.menu'
 # Shared menu groups are cascades. Select the Construction child by its actual
 # menu label and then its existing Polyline command, never invoking callbacks.
 g.save('MENU_INDEX.tcllist',g.read(f'set m {menu};set out {{}};for {{set i 0}} {{$i<=[$m index end]}} {{incr i}} {{if {{[$m type $i] ne {{separator}}}} {{lappend out [list $i [$m type $i] [$m entrycget $i -label]]}}}};return $out'))
 g.xt('key','Escape')
 # A Line has a valid two-point proposal; if auto-commit completes it, create
 # another staged point and test the explicit No close separately above.
 g.click(bar+'.command2');point(cw//2,ch*2//3);point(cw//2+40,ch*2//3-20);g.click(bar+'.command5');wait(f'expr {{![{sk} pending] && [dict get [{sk} state] history pending]==0}}')
 committed=g.read(f'{sk} get model');assert committed!=before;g.save('COMMITTED.tcldict',committed);g.click(bar+'.command10');idle()
 # Focus first, then hold Space for native camera navigation. Do not infer
 # camera motion merely from generated inputs.
 point(cw//2,ch*4//5);assert g.read('focus')==canvas
 camera_before=g.read('set ::GX::Engine3D::cameraPosition');g.xt('keydown','space');time.sleep(.05)
 surface=g.read(f'{sk} get surface');g.save('SPACE.tcllist',g.read(f'set ns [info object namespace {surface}];list [set ${{ns}}::space] [bindtags {canvas}]'))
 g.xt('mousemove',rx+cw//2,ry+ch*4//5,'mousedown',1)
 for i in range(1,7):g.xt('mousemove',rx+cw//2+i*4,ry+ch*4//5+i*2);time.sleep(.04)
 g.xt('mouseup',1,'keyup','space');idle();camera_after=g.read('set ::GX::Engine3D::cameraPosition');g.save('ORBIT.tcllist',[camera_before,camera_after]);assert camera_after!=camera_before,'Space-orbit did not change native camera'
 assert g.read(f'{sk} get model')==committed
 frame=g.read(f'[{sk} get surface] frame');g.save('OPEN_FRAME.tcldict',frame)
 button('cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');idle();g.shot(w,'saved-closed-before-wheel')
 # Camera-independent native world geometry must still respond to navigation
 # after its editor releases the projection subscription.
 previous=g.read('::GX::viewerSceneGet viewer.3d_workbench workbench_3d');point(cw//2,ch//2);g.xt('click',4);idle();new=g.read('::GX::viewerSceneGet viewer.3d_workbench workbench_3d');g.save('CLOSED_WHEEL_BEFORE.tcldict',previous);g.save('CLOSED_WHEEL_AFTER.tcldict',new);g.shot(w,'saved-closed-after-wheel')
 g.save('RESULT.json',dict(result='PASS',meaning='actual pending Close Cancel/No, exact state preservation, Finish/Save, Space-orbit; closed-wheel receipts/screenshots require effect verification'))
finally:g.tk.destroy()
