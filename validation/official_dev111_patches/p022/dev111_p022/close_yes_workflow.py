#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools';base=w+'.body.canvas.scene_pending.geometry_viewport.native3d';canvas=base+'.canvas'
def wait(expr):
 end=time.monotonic()+40
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.07)
 raise AssertionError(expr)
def button(action):g.reveal(tools+'.'+action,ins);g.click(tools+'.'+action)
def opened():
 wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready] && !$::GX::Engine3D::workerBusy}');wait(f'winfo viewable {base}.cad_tools.body.commands');wait(f'expr {{[winfo width {base}.cad_tools.body.commands]>1}}');time.sleep(.2);return g.read('set ::GX::Workbench3D::sketchComponent')
try:
 g.activate(w);button('cad_sketch_open');sk=opened();doc=g.read(f'{sk} get document_id');before=g.read(f'{sk} get model');history=g.read(f'dict get [{sk} state] history');g.save('BEFORE.tcldict',g.read(f'{sk} state'))
 g.click(base+'.cad_tools.body.commands');menu=base+'.cad_tools.body.commands.menu';g.menu(menu,'Create');child=g.read(f'{menu} entrycget 0 -menu');g.menu(child,'Polyline')
 _,rx,ry,cw,ch=g.geometry(canvas)
 for dx,dy in [(0,0),(30,-15),(60,5)]:g.xt('mousemove',rx+cw//2+dx,ry+ch*2//3+dy,'click',1);time.sleep(.25)
 construction=g.read(f'dict get [[{sk} get advanced] state] construction');g.save('STAGED.tcldict',construction);assert g.tk.tk.call('dict','get',construction,'family')=='polyline';assert g.read(f'{sk} pending')=='1'
 button('cad_sketch_close');modal=w+'.__tk__messagebox';wait(f'winfo viewable {modal}.yes');g.shot(w,'unfinished-close-choice');g.click(modal+'.yes');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');wait('expr {!$::GX::Engine3D::workerBusy}');g.shot(w,'finished-on-close')
 saved=g.read(f'dict get [::GX::interactiveDocumentRead {doc}] payload model');g.save('SAVED_MODEL.tcldict',saved);assert saved!=before
 button('cad_sketch_open');sk=opened();assert g.read(f'{sk} get document_id')==doc;assert g.read(f'{sk} get model')==saved
 h=g.read(f'dict get [{sk} state] history');assert int(g.tk.tk.call('dict','get',h,'count'))==int(g.tk.tk.call('dict','get',history,'cursor'))+1
 families=g.read(f'set model [{sk} get model];set out {{}};dict for {{key entry}} $model {{if {{[string match object/* $key]}} {{lappend out [list $key [dict get $entry definition family] [llength [dict get $entry definition controls]]]}}}};return $out');g.save('RETAINED_TOPOLOGY.tcllist',families);assert any(g.tk.tk.splitlist(row)[1:] == ('polyline','3') for row in g.tk.tk.splitlist(families))
 g.save('REOPENED.tcldict',g.read(f'{sk} state'));g.shot(w,'reopened-finished-polyline');g.save('RESULT.json',dict(result='PASS',document=doc,meaning='actual Create/Polyline three points; Close Yes finished and saved exactly; same Document/History reopened'))
finally:g.tk.destroy()
