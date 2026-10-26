#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('expected',type=Path);p.add_argument('--window',required=True);a=p.parse_args();g=Gui(a.launch,a.output);w=a.window;ins=w+'.body.inspector.scroll';tools=ins+'.content.property_tabs.solid_tab.solid_tools';combo=ins+'.content.model_header.geometry_form.geometry_documents.entry'
def wait(script):
 end=time.monotonic()+45
 while time.monotonic()<end:
  if g.read(script)=='1':return
  time.sleep(.1)
 raise AssertionError(script)
try:
 g.activate(w);g.reveal(combo,ins);g.choose(combo,'idoc_0006');g.click(w+'.toolbar.geometry_open');wait('expr {$::GX::Workbench3D::document eq {idoc_0006} && $::GX::Workbench3D::scene ne {}}')
 g.reveal(tools+'.cad_sketch_open',ins);g.click(tools+'.cad_sketch_open');wait('expr {$::GX::Workbench3D::sketchComponent ne {} && [dict get [[$::GX::Workbench3D::sketchComponent get projection] info] ready]}');time.sleep(.5)
 sk=g.read('set ::GX::Workbench3D::sketchComponent');state=g.read(f'{sk} state');model=g.read(f'{sk} get model');assert model==a.expected.read_text().rstrip('\n')
 assert g.read(f'{sk} get document_id')=='idoc_0016'
 assert g.read(f'dict get [{sk} state] history count')=='2';assert g.read(f'dict get [{sk} state] history pending')=='0'
 g.save('RESTORED_STATE.tcldict',state);g.shot(w,'saved-tilted-sketch-after-full-app-restart')
 g.reveal(tools+'.cad_sketch_close',ins);g.click(tools+'.cad_sketch_close');wait('expr {$::GX::Workbench3D::sketchComponent eq {}}');g.shot(w,'saved-visible-after-editor-close')
 g.save('RESULT.json',dict(status='PASS',document='idoc_0016',scope='actual full-application Session/Workbench/Sketch reopen; exact saved tilted model and History count2; saved3D display retained'))
finally:g.tk.destroy()
