#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,json,time
from pathlib import Path
from gui import Gui
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('framework',type=Path);p.add_argument('--window',required=True);p.add_argument('--counts',nargs='+',type=int,default=[1,10,50]);p.add_argument('--light-timing',action='store_true');a=p.parse_args()
g=Gui(a.launch,a.output);w=a.window;g.activate(w);ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools';combo=ins+'.content.model_header.geometry_form.geometry_documents.entry'
def observe(script):return g.read(script)
def wait(script,limit=30):
 end=time.monotonic()+limit
 while time.monotonic()<end:
  if str(observe(script))=='1':return
  time.sleep(.05)
 raise AssertionError(('Timed out',script))
def button(path):g.reveal(path,ins);g.click(path)
try:
 g.save('LOADED_CLOSE.tcl',observe('info body ::GX::Workbench3D::sketchClose'))
 for count,document in [(1,'idoc_0002'),(10,'idoc_0004'),(50,'idoc_0006')]:
  if count not in a.counts:continue
  out=a.output/f'objects{count}';out.mkdir(exist_ok=False)
  active=observe('set ::GX::Workbench3D::sketchComponent')
  if active:
   button(tools+'.cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}')
   wait(f"expr {{[{w}.footer.status cget -text] eq {{Action 'cad_sketch_close': completed}}}}")
   time.sleep(.2)
  current=observe('set ::GX::Workbench3D::document')
  if current!=document or not observe('set ::GX::Workbench3D::scene'):
   if observe('set ::GX::Workbench3D::scene'):
    g.click(w+'.toolbar.geometry_close');time.sleep(.5)
    wait('expr {$::GX::Workbench3D::scene eq {}}')
   g.reveal(combo,ins);g.choose(combo,document);g.click(w+'.toolbar.geometry_open')
   wait(f'expr {{$::GX::Workbench3D::document eq {{{document}}} && $::GX::Workbench3D::scene ne {{}}}}')
  g.reveal(tools+'.cad_sketch_open',ins);begin=time.monotonic_ns();g.click(tools+'.cad_sketch_open')
  wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}')
  opened=time.monotonic_ns();sk=observe('set ::GX::Workbench3D::sketchComponent');canvas=observe(f'[{sk} get host] canvas')
  before=observe(f'{sk} get model');g.save(str(Path(f'objects{count}')/'BEFORE.tcldict'),before)
  g.save(str(Path(f'objects{count}')/'HISTORY_BEFORE.tcldict'),observe(f'dict get [{sk} state] history'))
  # Resolve an actual defining control through public scientific references and
  # native projection. Choose an uncovered on-screen handle for real input.
  script=f'''set sk {sk};set host [$sk get host];set scene [$sk get scene];set result {{}};foreach object [::GX::Native2D::core ids $scene] {{foreach control [::GX::Native2D::core interaction_controls $scene $object] {{set p [$host device [dict get $control point]];lassign $p x y;if {{$x>40 && $y>40 && $x<[winfo width [$host canvas]]-45 && $y<[winfo height [$host canvas]]-45 && [winfo containing -displayof [$host canvas] [expr {{int([winfo rootx [$host canvas]]+$x)}}] [expr {{int([winfo rooty [$host canvas]]+$y)}}]] eq [$host canvas]}} {{set result [list $object [dict get $control index] $x $y];break}}}};if {{$result ne {{}}}} break}};return $result'''
  ref=g.tk.tk.splitlist(observe(script));assert len(ref)==4,(count,ref)
  object_id,index,sx,sy=ref;sx=int(float(sx));sy=int(float(sy));_,rx,ry,cw,ch=g.geometry(canvas)
  g.save(str(Path(f'objects{count}')/'CONTROL.json'),dict(object=object_id,index=index,start=[sx,sy],delta=[18,-12],canvas=[cw,ch]))
  observe(f'source {{{a.framework.resolve()}/validation/dev111_p022/timing.tcl}};::P022Timing::start {0 if a.light_timing else 1};::GX::native2DSpriteSceneDiagnostics reset;::GX::native2DSpriteSceneDiagnostics on')
  started=time.monotonic_ns();g.xt('mousemove',rx+sx,ry+sy,'mousedown',1)
  time.sleep(.1)
  modal=observe('grab current')
  if modal==w+'.__tk__messagebox' and observe(f'winfo exists {modal}.ok')=='1':
   # P017 explicitly admits branching after Undo. Confirm through its actual
   # modal, then cancel the initiating gesture whose release the modal consumed.
   g.save(str(Path(f'objects{count}')/'BRANCH_PROMPT.txt'),observe(f'{modal}.msg cget -text'))
   wait(f'winfo viewable {modal}.ok');g.xt('mouseup',1);g.click(modal+'.ok');g.xt('key','Escape');g.xt('mousemove',rx+sx,ry+sy,'mousedown',1)
   started=time.monotonic_ns()
  for i in range(1,5):g.xt('mousemove',rx+sx+18*i//4,ry+sy-12*i//4);time.sleep(.03)
  released=time.monotonic_ns();g.xt('mouseup',1)
  wait(f'expr {{![::GX::Native2D::core drag_active [{sk} get scene]] && ![[{sk} get host] pointerActive]}}')
  wait(f'expr {{[dict get [{sk} state] history pending]==0}}')
  settled=time.monotonic_ns();after=observe(f'{sk} get model')
  assert after!=before,('GUI control did not move',count)
  g.save(str(Path(f'objects{count}')/'AFTER.tcldict'),after)
  g.save(str(Path(f'objects{count}')/'HISTORY_AFTER.tcldict'),observe(f'dict get [{sk} state] history'))
  observe(f'::P022Timing::stop {{{out}/DRAG.tsv}};::GX::native2DSpriteSceneDiagnostics off')
  g.save(str(Path(f'objects{count}')/'SPRITE.tcldict'),observe('::GX::native2DSpriteSceneDiagnostics get'))
  g.shot(w,f'objects{count}-moved')
  undo=observe(f'dict get $::GX::ViewerCommands::windows [{sk} widget] toolbar buttons undo')
  g.click(undo);wait(f'expr {{[dict get [{sk} state] history pending]==0}}')
  restored=observe(f'{sk} get model');g.save(str(Path(f'objects{count}')/'UNDO.tcldict'),restored)
  assert restored==before,('Exact Undo mismatch',count)
  g.save(str(Path(f'objects{count}')/'TIMES.json'),dict(open_ms=(opened-begin)/1e6,gesture_ms=(settled-started)/1e6,post_release_ms=(settled-released)/1e6,observed_settle_includes_query_roundtrips=True))
  g.save(str(Path(f'objects{count}')/'RESULT.json'),dict(result='PASS',meaning='actual defining-control mouse edit and GUI Undo; exact retained model restored'))
finally:
 try:
  g.read('foreach target $::P022Timing::targets {catch {trace remove execution $target {enter leave} ::P022Timing::record}};set ::P022Timing::targets {};::GX::native2DSpriteSceneDiagnostics off')
 except Exception:pass
 g.tk.destroy()
