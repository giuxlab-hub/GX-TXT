#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
from pathlib import Path
import argparse,time
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output');p.add_argument('mode');p.add_argument('--keep',action='store_true');a=p.parse_args();g=Gui(a.launch,a.output)
try:
 g.activate('.');g.config(a.mode)
 old=set(g.tk.tk.splitlist(g.read('winfo children .')));g.viewer('C++ Native3D')
 deadline=time.monotonic()+40
 while time.monotonic()<deadline:
  new=[x for x in g.tk.tk.splitlist(g.read('winfo children .')) if x not in old and x.startswith('.gxViewerDevPreview')]
  if new:
   w=new[0];data=g.read(f'set out {{}};dict for {{h r}} $::GX::Native3DCanvas::instances {{if {{[string match {{{w}.*}} [dict get $r widget]]}} {{set out [::GX::native3DViewportInspect $h]}}}};return $out')
   if data and g.tk.tk.call('dict','get',data,'status') in ['ready','error']:break
  time.sleep(.1)
 else:raise AssertionError('No ready authored Viewer')
 g.save('BEFORE.tcldict',data);assert g.tk.tk.call('dict','get',data,'status')=='ready',data
 canvas=w+'.body.canvas.graphics.canvas';g.drag=None
 _,x,y,width,height=g.geometry(canvas);g.xt('mousemove',x+width//2,y+height//2,'mousedown',1)
 for i in range(1,9):g.xt('mousemove',x+width//2+i*4,y+height//2+i*2);time.sleep(.012)
 g.xt('mouseup',1);time.sleep(1)
 g.xt('mousemove',x+width//2,y+height//2,'click',4);time.sleep(.5)
 g.save('AFTER.tcldict',g.read(f'set out {{}};dict for {{h r}} $::GX::Native3DCanvas::instances {{if {{[string match {{{w}.*}} [dict get $r widget]]}} {{set out [::GX::native3DViewportInspect $h]}}}};return $out'))
 g.shot(w,'colored-cube-orbit-zoom')
 if not a.keep:
  g.activate(w);g.xt('key','--clearmodifiers','alt+F4');time.sleep(.3)
  modal=g.read('grab current')
  if modal==w+'.__tk__messagebox':g.click(modal+'.yes')
 g.save('RESULT.json',dict(result='PASS',mode=a.mode,meaning='normal Configuration Save, actual authored Viewer startup/orbit/wheel; screenshots require visual review'))
finally:g.tk.destroy()
