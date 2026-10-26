#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,json,time,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'dev111_p022'))
from gui import Gui
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('framework',type=Path);a=p.parse_args();assert not a.output.exists();g=Gui(a.launch,a.output);checks={}
def shot(w,label):
 time.sleep(.4) # inspect painted pixels after Tk/X11 expose, not only callback state
 g.shot(w,label)
def read(s):return g.read(s)
def wait(s,limit=40):
 end=time.monotonic()+limit
 while time.monotonic()<end:
  if str(read(s))=='1':return
  time.sleep(.05)
 raise AssertionError(('Timeout',s))
def settled():
 wait('set r [::GX::native3DViewportInspect $::ResidentDemo::view];set ready [expr {[dict get $r status] eq {ready} && ![dict get $r pending] && [dict get $r busy] eq {}}];set frame [$::ResidentDemo::surface frame];set canvas [$::ResidentDemo::surface canvas];if {$frame eq {} || [dict get $frame width]!=[winfo width $canvas] || [dict get $frame height]!=[winfo height $canvas]} {set ready 0};foreach b $::ResidentDemo::bindings {if {[dict get [$b info] pending] || [dict get [[dict get [$b info] surface] resourcesInfo] pending]} {set ready 0}};return $ready')
def editor():return str(read('set ::ResidentDemo::editor'))
def exact(sk):return read(f'{sk} get model')
def status(sk):return read(f'dict get [{sk} state] history')
def click(w):g.click(w);settled()
def wait_editor():
 wait('expr {$::ResidentDemo::editor ne {} && [string first "Editing [$::ResidentDemo::editor get document_id] " $::ResidentDemo::status]==0 && [$::ResidentDemo::editor get projection] ne {} && [dict get [[$::ResidentDemo::editor get projection] info] ready]}')
 time.sleep(.3)
 settled();return editor()
