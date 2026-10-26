#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse,json,os,re,subprocess,time,tkinter
from pathlib import Path
class Gui:
 def __init__(self,launch,out):
  self.launch=json.loads(Path(launch).read_text());self.out=Path(out);self.out.mkdir(exist_ok=True)
  os.environ['DISPLAY']=self.launch['graphics_environment']['DISPLAY'];os.environ['XAUTHORITY']=self.launch['graphics_environment']['XAUTHORITY']
  self.tk=tkinter.Tk();self.tk.withdraw();self.app=None
  for app in self.tk.tk.splitlist(self.tk.tk.call('winfo','interps')):
   if not str(app).startswith('gxtxt_pipeline.tcl'):continue
   try:
    if int(self.tk.tk.call('send',app,'pid'))==self.launch['pid']:self.app=app;break
   except (tkinter.TclError,ValueError):pass
  assert self.app,'Owned application PID not found on recorded display'
  self.trace=self.out/'INPUT.jsonl'
 def read(self,script):
  command=self.tk.tk.call('list','apply',self.tk.tk.call('list',(),script))
  return self.tk.tk.call('send',self.app,command)
 def xt(self,*args):
  with self.trace.open('a') as f:f.write(json.dumps(dict(time_ns=time.monotonic_ns(),app_pid=self.launch['pid'],argv=['xdotool',*map(str,args)]))+'\n')
  subprocess.run(['xdotool',*map(str,args)],check=True,timeout=8)
 def pause(self,t=.25):time.sleep(t)
 def save(self,name,value):
  p=self.out/name
  if isinstance(value,(dict,list)):p.write_text(json.dumps(value,indent=2,default=str)+'\n')
  else:p.write_text(str(value)+'\n')
 def geometry(self,w):
  values=self.tk.tk.splitlist(self.read(f'list [winfo viewable {w}] [winfo rootx {w}] [winfo rooty {w}] [winfo width {w}] [winfo height {w}]'))
  return [int(x) for x in values]
 def click(self,w):
  visible,x,y,width,height=self.geometry(w);assert visible and width>1 and height>1,(w,visible,width,height)
  actual=self.read(f'winfo containing -displayof {w} {x+width//2} {y+height//2}')
  assert actual==w or str(actual).startswith(w+'.'),(w,'covered or clipped',actual)
  self.xt('mousemove',x+width//2,y+height//2,'click',1);self.pause()
 def activate(self,w):
  client=self.read(f'winfo id [winfo toplevel {w}]')
  info=subprocess.check_output(['xwininfo','-id',str(client),'-tree'],text=True)
  match=re.search(r'Parent window id:\s*(0x[0-9a-fA-F]+)',info);assert match,info
  self.xt('windowactivate','--sync',match.group(1));self.pause(.1)
 def tab(self,w,child):
  script='''set target [%s index %s];set hit -1;for {set x 2} {$x<[winfo width %s]} {incr x 2} {if {[%s identify tab $x 10] eq $target} {set hit $x;break}};list $hit [winfo rootx %s] [winfo rooty %s]'''%(w,child,w,w,w,w)
  hit,x,y=map(int,self.tk.tk.splitlist(self.read(script)));assert hit>=0,(w,child)
  self.xt('mousemove',x+hit+4,y+10,'click',1);self.pause();assert self.read(f'{w} select')==child
 def choose(self,w,value):
  values=self.tk.tk.splitlist(self.read(f'{w} cget -values'));index=values.index(value)
  popup=self.read('grab current')
  if not popup:
   visible,rx,ry,width,height=self.geometry(w);assert visible
   px=rx+width-8
   if self.read(f'winfo containing -displayof {w} {px} {ry+height//2}')!=w:px=rx+width//2
   assert self.read(f'winfo containing -displayof {w} {px} {ry+height//2}')==w,(w,'selector clipped')
   self.xt('mousemove',px,ry+height//2,'click',1);self.pause(.35)
  # Read the actual posted native listbox and click its requested row. Keyboard
  # navigation can be consumed by the desktop input method; never infer success.
  lb=w+'.popdown.f.l'
  if self.read(f'winfo exists {lb}')!='1':
   popup=self.read('grab current');assert popup,'Selector did not open'
   candidates=[row[0] for row in self.widgets(popup) if row[1]=='Listbox']
   assert len(candidates)==1,(popup,candidates)
   lb=candidates[0];assert self.tk.tk.splitlist(self.read(f'{lb} get 0 end'))==values
  box=self.tk.tk.splitlist(self.read(f'{lb} bbox {index}'))
  assert len(box)==4,(lb,index,box)
  x,y,bw,bh=map(int,box);_,rx,ry,_,_=self.geometry(lb)
  self.xt('mousemove',rx+x+max(2,bw//2),ry+y+bh//2,'click',1)
  self.pause();assert self.read(f'{w} get')==value
 def fill(self,w,value):
  self.click(w);self.xt('key','Home','shift+End','BackSpace')
  if value:self.xt('type','--clearmodifiers','--delay','80',value)
  self.pause()
  assert self.read(f'{w} get')==value
 def menu(self,w,label):
  script='''set target -1;for {set i 0} {$i<=[%s index end]} {incr i} {if {[%s type $i] ne {separator} && [%s entrycget $i -label] eq {%s}} {set target $i;break}};if {$target<0} {error {Menu label missing}};set y [%s yposition $target];set height [expr {[font metrics [%s cget -font] -linespace]+6}];if {$target<[%s index end]} {set height [expr {[%s yposition [expr {$target+1}]]-$y}]};list [winfo viewable %s] [winfo rootx %s] [winfo rooty %s] $y $height'''%(w,w,w,label,w,w,w,w,w,w,w)
  visible,x,y,offset,height=map(int,self.tk.tk.splitlist(self.read(script)));assert visible
  self.xt('mousemove',x+70,y+offset+height//2,'click',1);self.pause()
 def shot(self,w,label):
  visible,x,y,width,height=self.geometry(w);assert visible and width>1 and height>1,(w,visible,width,height)
  name=self.out/(label+'.png');assert not name.exists()
  subprocess.run(['import','-silent','-window','root','-crop',f'{width}x{height}+{x}+{y}',str(name)],check=True,timeout=8)
 def widgets(self,w='.'):
  script='''proc ::p022Widgets {w} {set rows {};foreach c [winfo children $w] {set text {};catch {set text [$c cget -text]};set row [list $c [winfo class $c] [winfo viewable $c] $text];lappend rows $row;if {[winfo class $c] ni {Menu}} {lappend rows {*}[::p022Widgets $c]}};return $rows};::p022Widgets %s'''%w
  return [self.tk.tk.splitlist(r) for r in self.tk.tk.splitlist(self.read(script))]
 def config(self,mode):
  self.tab('.top.nb','.top.nb.configuration');self.tab('.top.nb.configuration.sections','.top.nb.configuration.sections.viewers')
  p='.top.nb.configuration.sections.viewers.native3dTabs.graphics'
  self.choose(p+'.value_execution',mode);self.shot('.',f'config-{mode}-draft-{time.monotonic_ns()}')
  self.click('.top.nb.configuration.actions.save');self.pause(.5)
  actual=self.read('::GX::native3dGraphicsPolicy');self.save(f'policy-{mode}-{time.monotonic_ns()}.tcldict',actual)
  assert self.read('::GX::configurationGet viewers.native3d.execution')==mode
  self.shot('.',f'config-{mode}-saved-{time.monotonic_ns()}')
 def viewer(self,label):
  # Native wheel navigation avoids relying on desktop input-method handling of
  # rapidly changing search text. It uses the ordinary unfiltered Viewer tiles.
  self.tab('.top.nb','.top.nb.viewers');self.fill('.top.nb.viewers.tools.search','');self.pause(.5)
  found=[row[0] for row in self.widgets('.top.nb.viewers') if row[1]=='TButton' and row[3]==label]
  assert len(found)==1,(label,found)
  for _ in range(30):
   _,x,y,width,height=self.geometry(found[0]);px,py=x+width//2,y+height//2
   actual=self.read(f'winfo containing -displayof . {px} {py}')
   if actual==found[0]:break
   _,vx,vy,vw,vh=self.geometry('.top.nb.viewers.viewport')
   self.xt('mousemove',vx+vw//2,vy+vh//2,'click','--repeat','3','--delay','100',4 if py<vy else 5);self.pause(.15)
  else:raise AssertionError(('Viewer tile not reachable',label))
  self.click(found[0]);self.pause(.8)
 def reveal(self,w,viewport):
  for _ in range(40):
   _,x,y,width,height=self.geometry(w);px,py=x+width//2,y+height//2
   if self.read(f'winfo containing -displayof . {px} {py}')==w:return
   _,vx,vy,vw,vh=self.geometry(viewport)
   # Native3D sidebar children own the pointer and do not inherit Canvas wheel
   # bindings. Use its real scrollbar thumb, never a programmatic yview setter.
   bar=viewport.rsplit('.',1)[0]+'.bar'
   if self.read(f'winfo exists {bar}')=='1' and self.read(f'winfo viewable {bar}')=='1' and self.read(f'{bar} cget -command')==viewport+' yview':
    _,bx,by,bw,bh=self.geometry(bar)
    parts=self.tk.tk.splitlist(self.read(f'set rows {{}};for {{set y 0}} {{$y<[winfo height {bar}]}} {{incr y}} {{lappend rows [{bar} identify [expr {{[winfo width {bar}]/2}}] $y]}};return $rows'))
    slider=[i for i,k in enumerate(parts) if k=='thumb' or k=='slider'];track=[i for i,k in enumerate(parts) if k in ('thumb','slider','trough1','trough2','trough')]
    if not slider or not track:
     self.xt('mousemove',vx+vw//2,vy+vh//2,'click','--repeat','2','--delay','70',4 if py<vy else 5);self.pause(.2);continue
    first,last=map(float,self.tk.tk.splitlist(self.read(f'{bar} get')))
    region=list(map(float,self.tk.tk.splitlist(self.read(f'{viewport} cget -scrollregion'))));total=region[3]-region[1]
    target=max(0,min(1-(last-first),first+(py-(vy+vh/2))/total))
    offset=round((target-first)*(track[-1]-track[0]+1))
    sy=(slider[0]+slider[-1])//2
    self.xt('mousemove',bx+bw//2,by+sy,'mousedown',1,'mousemove',bx+bw//2,by+sy+offset,'mouseup',1);self.pause(.2)
   else:
    self.xt('mousemove',vx+vw//2,vy+vh//2,'click','--repeat','3','--delay','70',4 if py<vy else 5);self.pause(.1)
  raise AssertionError(('Not reachable',w))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('launch');p.add_argument('output');p.add_argument('command');p.add_argument('args',nargs='*');a=p.parse_args();g=Gui(a.launch,a.output)
 try:
  if a.command in ['inspect','widgets']:
   rows=g.widgets(a.args[0] if a.args else '.');g.save('WIDGETS.json',rows)
   for row in rows:
    if row[2]=='1' and (row[3] or row[1] in ['Notebook','TNotebook','Treeview']):print(row)
  elif a.command=='config':g.config(a.args[0]);print(g.read('::GX::native3dGraphicsPolicy'))
  elif a.command=='viewer':g.viewer(a.args[0])
  elif a.command=='open-session':
   g.tab('.top.nb','.top.nb.sessionfiles');g.click('.top.nb.sessionfiles.bar.session');g.menu('.top.nb.sessionfiles.bar.session.menu','Open Session...')
   deadline=time.monotonic()+20
   while time.monotonic()<deadline:
    if g.read('expr {[winfo exists .__tk_choosedir.contents.f2.ent] && [winfo viewable .__tk_choosedir.contents.f2.ent] && [winfo width .__tk_choosedir.contents.f2.ent]>1}')=='1':break
    time.sleep(.1)
   g.fill('.__tk_choosedir.contents.f2.ent',a.args[0]);g.click('.__tk_choosedir.contents.f2.ok');g.click('.__tk_choosedir.contents.f2.ok')
   assert g.read('set ::GX::currentSession')==a.args[0]
  elif a.command=='read':
   value=g.read(a.args[0]);g.save('OBSERVATION-'+str(time.monotonic_ns())+'.tcldict',value);print(value)
  elif a.command=='click':g.click(a.args[0])
  elif a.command=='point':
   w=a.args[0];px,py=map(int,a.args[1:3]);visible,x,y,width,height=g.geometry(w);assert visible and 0<=px<width and 0<=py<height
   g.xt('mousemove',x+px,y+py,'click',int(a.args[3]) if len(a.args)>3 else 1);g.pause()
  elif a.command=='fill':g.fill(*a.args)
  elif a.command=='choose':g.choose(*a.args)
  elif a.command=='reveal':g.reveal(*a.args)
  elif a.command=='tab':g.tab(*a.args)
  elif a.command=='row':
   w,item=a.args[:2];box=g.tk.tk.splitlist(g.read(f'{w} bbox {{{item}}}'))
   for _ in range(25):
    if len(box)==4:break
    _,tx,ty,tw,th=g.geometry(w)
    target=int(g.read(f'{w} index {{{item}}}'));top=g.read(f'if {{[catch {{{w} identify row 12}} row]}} {{set row {{}}}};return $row');first=int(g.read(f'{w} index {{{top}}}')) if top else 0
    g.xt('mousemove',tx+tw//2,ty+th//2,'click','--repeat','2','--delay','60',4 if target<first else 5);g.pause(.15)
    box=g.tk.tk.splitlist(g.read(f'{w} bbox {{{item}}}'))
   assert len(box)==4
   x,y,width,height=map(int,box);_,rx,ry,_,_=g.geometry(w)
   g.xt('mousemove',rx+x+width//2,ry+y+height//2,'click',int(a.args[2]) if len(a.args)>2 else 1);g.pause()
  elif a.command=='menu':g.menu(*a.args)
  elif a.command=='key':g.xt('key',*a.args)
  elif a.command=='drag':
   w=a.args[0];dx,dy,steps=map(int,a.args[1:4]);visible,x,y,width,height=g.geometry(w);assert visible
   sx=x+width//2;sy=y+height//2
   g.xt('mousemove',sx,sy,'mousedown',1)
   for i in range(1,steps+1):g.xt('mousemove',sx+dx*i//steps,sy+dy*i//steps);g.pause(.025)
   g.xt('mouseup',1)
  elif a.command=='type':g.xt('type','--clearmodifiers','--delay','1',a.args[0])
  elif a.command=='shot':g.shot(*a.args)
  elif a.command=='close':
   g.activate(a.args[0]);g.xt('key','--clearmodifiers','alt+F4');g.pause()
  elif a.command=='activate':g.activate(a.args[0])
  elif a.command=='tree':
   script='''proc ::p022Tree {w parent} {set r {};foreach id [$w children $parent] {lappend r [list $id [$w item $id -text] [$w item $id -values]];lappend r {*}[::p022Tree $w $id]};return $r};::p022Tree %s {}'''%a.args[0]
   v=g.read(script);g.save('TREE.tcllist',v);print(v)
  else:raise ValueError(a.command)
 finally:g.tk.destroy()
