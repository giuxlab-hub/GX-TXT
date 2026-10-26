#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from gui import Gui
import argparse,time,os,subprocess,signal
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output',type=Path);p.add_argument('framework',type=Path);p.add_argument('mode');p.add_argument('--trace-io',action='store_true');a=p.parse_args();g=Gui(a.launch,a.output)
def wait(expr):
 end=time.monotonic()+45
 while time.monotonic()<end:
  if g.read(expr)=='1':return
  time.sleep(.05)
 raise AssertionError(expr)
try:
 g.activate('.');g.config(a.mode);g.tab('.top.nb','.top.nb.channels')
 tree='.top.nb.channels.browser.tree';item='dataset:703032325f617470'
 g.read(f'source {{{a.framework.resolve()}/validation/dev111_p022/timing.tcl}};::P022Timing::start 0')
 # Actual Dataset row context menu, not a callback invocation.
 box=list(map(int,g.tk.tk.splitlist(g.read(f'{tree} bbox {item}'))));_,rx,ry,_,_=g.geometry(tree)
 x,y,w,h=box;g.xt('mousemove',rx+x+w//2,ry+y+h//2,'click',3);g.pause();g.menu('.top.datasetBrowserMenu','Preview')
 deadline=time.monotonic()+45;owner=''
 while time.monotonic()<deadline:
  owner=g.read('set result {};foreach key [array names ::GX::DatasetViewer::state *,previewWidget] {set w [string range $key 0 end-14];if {[info exists ::GX::DatasetViewer::state($w,image)] && $::GX::DatasetViewer::state($w,image) ne {} && !$::GX::DatasetViewer::state($w,busy)} {set result $w}};return $result')
  if owner:break
  time.sleep(.08)
 assert owner,'No current actual Dataset Preview owner'
 g.read(f'::P022Timing::stop {{{a.output.resolve()}/STARTUP.tsv}}')
 c='.top.nb.preview.geometry';_,x,y,w,h=g.geometry(c)
 g.save('BEFORE.tcldict',g.read(f'array get ::GX::DatasetViewer::state {owner},*'))
 g.read(f'source {{{a.framework.resolve()}/validation/dev111_p022/timing.tcl}};::P022Timing::start 0')
 worker=int(g.read(f'lindex [pid $::GX::DatasetViewer::state({owner},worker)] 0'))
 def sample(pid):
  fields=Path(f'/proc/{pid}/stat').read_text().rsplit(') ',1)[1].split()
  return dict(ticks=int(fields[11])+int(fields[12]),rss_bytes=int(fields[21])*os.sysconf('SC_PAGE_SIZE'),threads=int(fields[17]))
 before_cpu={str(pid):sample(pid) for pid in [g.launch['pid'],worker]}
 tracer=None
 if a.trace_io:
  tracer=subprocess.Popen(['strace','-ttt','-T','-s','0','-yy','-e','trace=openat,write,close,rename,renameat,renameat2,fsync,fdatasync','-p',str(worker),'-o',str(a.output/'NATIVE_IO.strace')],stdout=subprocess.DEVNULL,stderr=(a.output/'STRACE.log').open('w'))
  time.sleep(.1)
 started=time.monotonic_ns();g.xt('mousemove',x+w//2,y+h//2,'mousedown',1)
 for i in range(1,13):g.xt('mousemove',x+w//2+i*4,y+h//2+i*2);time.sleep(.012)
 release=time.monotonic_ns();g.xt('mouseup',1)
 wait(f'expr {{!$::GX::DatasetViewer::state({owner},busy) && ![llength $::GX::DatasetViewer::state({owner},pending)]}}')
 finish=time.monotonic_ns()
 after_cpu={str(pid):sample(pid) for pid in [g.launch['pid'],worker]}
 if tracer is not None:
  tracer.send_signal(signal.SIGINT);tracer.wait(timeout=5)
 g.save('PROCESS_COST.json',dict(before=before_cpu,after=after_cpu,ticks_per_second=os.sysconf('SC_CLK_TCK'),cpu_ms={pid:(after_cpu[pid]['ticks']-before_cpu[pid]['ticks'])*1000/os.sysconf('SC_CLK_TCK') for pid in before_cpu},note='two read-only process samples around actual input; tick-resolution, no polling'))
 g.read(f'::P022Timing::stop {{{a.output.resolve()}/DRAG.tsv}}')
 g.save('AFTER.tcldict',g.read(f'array get ::GX::DatasetViewer::state {owner},*'))
 g.shot('.','molecule-after-orbit')
 g.save('TIMES.json',dict(mode=a.mode,motions=12,elapsed_ms=(finish-started)/1e6,post_release_ms=(finish-release)/1e6,meaning='actual pointer orbit with input/observation overhead'))
finally:g.tk.destroy()