def drag_control(sk,cancel=False):
 c=str(read(f'[{sk} get host] canvas'));g.activate(c)
 script=f'''set sk {sk};set h [$sk get host];set scene [$sk get scene];set result {{}};foreach id [::GX::Native2D::core ids $scene] {{foreach ref [::GX::Native2D::core interaction_controls $scene $id] {{set p [$h device [dict get $ref point]];lassign $p x y;if {{$x>45 && $y>180 && $x<[winfo width [$h canvas]]-80 && $y<[winfo height [$h canvas]]-50 && [winfo containing -displayof [$h canvas] [expr {{int([winfo rootx [$h canvas]]+$x)}}] [expr {{int([winfo rooty [$h canvas]]+$y)}}]] eq [$h canvas]}} {{set result [list $id [dict get $ref index] $x $y];break}}}};if {{$result ne {{}}}} break}};return $result'''
 ref=g.tk.tk.splitlist(read(script));assert len(ref)==4,ref
 _,rx,ry,_,_=g.geometry(c);x,y=map(float,ref[2:]);x,y=int(x),int(y)
 before=exact(sk);hist=status(sk);started=time.monotonic_ns()
 g.xt('mousemove',rx+x,ry+y,'mousedown',1);time.sleep(.1)
 assert not read('grab current'),read('grab current')
 for i in range(1,5):g.xt('mousemove',rx+x+24*i//4,ry+y-16*i//4);time.sleep(.03)
 if cancel:g.xt('key','Escape')
 g.xt('mouseup',1)
 wait(f'expr {{![::GX::Native2D::core drag_active [{sk} get scene]] && ![[{sk} get host] pointerActive] && [dict get [{sk} state] history pending]==0}}');settled()
 after=exact(sk);afterhist=status(sk)
 g.save(('CANCEL' if cancel else 'MOVE')+'_SCIENCE.tcldict',dict(before=before,after=after,history_before=hist,history_after=afterhist,reference=ref,elapsed_ms=(time.monotonic_ns()-started)/1e6))
 if cancel:assert after==before and afterhist==hist,('Cancel changed science/History',afterhist,hist)
 else:assert after!=before,'Actual pointer edit did not change defining geometry'
 return before,after
try:
 g.activate('.');settled();shot('.','01-closed-native-depth')
 checks['initial_closed_native']=dict(result='PASS',resource_info=read('$::ResidentDemo::surface resourcesInfo'),independent_procs=read('info procs ::GX::Workbench3D::*'))
 assert not checks['initial_closed_native']['independent_procs']
 # Locate the visible endpoint with the existing native mapper, then pick it
 # through actual Canvas press/release and the Native3D picking pipeline.
 point=read('::GX::native3DProjectionEnsure;set d [lindex $::ResidentDemo::documents 0];set entry [dict get [::GX::nativeCadSketchQuickOpenList [list $d]] $d];set map [::GX3DEProjection::create [$::ResidentDemo::surface frame] [dict get $entry normalized_frame]];try {set p [dict get [$map map to_screen {{-3 0}}] points]} finally {$map dispose};return [lindex $p 0]')
 x,y=map(float,g.tk.tk.splitlist(point));_,rx,ry,cw,ch=g.geometry('.body.view.canvas');assert 0<x<cw and 0<y<ch
 g.xt('mousemove',rx+round(x),ry+round(y),'click',1);settled()
 wait('expr {$::ResidentDemo::selected ne {}}')
 picked=read('dict get [$::ResidentDemo::selected info] document_id');assert picked==read('lindex $::ResidentDemo::documents 0')
 checks['native_pick']=dict(result='PASS',document=picked,position=[x,y]);shot('.','02-picked-native')
 click('.tools.picked');sk=wait_editor();assert read(f'{sk} get document_id')==picked
 before,after=drag_control(sk);shot('.','03-edited-native-and-handles')
 undo=read(f'dict get $::GX::ViewerCommands::windows [{sk} widget] toolbar buttons undo');click(undo)
 assert exact(sk)==before,'GUI Undo did not restore exact model'
 redo=read(f'dict get $::GX::ViewerCommands::windows [{sk} widget] toolbar buttons redo');click(redo)
 assert exact(sk)==after,'GUI Redo did not restore exact model'
 checks['edit_undo_redo']=dict(result='PASS',document=picked)
 # Cancel is a separate fresh gesture with no scientific History submission.
 drag_control(sk,True);checks['cancel']=dict(result='PASS')
 click('.tools.save');saved=exact(sk);click('.tools.close');assert not editor();shot('.','04-closed-after-save')
 wait('[lindex $::ResidentDemo::bindings 0] ready')
 click('.tools.picked');sk=wait_editor();assert exact(sk)==saved and read(f'{sk} get document_id')==picked
 checks['save_close_reopen']=dict(result='PASS',document=picked,exact_model_restored=True)
 click('.tools.close')
 switch=[]
 for id in ['editB','editC','editA']:
  t=time.monotonic_ns();click('.tools.'+id);sk=wait_editor();switch.append(dict(button=id,ms=(time.monotonic_ns()-t)/1e6,document=read(f'{sk} get document_id')))
  if id=='editC':
   assert read(f'[{sk} get resident] qualityValid')=='0','Unsupported native stroke did not retain its exact overlay style'
   shot('.','05a-active-dashed-style-fallback')
   checks['styled_geometry']=dict(result='PASS',native_active_fallback=True)
  click('.tools.close')
 checks['three_plane_switch']=dict(result='PASS',samples=switch)
 click('.tools.hideB');wait('expr {![dict get [[lindex $::ResidentDemo::bindings 1] info] hidden]==0}');shot('.','05-hidden-B')
 click('.tools.showB');wait('[lindex $::ResidentDemo::bindings 1] ready');checks['visibility']=dict(result='PASS')
 click('.tools.editA');sk=wait_editor();model=exact(sk);history=status(sk)
 read(f'source {{{a.framework.resolve()}/validation/dev111_p023_exp01/counter.tcl}};::EXP01Counter::start count')
 # Real buttons and camera input; no scientific callbacks are invoked by tests.
 click('.body.view.tools.front')
 wait(f'expr {{![dict get [[{sk} get projection] info] ready]}}');assert exact(sk)==model
 wait('set c [$::ResidentDemo::surface canvas];expr {[$c find withtag cad_projection_status] ne {} && [$c find withtag cad_projected_axes] eq {}}')
 shot('.','06-edge-on-science-preserved')
 click('.body.view.tools.top');wait_editor();assert exact(sk)==model
 c=str(read(f'[{sk} get host] canvas'));_,rx,ry,cw,ch=g.geometry(c)
 g.xt('mousemove',rx+cw//2,ry+ch//2,'keydown','space','mousedown',1)
 for i in range(1,5):g.xt('mousemove',rx+cw//2+8*i,ry+ch//2+4*i);time.sleep(.03)
 g.xt('mouseup',1,'keyup','space');settled()
 g.xt('mousemove',rx+cw//2,ry+ch//2,'click','--repeat',3,'--delay',60,4);settled()
 counters=read('::EXP01Counter::stop');g.save('CAMERA_COUNTER.tcldict',counters)
 assert exact(sk)==model and status(sk)==history,'Camera changed science or History'
 checks['camera_invalid_recovery']=dict(result='PASS',science_unchanged=True)
 shot('.','07-camera-recovery')
 click('.tools.close');checks['final_sources']=dict(result='PASS',documents=read('::GX::interactiveDocumentSourceIdentities $::ResidentDemo::documents'))
 g.save('RESULT.json',dict(result='PASS',checks=checks,source_commit=json.loads(Path(a.launch).read_text())['source_commit']))
except Exception as e:
 try:shot('.','FAILURE')
 except Exception:pass
 g.save('RESULT.json',dict(result='FAIL',error=repr(e),completed_checks=checks));raise
finally:g.tk.destroy()
