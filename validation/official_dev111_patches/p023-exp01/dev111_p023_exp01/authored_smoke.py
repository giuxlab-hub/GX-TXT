#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import sys,time,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'dev111_p022'))
from gui import Gui
g=Gui(sys.argv[1],sys.argv[2]);w=sys.argv[3]
def read(s):return g.read(s)
def wait(s):
 end=time.monotonic()+45
 while time.monotonic()<end:
  if str(read(s))=='1':return
  time.sleep(.1)
 raise AssertionError(s)
def settled():
 wait('set ok 1;dict for {h r} $::GX::Native3DCanvas::instances {set r [::GX::native3DViewportInspect $h];if {[dict get $r status] ne {ready} || [dict get $r busy] ne {} || [dict get $r pending]} {set ok 0}};dict for {key b} $::GX::NativeCadSketchScene::bindings {if {[dict get [$b info] pending] || [dict get [[dict get [$b info] surface] resourcesInfo] pending]} {set ok 0}};return $ok')
def button(text):
 found=[x[0] for x in g.widgets(w) if x[1]=='TButton' and x[2]=='1' and x[3]==text];assert found,(text,found)
 for candidate in found:
  _,x,y,bw,bh=g.geometry(candidate)
  if read(f'winfo containing {x+bw//2} {y+bh//2}')==candidate:return candidate
 raise AssertionError(('No exposed button',text))
try:
 g.activate(w);settled();time.sleep(.25)
 keys=g.tk.tk.splitlist(read(f'dict keys [dict get $::GX::ViewerGui::instances {w} cad_sketches]'));assert len(keys)==1;component=keys[0]
 sk=read(f'dict get $::GX::ViewerGui::instances {w} cad_sketches {component}')
 c=read(f'[{sk} get host] canvas');before=read(f'{sk} get model')
 g.click(button('Line'));settled();_,rx,ry,cw,ch=g.geometry(c)
 for x,y in [(cw//2,ch//2),(cw//2+100,ch//2+60)]:g.xt('mousemove',rx+x,ry+y,'click',1);time.sleep(.2)
 settled();g.click(button('Finish'));settled();after=read(f'{sk} get model');assert after!=before
 g.save('SCIENCE.tcldict',dict(before=before,after=after,state=read(f'::GX::viewerGuiDesignCadState {w} {component}')))
 g.click(button('Undo'));settled();assert read(f'{sk} get model')==before
 g.click(button('Redo'));settled();assert read(f'{sk} get model')==after
 g.click(button('Save'));settled();time.sleep(.3);g.shot(w,'constructed-native-sketch')
 g.save('RENDERER.tcldict',read('set result {};dict for {h r} $::GX::Native3DCanvas::instances {dict set result $h [::GX::native3DViewportInspect $h]};return $result'))
 g.xt('key','--clearmodifiers','alt+F4');time.sleep(.4)
 modal=read('grab current')
 if modal:
  assert 'Save the current Workspace' in read(f'{modal}.msg cget -text')
  g.activate(modal);g.click(modal+'.no') # scientific Document was explicitly saved above
 wait(f'expr {{![winfo exists {w}]}}');time.sleep(.4)
 assert read('winfo exists .bgerrorDialog')=='0','Unexpected Tk background error after close'
 g.save('DISPOSAL.tcldict',read('list $::GX::NativeCadSketchScene::bindings [dict keys $::GX::Native3DCanvas::instances]'))
 g.save('RESULT.json',dict(result='PASS',meaning='actual registered authored Viewer, exact shared line/Finish/Undo/Redo/Save and whole-window disposal',source_commit=json.loads(Path(sys.argv[1]).read_text())['source_commit']))
except Exception as e:
 try:g.shot(w,'FAILURE')
 except Exception:pass
 g.save('RESULT.json',dict(result='FAIL',error=repr(e)));raise
finally:g.tk.destroy()
