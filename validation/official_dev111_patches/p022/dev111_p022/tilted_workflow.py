#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('--window',required=True);p.add_argument('--resume',action='store_true');a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools';base=w+'.body.canvas.scene_pending.geometry_viewport.native3d';form=base+'.workingPlane'
def wait(expr,limit=40):
 end=time.monotonic()+limit
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.06)
 raise AssertionError(expr)
def button(name):g.reveal(tools+'.'+name,ins);g.click(tools+'.'+name)
def opened():
 wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}')
 wait('expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}')
 return g.read('set ::GX::Workbench3D::sketchComponent')
def point(c,x,y):
 _,rx,ry,cw,ch=g.geometry(c);g.xt('mousemove',rx+x,ry+y,'click',1);time.sleep(.25)
try:
 g.activate(w)
 if not a.resume:
  if g.read(f'winfo exists {form}')!='1':button('cad_working_plane_form')
  for i,value in enumerate(['5;2;1','1;1;1','1;-1;0']):g.fill(form+f'.viewport.content.field{i}.entry',value)
  g.click(form+'.actions.apply');time.sleep(.4)
  if g.read(f'winfo exists {form}')=='1':g.click(form+'.actions.close')
  button('cad_sketch_create');sk=opened();doc=g.read(f'{sk} get document_id');plane=g.read(f'{sk} get plane');g.save('PLANE.tcldict',plane)
  g.save('CREATED.tcldict',g.read(f'{sk} state'));c=g.read(f'[{sk} get host] canvas');bar=base+'.cad_tools.body.tools'
  g.click(bar+'.command2');_,_,_,cw,ch=g.geometry(c);point(c,cw//2,ch*2//3);point(c,cw//2+55,ch*2//3-25);g.click(bar+'.command5')
  wait(f'expr {{![{sk} pending] && [dict get [{sk} state] history pending]==0}}')
 else:
  sk=opened();doc=g.read(f'{sk} get document_id');plane=g.read(f'{sk} get plane');c=g.read(f'[{sk} get host] canvas');bar=base+'.cad_tools.body.tools'
  g.save('PLANE.tcldict',plane);g.save('CREATED.tcldict',g.read(f'{sk} state'))
 model=g.read(f'{sk} get model');g.save('MODEL.tcldict',model)
 # Query-only use of the authoritative native coordinate contract supplements
 # the actual construction; no geometry is inserted through these assertions.
 receipt=g.read(f'set sk {sk};set local {{{{0 0}} {{1 0}} {{0 1}} {{2.5 -3.75}}}};set forward [$sk transform to_world $local];set reverse [$sk transform to_plane [dict get $forward points]];list $forward $reverse')
 g.save('NATIVE_FRAME_ROUNDTRIP.tcllist',receipt)
 forward,reverse=g.tk.tk.splitlist(receipt);back=g.tk.tk.call('dict','get',reverse,'points')
 for actual,expected in zip(g.tk.tk.splitlist(back),[(0,0),(1,0),(0,1),(2.5,-3.75)]):
  coords=list(map(float,g.tk.tk.splitlist(actual)));assert all(abs(x-y)<1e-11 for x,y in zip(coords,expected))
 g.shot(w,'tilted-plane-line-and-context');g.click(bar+'.command10');time.sleep(.3)
 history=g.read(f'dict get [{sk} state] history');button('cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}')
 wait('expr {!$::GX::Engine3D::workerBusy}');g.shot(w,'saved-tilted-sketch-closed')
 button('cad_sketch_open');sk=opened();assert g.read(f'{sk} get document_id')==doc;assert g.read(f'{sk} get model')==model
 current=g.read(f'dict get [{sk} state] history');assert g.tk.tk.call('dict','get',current,'count')==g.tk.tk.call('dict','get',history,'count')
 g.save('REOPENED.tcldict',g.read(f'{sk} state'));g.shot(w,'same-tilted-document-reopened')
 button('cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');time.sleep(.3)
 button('cad_sketch_create');other=opened();other_doc=g.read(f'{other} get document_id');assert other_doc!=doc
 g.save('CREATE_AGAIN.tcldict',g.read(f'{other} state'));button('cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}')
 g.save('PRESENTATIONS.tcldict',g.read('::GX::native3DGuiHostDocumentPresentationInspect'))
 g.save('RESULT.json',dict(result='PASS',tilted_document=doc,new_document=other_doc,meaning='actual tilted scientific plane, Line Finish/Save/Close/Reopen exactmodel/History; native frame roundtrip; independent CreateAgain/Close'))
finally:g.tk.destroy()
