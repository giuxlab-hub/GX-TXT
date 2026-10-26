#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,time,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'dev111_p022'))
from gui import Gui
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('framework');p.add_argument('--window',default='.gxViewerDevPreview1');a=p.parse_args();g=Gui(a.launch,a.output);checks={}
def read(s):return g.read(s)
def wait(s):
 end=time.monotonic()+45
 while time.monotonic()<end:
  if str(read(s))=='1':return
  time.sleep(.05)
 raise AssertionError(s)
def settled():
 wait('set stable [expr {!$::GX::Engine3D::workerBusy && ![llength $::GX::Engine3D::cameraQueue]}];dict for {key binding} $::GX::NativeCadSketchScene::bindings {if {[dict get [$binding info] pending] || [dict get [[dict get [$binding info] surface] resourcesInfo] pending]} {set stable 0}};return $stable')
def tool(sk,id):return str(read(f'dict get $::GX::ViewerCommands::windows [{sk} widget] toolbar buttons {id}'))
def exact(sk):return str(read(f'{sk} get model'))
try:
 w=a.window;g.activate(w);settled();sk=str(read('set ::GX::Workbench3D::sketchComponent'));assert sk
 original=exact(sk);doc=read(f'{sk} get document_id')
 g.click(tool(sk,'redo'));settled();redone=exact(sk);assert redone!=original
 checks['redo']='PASS'
 c=read(f'[{sk} get host] canvas');ref=g.tk.tk.splitlist(read(f'set sk {sk};set host [$sk get host];set scene [$sk get scene];set id [lindex [::GX::Native2D::core ids $scene] 0];set r [lindex [::GX::Native2D::core interaction_controls $scene $id] 0];return [$host device [dict get $r point]]'))
 x,y=map(lambda x:round(float(x)),ref);_,rx,ry,cw,ch=g.geometry(c)
 history=read(f'dict get [{sk} state] history');g.activate(c)
 g.xt('mousemove',rx+x,ry+y,'mousedown',1);time.sleep(.15)
 for i in range(1,5):g.xt('mousemove',rx+x+15*i//4,ry+y-10*i//4);time.sleep(.05)
 g.save('CANCEL_PREVIEW.tcldict',read(f'[{sk} get host] state'));assert read(f'[{sk} get host] pointerActive')=='1','Test did not start a native gesture'
 g.xt('key','Escape');time.sleep(.1);g.xt('mouseup',1);settled()
 g.save('CANCEL_RESULT.tcldict',dict(model=exact(sk),history=read(f'dict get [{sk} state] history'),expected_history=history))
 assert exact(sk)==redone and read(f'dict get [{sk} state] history')==history
 checks['cancel_no_science_history']='PASS'
 g.click(tool(sk,'save'));settled();saved=exact(sk);g.shot(w,'01-saved-native')
 viewport=w+'.body.inspector.scroll';button=viewport+'.content.property_tabs.solid_tab.solid_tools.cad_sketch_close';opener=button.replace('_close','_open')
 g.reveal(button,viewport);settled();g.click(button);wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');settled();wait('set ok 1;dict for {key b} $::GX::NativeCadSketchScene::bindings {if {![$b ready]} {set ok 0}};return $ok');g.save('CLOSED_BINDINGS.tcldict',read('set rows {};dict for {key b} $::GX::NativeCadSketchScene::bindings {dict set rows $key [$b info]};return $rows'));time.sleep(.3);g.shot(w,'02-editor-closed-body-visible')
 g.reveal(opener,viewport);settled();time.sleep(.2);g.click(opener);wait('expr {$::GX::Workbench3D::sketchComponent ne {}}');settled();sk=str(read('set ::GX::Workbench3D::sketchComponent'))
 assert read(f'{sk} get document_id')==doc and exact(sk)==saved
 checks['same_document_save_close_reopen']='PASS'
 # Real fixed-size line tool; exactly two accepted viewport inputs, then Finish.
 g.click(tool(sk,'line'));settled();c=read(f'[{sk} get host] canvas');_,rx,ry,cw,ch=g.geometry(c)
 for px,py in [(cw-160,ch-130),(cw-70,ch-80)]:g.xt('mousemove',rx+px,ry+py,'click',1);time.sleep(.2)
 settled();
 if read('grab current'):
  modal=read('grab current');g.save('BRANCH_PROMPT.txt',read(f'{modal}.msg cget -text'));g.click(modal+'.ok');settled()
 constructed=exact(sk);assert constructed!=saved
 g.click(tool(sk,'finish'));settled();assert read(f'dict get [[[{sk} get host] advanced] state] construction')==''
 g.shot(w,'03-gui-line-finished');g.click(tool(sk,'undo'));settled();assert exact(sk)==saved
 checks['gui_construction_finish_undo']='PASS'
 g.click(tool(sk,'save'));settled()
 g.save('SCIENCE.tcldict',dict(document=doc,before=original,redone=redone,saved=saved,constructed=constructed,history=read(f'dict get [{sk} state] history')))
 g.save('RESULT.json',dict(result='PASS',checks=checks,source_commit=json.loads(Path(a.launch).read_text())['source_commit']))
except Exception as e:
 try:g.shot(a.window,'FAILURE')
 except Exception:pass
 g.save('RESULT.json',dict(result='FAIL',error=repr(e),checks=checks));raise
finally:g.tk.destroy()
