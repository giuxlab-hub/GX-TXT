#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Normal read-only PDF Dataset consultation using the shared OCR canvas."""
import re
import signal
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

class PdfReader:
    def __init__(self, path, identity):
        self.root = tk.Tk(); self.root.title("GX-TXT PDF Dataset — " + identity)
        self.root.geometry("1050x820")
        self.path = Path(path); self.identity = identity
        self.cache = tempfile.TemporaryDirectory(prefix="gxtxt-pdf-")
        self.rendered = OrderedDict(); self.page_sizes = {}; atexit.register(self.cache.cleanup)
        self.page = 1; self.pages = 0; self.zoom = 100; self.size = (595,842)
        bar = ttk.Frame(self.root); bar.pack(fill="x")
        for label, action in [("Previous", lambda:self.navigate(-1)), ("Next", lambda:self.navigate(1)),
                              ("Zoom −", lambda:self.zoom_by(.8)), ("Zoom +", lambda:self.zoom_by(1.25)),
                              ("Fit page", lambda:self.fit(False)), ("Fit width", lambda:self.fit(True))]:
            ttk.Button(bar,text=label,command=action).pack(side="left")
        self.position = tk.StringVar(); ttk.Label(bar,textvariable=self.position).pack(side="left",padx=10)
        self.canvas = PdfCanvas(self.root, lambda _:None); self.canvas.pack(fill="both",expand=True)
        for binding in ("<ButtonPress-1>","<B1-Motion>","<ButtonRelease-1>","<Motion>"):
            self.canvas.canvas.unbind(binding)
        self.canvas.canvas.configure(cursor="fleur")
        self.canvas.canvas.bind("<ButtonPress-1>",lambda e:self.canvas.canvas.scan_mark(e.x,e.y))
        self.canvas.canvas.bind("<B1-Motion>",lambda e:self.canvas.canvas.scan_dragto(e.x,e.y,gain=1))
        self.canvas.zoom_callback=lambda direction,x,y:self.zoom_by(1.25 if direction>0 else .8)
        self.status=tk.StringVar(value=identity);ttk.Label(self.root,textvariable=self.status,wraplength=1000).pack(fill="x")
        self.root.protocol("WM_DELETE_WINDOW",self.close)
        signal.signal(signal.SIGTERM,lambda *_:self.close())
        try:
            result=subprocess.run(["pdfinfo",str(self.path)],capture_output=True,text=True,timeout=30,check=True).stdout
            self.pages=int(re.search(r"^Pages:\s+(\d+)",result,re.M).group(1))
            self.size=self.page_size(self.page)
            self.root.after(100,lambda:self.fit(False))
        except Exception as error:self.status.set("Unable to read PDF: "+str(error))
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
        self.cache.cleanup();self.root.destroy()
    def navigate(self, delta):
        self.page=max(1,min(self.pages,self.page+delta));self.size=self.page_size(self.page);self.render()
    def zoom_by(self, scale):
        self.zoom=max(10,min(400,self.zoom*scale));self.render()
    def fit(self,width):
        self.size=self.page_size(self.page)
        c=self.canvas.canvas
        ratio=(c.winfo_width()-20)/self.size[0]
        if not width:ratio=min(ratio,(c.winfo_height()-20)/self.size[1])
        self.zoom=max(10,min(400,ratio*100));self.render()
    def render(self):
        if not self.pages:return
        try:
            dpi=max(10,round(72*self.zoom/100));base=Path(self.cache.name)/f"page-{self.page}-{dpi}"
            image=Path(str(base)+".png")
            if not image.exists():render_page(self.path,self.page,dpi,base)
            self.rendered.pop(image, None); self.rendered[image]=image.stat().st_size
            while len(self.rendered)>8 or (sum(self.rendered.values())>64*1024*1024 and len(self.rendered)>1):
                expired, _=self.rendered.popitem(last=False); expired.unlink(missing_ok=True)
            with Image.open(image) as source:self.canvas.set_image(source.convert("RGB"),100)
            if image.stat().st_size > 64*1024*1024:
                self.rendered.pop(image, None); image.unlink(missing_ok=True)
            self.position.set(f"Page {self.page} / {self.pages} · {self.zoom:.0f}%")
            self.status.set(self.identity+" — Drag to Pan; wheel to zoom")
        except Exception as error:self.status.set("PDF rendering failed: "+str(error))
    def run(self):self.root.mainloop()

if __name__=="__main__":PdfReader(sys.argv[1],sys.argv[2]).run()
