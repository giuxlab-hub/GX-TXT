#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Normal read-only PDF Dataset consultation using the shared OCR canvas."""
import re
import signal
import base64
import hashlib
import os
from collections import OrderedDict
import atexit
import sys
import tempfile
import subprocess
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from PIL import Image
from gxtxt.pdf_canvas import PdfCanvas, render_page
from gxtxt_job_supervisor import tcl_result

class PdfReader:
    def __init__(self, path, identity, owner_receipts=False, managed_resource=False, title=None):
        self.root = tk.Tk(); self.root.title("GX-TXT PDF — " + (title or identity) if managed_resource else "GX-TXT PDF Dataset — " + identity)
        self.source_kind = "managed_resource" if managed_resource else "dataset"
        self.root.geometry("1050x820")
        self.path = Path(path); self.identity = identity
        self.cache = tempfile.TemporaryDirectory(prefix="gxtxt-pdf-")
        self.rendered = OrderedDict(); self.page_sizes = {}; atexit.register(self.cache.cleanup)
        self.page = 1; self.pages = 0; self.zoom = 100; self.size = (595,842)
        self.owner_receipts = owner_receipts; self.last_receipt = None
        self.reader_state = "starting"; self.source_sha256 = ""
        self.rendered_sha256 = ""; self.rendered_pixels = []; self.closing = False
        self.controls = {}
        bar = ttk.Frame(self.root); bar.pack(fill="x")
        for name, label, action in [("previous", "Previous", lambda:self.navigate(-1)), ("next", "Next", lambda:self.navigate(1)),
                              ("zoom_out", "Zoom −", lambda:self.zoom_by(.8)), ("zoom_in", "Zoom +", lambda:self.zoom_by(1.25)),
                              ("fit_page", "Fit page", lambda:self.fit(False)), ("fit_width", "Fit width", lambda:self.fit(True))]:
            button = ttk.Button(bar,text=label,command=action);button.pack(side="left")
            self.controls[name] = button
        self.position = tk.StringVar(); ttk.Label(bar,textvariable=self.position).pack(side="left",padx=10)
        self.canvas = PdfCanvas(self.root, lambda _:None); self.canvas.pack(fill="both",expand=True)
        for binding in ("<ButtonPress-1>","<B1-Motion>","<ButtonRelease-1>","<Motion>"):
            self.canvas.canvas.unbind(binding)
        self.canvas.canvas.configure(cursor="fleur")
        self.canvas.canvas.bind("<ButtonPress-1>",self.pan_start)
        self.canvas.canvas.bind("<B1-Motion>",lambda e:self.canvas.canvas.scan_dragto(e.x,e.y,gain=1))
        self.canvas.zoom_callback=lambda direction,x,y:self.zoom_by(1.25 if direction>0 else .8)
        self.status=tk.StringVar(value=identity);ttk.Label(self.root,textvariable=self.status,wraplength=1000).pack(fill="x")
        self.root.protocol("WM_DELETE_WINDOW",self.close)
        signal.signal(signal.SIGTERM,lambda *_:self.close())
        try:
            with self.path.open("rb") as source:self.source_sha256=hashlib.file_digest(source,"sha256").hexdigest()
            result=subprocess.run(["pdfinfo",str(self.path)],capture_output=True,text=True,timeout=30,check=True).stdout
            self.pages=int(re.search(r"^Pages:\s+(\d+)",result,re.M).group(1))
            self.size=self.page_size(self.page)
            self.root.after(100,lambda:self.fit(False))
        except Exception as error:
            self.reader_state="unavailable";self.status.set("Unable to read PDF: "+str(error))
        self.update_controls()
        if self.owner_receipts:self.root.after(50,self.observe)
    def pan_start(self,event):
        self.canvas.canvas.focus_set();self.canvas.canvas.scan_mark(event.x,event.y)
    def update_controls(self):
        for name,button in self.controls.items():
            disabled=not self.pages or (name=="previous" and self.page<=1) or (name=="next" and self.page>=self.pages)
            button.state(["disabled" if disabled else "!disabled"])
    def native_widget(self,widget):
        return dict(native_id=widget.winfo_id(),mapped=widget.winfo_ismapped(),
                    rectangle=[widget.winfo_rootx(),widget.winfo_rooty(),widget.winfo_width(),widget.winfo_height()])
    def snapshot(self):
        return dict(schema="gxtxt.pdf_reader_receipt.v1",pid=os.getpid(),dataset_id=self.identity,source_kind=self.source_kind,
                    source_sha256=self.source_sha256,state=self.reader_state,page=self.page,pages=self.pages,
                    zoom_percent=self.zoom,page_size_points=list(self.size),rendered_sha256=self.rendered_sha256,
                    rendered_pixels=self.rendered_pixels,window_id=self.root.winfo_id(),frame_id=self.root.wm_frame(),
                    geometry=self.root.winfo_geometry(),mapped=self.root.winfo_ismapped(),status=self.status.get()[:4096],
                    canvas=dict(self.native_widget(self.canvas.canvas),xview=list(self.canvas.canvas.xview()),yview=list(self.canvas.canvas.yview())),
                    controls={name:dict(self.native_widget(button),enabled=not button.instate(["disabled"])) for name,button in self.controls.items()})
    def emit(self):
        if not self.owner_receipts:return
        receipt=self.snapshot()
        if receipt!=self.last_receipt:
            line=base64.b64encode(tcl_result(receipt).encode("utf-8")).decode("ascii")
            try:print("GXPDF1 "+line,flush=True)
            except BrokenPipeError:
                self.owner_receipts=False
                # The owning Tcl reader can close its pipe before SIGTERM is
                # delivered. Retire this receipt transport, including Python's
                # final buffered flush, when that owner has gone away.
                with open(os.devnull,"wb") as sink:
                    os.dup2(sink.fileno(),sys.stdout.fileno())
            self.last_receipt=receipt
    def observe(self):
        if self.closing:return
        self.emit();self.root.after(200,self.observe)
    def page_size(self, page):
        if page not in self.page_sizes:
            info=subprocess.run(["pdfinfo", "-f", str(page), "-l", str(page), str(self.path)],
                                capture_output=True, text=True, timeout=30, check=True).stdout
            match=re.search(r"Page\s+(?:\d+\s+)?size:\s+([\d.]+) x ([\d.]+)", info)
            if not match: raise ValueError("Active page dimensions unavailable")
            size=tuple(map(float, match.groups()))
            rotation=re.search(r"Page\s+(?:\d+\s+)?rot:\s+(-?\d+)", info)
            if rotation and int(rotation.group(1)) % 180: size=size[::-1]
            self.page_sizes[page]=size
        return self.page_sizes[page]
    def close(self):
        if self.closing:return
        self.closing=True;self.reader_state="closed";self.emit()
        self.cache.cleanup();self.root.destroy()
    def navigate(self, delta):
        if not self.pages:return
        self.page=max(1,min(self.pages,self.page+delta));self.size=self.page_size(self.page);self.render()
    def zoom_by(self, scale):
        if not self.pages:return
        self.zoom=max(10,min(400,self.zoom*scale));self.render()
    def fit(self,width):
        if not self.pages:return
        self.size=self.page_size(self.page)
        c=self.canvas.canvas
        ratio=(c.winfo_width()-20)/self.size[0]
        if not width:ratio=min(ratio,(c.winfo_height()-20)/self.size[1])
        self.zoom=max(10,min(400,ratio*100));self.render()
    def render(self):
        if not self.pages:return
        self.reader_state="rendering";self.emit()
        try:
            dpi=max(10,round(72*self.zoom/100));base=Path(self.cache.name)/f"page-{self.page}-{dpi}"
            image=Path(str(base)+".png")
            if not image.exists():render_page(self.path,self.page,dpi,base)
            self.rendered.pop(image, None); self.rendered[image]=image.stat().st_size
            while len(self.rendered)>8 or (sum(self.rendered.values())>64*1024*1024 and len(self.rendered)>1):
                expired, _=self.rendered.popitem(last=False); expired.unlink(missing_ok=True)
            with Image.open(image) as source:
                self.rendered_pixels=list(source.size);self.canvas.set_image(source.convert("RGB"),100)
            with image.open("rb") as rendered:self.rendered_sha256=hashlib.file_digest(rendered,"sha256").hexdigest()
            if image.stat().st_size > 64*1024*1024:
                self.rendered.pop(image, None); image.unlink(missing_ok=True)
            self.position.set(f"Page {self.page} / {self.pages} · {self.zoom:.0f}%")
            self.status.set(self.identity+" — Drag to Pan; wheel to zoom")
            self.reader_state="ready"
        except Exception as error:
            self.reader_state="unavailable";self.status.set("PDF rendering failed: "+str(error))
            self.canvas.canvas.delete("page");self.canvas.photo=None
            self.rendered_sha256="";self.rendered_pixels=[]
        self.update_controls();self.emit()
    def run(self):self.root.mainloop()

if __name__=="__main__":
    title = sys.argv[sys.argv.index("--title") + 1] if "--title" in sys.argv[3:] else None
    PdfReader(sys.argv[1],sys.argv[2],"--owner-receipts" in sys.argv[3:],"--managed-resource" in sys.argv[3:],title).run()
