#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""CORE read-only raster and timed audio consultation; original files untouched."""
import sys,subprocess,json,array,math,signal
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from PIL import Image,ImageTk
from concurrent.futures import ThreadPoolExecutor
class Reader:
 def __init__(self,path,identity,kind,raw_format="",raw_rate="",raw_channels="",stream_index=""):
  self.input_options=[];self.stream_index=stream_index
  if raw_format and raw_format!="none":
   if raw_format not in {"u8","s16le","s16be","s24le","s24be","s32le","s32be","f32le","f32be","f64le","f64be"} or int(raw_rate)<=0 or int(raw_channels)<=0:raise ValueError("Invalid declared raw PCM metadata")
   self.input_options=["-f",raw_format,"-ar",raw_rate,"-ac",raw_channels]
  self.path=Path(path);self.kind=kind;self.root=tk.Tk();self.root.title('GX-TXT CORE '+kind+' — '+identity)
  self.root.geometry('1100x780');self.pool=ThreadPoolExecutor(max_workers=1);self.closed=False;self.processes=set();self.pending=None;self.zoom=1.;self.start=0.;self.span=30.
  self.bar=ttk.Frame(self.root);self.bar.pack(fill='x');self.status=tk.StringVar(value=identity)
  actions=[('Fit',self.fit),('Zoom +',lambda:self.scale(1.25)),('Zoom −',lambda:self.scale(.8))]
  if kind=='audio':actions += [('Previous interval',lambda:self.navigate(-1)),('Next interval',lambda:self.navigate(1))]
  for label,fn in actions:ttk.Button(self.bar,text=label,command=fn).pack(side='left',padx=4,pady=4)
  self.canvas=tk.Canvas(self.root,bg='white',highlightthickness=0);self.canvas.pack(fill='both',expand=True)
  self.canvas.bind('<ButtonPress-1>',lambda e:self.canvas.scan_mark(e.x,e.y));self.canvas.bind('<B1-Motion>',lambda e:self.canvas.scan_dragto(e.x,e.y,gain=1))
  self.canvas.bind('<Button-4>',lambda e:self.scale(1.25));self.canvas.bind('<Button-5>',lambda e:self.scale(.8))
  ttk.Label(self.root,textvariable=self.status,wraplength=1050).pack(fill='x')
  self.root.protocol('WM_DELETE_WINDOW',self.close);signal.signal(signal.SIGTERM,lambda *_:self.close());self.root.after(100,self.fit)
 def close(self):
  self.closed=True
  for p in tuple(self.processes):
   if p.poll() is None:p.terminate()
  self.pool.shutdown(wait=False,cancel_futures=True);self.root.destroy()
 def run_process(self,cmd,timeout,text=False):
  if self.closed:raise RuntimeError('Reader closed')
  p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=text);self.processes.add(p)
  try:
   if self.closed:p.terminate()
   try:out,err=p.communicate(timeout=timeout)
   except subprocess.TimeoutExpired:p.kill();p.communicate();raise
   if p.returncode:raise subprocess.CalledProcessError(p.returncode,cmd,out,err)
   return subprocess.CompletedProcess(cmd,p.returncode,out,err)
  finally:self.processes.discard(p)
 def fit(self):
  try:self._fit()
  except Exception as e:self.status.set(str(e))
 def _fit(self):
  if self.kind=='image':
   with Image.open(self.path) as im:
    if im.width*im.height>64_000_000:raise ValueError('Image exceeds 64 million pixel consultation budget')
    self.zoom=min((self.canvas.winfo_width()-20)/im.width,(self.canvas.winfo_height()-20)/im.height)
  else:self.span=30.
  self.render()
 def scale(self,f):
  if self.kind=='image':self.zoom=max(.01,min(16,self.zoom*f))
  else:self.span=max(.01,min(300,self.span/f))
  self.render()
 def navigate(self,d):self.start=max(0,self.start+d*self.span);self.render()
 def render(self):
  if self.pending and not self.pending.done():return
  width=max(200,self.canvas.winfo_width());height=max(100,self.canvas.winfo_height());zoom,start,span=self.zoom,self.start,self.span
  def work():
   if self.kind=='image':
    with Image.open(self.path) as im:
     original=im.size;size=tuple(max(1,round(x*zoom)) for x in original)
     if size[0]*size[1]>32_000_000:raise ValueError('Displayed raster exceeds 32 million pixels; zoom out')
     return ('image',im.convert('RGB').resize(size),original,zoom)
   probe=self.run_process(['ffprobe','-v','error','-show_streams','-show_format','-of','json',*self.input_options,str(self.path)],text=True,timeout=20)
   info=json.loads(probe.stdout);stream=next(s for s in info['streams'] if s['codec_type']=='audio' and (self.stream_index=='' or s['index']==int(self.stream_index)));rate=int(stream['sample_rate']);channels=int(stream['channels'])
   if span*rate*4>128*1024*1024:raise ValueError('Interval exceeds waveform memory budget; zoom in')
   # One channel is shown explicitly. No averaging/resampling/calibration.
   raw=self.run_process(['ffmpeg','-v','error','-ss',str(start),*self.input_options,'-i',str(self.path),'-map',f"0:{stream['index']}",'-t',str(span),'-af','pan=mono|c0=c0','-f','f32le','-'],timeout=30).stdout
   if len(raw)>128*1024*1024:raise ValueError('Interval exceeds waveform memory budget; zoom in')
   samples=array.array('f');samples.frombytes(raw)
   if sys.byteorder!='little':samples.byteswap()
   if not samples:raise ValueError('No samples in this interval; return to an earlier interval')
   bucket=max(1,math.ceil(len(samples)/max(1,width-100)));peaks=[]
   for i in range(0,len(samples),bucket):
    finite=[v for v in samples[i:i+bucket] if math.isfinite(v)]
    if finite:peaks.append((i/rate,min(finite),max(finite)))
   return ('audio',peaks,start,len(samples)/rate,rate,channels)
  self.status.set('Reading canonical source…');self.pending=self.pool.submit(work);self.root.after(30,self.ready)
 def ready(self):
  if self.closed:return
  if not self.pending.done():self.root.after(30,self.ready);return
  try:
   result=self.pending.result();self.canvas.delete('all')
   if result[0]=='image':
    _,im,size,zoom=result;self.image=ImageTk.PhotoImage(im);self.canvas.create_image(0,0,image=self.image,anchor='nw');self.canvas.configure(scrollregion=(0,0,im.width,im.height))
    self.status.set(f'{size[0]} × {size[1]} source pixels · {zoom*100:.1f}% · Drag to Pan · display resize only')
   else:
    _,peaks,start,duration,rate,channels=result;w=self.canvas.winfo_width()-100;h=self.canvas.winfo_height()-80;mid=20+h/2
    amplitude=max(1e-12,max(max(abs(lo),abs(hi)) for _,lo,hi in peaks))
    self.canvas.create_line(70,mid,70+w,mid,fill='#777777')
    for t,lo,hi in peaks:
     x=70+t/duration*w;self.canvas.create_line(x,mid-hi/amplitude*h/2,x,mid-lo/amplitude*h/2,fill='#145c9a')
    for i in range(6):self.canvas.create_text(70+w*i/5,mid+h/2+25,text=f'{start+duration*i/5:.4g} s')
    self.canvas.create_text(65,20,text=f'{amplitude:.4g}',anchor='e');self.canvas.create_text(65,20+h,text=f'{-amplitude:.4g}',anchor='e')
    self.status.set(f'Channel 1 of {channels} · {rate} Hz · {start:.4g}–{start+duration:.4g} s · decoded normalized PCM amplitude, no physical calibration · min/max envelope, no resampling')
  except Exception as e:self.status.set(str(e))
 def run(self):self.root.mainloop()
if __name__=='__main__':Reader(*sys.argv[1:]).run()
