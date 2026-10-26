#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);a=p.parse_args();g=Gui(a.launch,a.output)
try:
 for mode in ['Software','Auto','Hardware']:
  if g.read('winfo exists .gxInterfacePreview')=='1':
   g.activate('.gxInterfacePreview');g.xt('key','--clearmodifiers','alt+F4');time.sleep(.4)
   assert g.read('winfo exists .gxInterfacePreview')=='0'
  g.activate('.');g.config(mode);g.activate('.gxInterfaceDesigner');g.click('.gxInterfaceDesigner.toolbar.command8')
  end=time.monotonic()+40;record=''
  while time.monotonic()<end:
   record=g.read('set out {};dict for {h r} $::GX::Native3DCanvas::instances {if {[string match {.gxInterfacePreview.*} [dict get $r widget]]} {set out [::GX::native3DViewportInspect $h]}};return $out')
   if record and g.tk.tk.call('dict','get',record,'status') in ['ready','error']:break
   time.sleep(.08)
  assert record and g.tk.tk.call('dict','get',record,'status')=='ready',record
  g.save(mode+'-BEFORE.tcldict',record);g.activate('.gxInterfacePreview')
  c='.gxInterfacePreview.body.canvas.native3d_1.canvas';_,x,y,cw,ch=g.geometry(c);g.xt('mousemove',x+cw//2,y+ch//2,'mousedown',1)
  for i in range(1,7):g.xt('mousemove',x+cw//2+6*i,y+ch//2+3*i);time.sleep(.015)
  g.xt('mouseup',1);time.sleep(.5);g.shot('.gxInterfacePreview',mode+'-preview-orbit')
  g.save(mode+'-AFTER.tcldict',g.read('set out {};dict for {h r} $::GX::Native3DCanvas::instances {if {[string match {.gxInterfacePreview.*} [dict get $r widget]]} {set out [::GX::native3DViewportInspect $h]}};return $out'))
 g.save('RESULT.json',dict(result='PASS',meaning='actual Configuration Software/Auto/Hardware and Builder native3D Preview Close/Reopen/orbit; native identity receipts and screenshot visual review required'))
finally:g.tk.destroy()
