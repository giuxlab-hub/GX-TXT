# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import math
import tkinter as tk
from typing import Callable
from PIL import Image, ImageTk


class ImageCanvas(tk.Canvas):
    def __init__(self, master, *, on_cursor=None, on_left_press=None,
                 on_left_drag=None, on_left_release=None, on_right_click=None,
                 on_view_changed=None, **kwargs):
        super().__init__(master, highlightthickness=0, background="#303030", **kwargs)
        self.original_image: Image.Image | None = None
        self._display_image: Image.Image | None = None
        self._background_hex = "#303030"
        self._opacity = 100
        self.tk_image = None
        self.image_item = None
        self.scale = 1.0
        self.offset_x = 0.0
        self.offset_y = 0.0
        self.min_scale = 0.01
        self.max_scale = 50.0
        self._render_pending = False
        # A comparison canvas may be loaded while its panes have provisional
        # Tk dimensions. Defer the first fit until real viewport geometry exists.
        self._pending_initial_fit = False
        self._pan_last_x = self._pan_last_y = 0
        self.on_cursor = on_cursor
        self.on_left_press = on_left_press
        self.on_left_drag = on_left_drag
        self.on_left_release = on_left_release
        self.on_right_click = on_right_click
        self._right_pan_active = False
        self.on_view_changed = on_view_changed
        self.bind("<Configure>", self._on_configure)
        self.bind("<Motion>", self._on_motion)
        self.bind("<ButtonPress-1>", self._on_left_press)
        self.bind("<B1-Motion>", self._on_left_drag)
        self.bind("<ButtonRelease-1>", self._on_left_release)
        self.bind("<ButtonPress-2>", self._pan_start); self.bind("<B2-Motion>", self._pan_move)
        self.bind("<ButtonPress-3>", self._on_right_press)
        self.bind("<B3-Motion>", self._on_right_move)
        self.bind("<ButtonRelease-3>", lambda _e: setattr(self,"_right_pan_active",False))
        self.bind("<MouseWheel>", self._on_mousewheel)
        self.bind("<Button-4>", lambda e: self.zoom_at(e.x, e.y, 1.15))
        self.bind("<Button-5>", lambda e: self.zoom_at(e.x, e.y, 1/1.15))

    def set_image(self, image: Image.Image | None) -> None:
        # A Session switch clears all canvas objects. The previous Tk item ID
        # must NEVER be reused after delete('all'), or the new raster remains
        # invisible even though its pixels are successfully decoded.
        if image is None:
            self.delete("base_image")
            self.image_item = None
            self.tk_image = None
        self.original_image = image
        self._update_display_image()
        self.scale, self.offset_x, self.offset_y = 1.0, 0.0, 0.0
        self._pending_initial_fit = True
        self.request_render()
        # Try after normal geometry settlement. A later Configure event makes
        # the first fit reliable even if this callback sees a 1x1 canvas.
        self.after_idle(self._try_initial_fit)

    def set_appearance(self, background: str, opacity: int):
        """Change display rendering only; scientific source pixels stay immutable."""
        import re
        if not re.fullmatch(r"#[0-9a-fA-F]{6}",str(background)):
            raise ValueError("Canvas color requires #RRGGBB")
        opacity=max(0,min(100,int(opacity)))
        if (background.lower(),opacity)==(self._background_hex.lower(),self._opacity):
            return
        self._background_hex=background
        self._opacity=opacity
        self.configure(background=background)
        self._update_display_image()
        self.request_render()

    def _update_display_image(self):
        if self.original_image is None:
            self._display_image=None
        elif self._opacity==100:
            self._display_image=self.original_image
        else:
            bg=Image.new("RGB",self.original_image.size,self._background_hex)
            img=self.original_image.convert("RGBA")
            if self._opacity==0:self._display_image=bg
            else:
                if img.getextrema()[3][0]!=255:
                    mask=img.getchannel("A").point(lambda a:round(a*self._opacity/100))
                else:mask=Image.new("L",img.size,round(255*self._opacity/100))
                bg.paste(img.convert("RGB"),(0,0),mask)
                self._display_image=bg

    def _try_initial_fit(self):
        if not self._pending_initial_fit or self.original_image is None:
            return False
        # Tk's initial requested size can be 1x1 while the paned window is
        # arranging children. Fitting that rectangle formerly locked the image
        # into min_scale, leaving it tiny or far from the visible viewport.
        if self.winfo_width() < 32 or self.winfo_height() < 32:
            return False
        self.fit_to_window()
        return True

    def image_to_canvas(self, x, y):
        return self.offset_x + x*self.scale, self.offset_y + y*self.scale

    def canvas_to_image(self, x, y):
        return (x-self.offset_x)/self.scale, (y-self.offset_y)/self.scale

    def inside_image(self, x, y):
        if self.original_image is None: return False
        w, h = self.original_image.size
        return 0 <= x < w and 0 <= y < h

    def fit_to_window(self):
        if self.original_image is None: return
        cw, ch = self.winfo_width(), self.winfo_height()
        if cw < 32 or ch < 32:
            self._pending_initial_fit = True
            return
        self._pending_initial_fit = False
        iw, ih = self.original_image.size
        self.scale = max(self.min_scale, min(self.max_scale, min(cw/iw, ch/ih)))
        self.offset_x = (cw-iw*self.scale)/2
        self.offset_y = (ch-ih*self.scale)/2
        self.request_render(); self._notify_view_changed()

    def copy_view_from(self, other):
        """Match raster scale/center with another independently sized viewport."""
        if self.original_image is None or other.original_image is None: return
        source_center=other.canvas_to_image(max(1,other.winfo_width())/2,
                                            max(1,other.winfo_height())/2)
        self.scale=max(self.min_scale,min(self.max_scale,other.scale))
        self.offset_x=max(1,self.winfo_width())/2-source_center[0]*self.scale
        self.offset_y=max(1,self.winfo_height())/2-source_center[1]*self.scale
        self.request_render();self._notify_view_changed()

    def zoom_at(self, cx, cy, factor):
        if self.original_image is None: return
        ix, iy = self.canvas_to_image(cx, cy)
        ns = max(self.min_scale, min(self.max_scale, self.scale*factor))
        if math.isclose(ns, self.scale, abs_tol=1e-15): return
        self.scale = ns
        self.offset_x = cx - ix*self.scale
        self.offset_y = cy - iy*self.scale
        self.request_render(); self._notify_view_changed()

    def request_render(self):
        if self._render_pending: return
        self._render_pending = True
        self.after_idle(self._render)

    def _render(self):
        self._render_pending = False
        if self.original_image is None:
            if self.image_item is not None:
                self.delete(self.image_item)
                self.image_item = None
            self.tk_image = None
            return
        if self.image_item is not None and not self.find_withtag(self.image_item):
            # Defensive recovery from an external clear, including legacy code
            # that calls Canvas.delete('all') instead of set_image(None).
            self.image_item = None
        cw, ch = max(1, self.winfo_width()), max(1, self.winfo_height())
        iw, ih = self.original_image.size
        x0 = max(0, int(math.floor(-self.offset_x/self.scale)))
        y0 = max(0, int(math.floor(-self.offset_y/self.scale)))
        x1 = min(iw, int(math.ceil((cw-self.offset_x)/self.scale)))
        y1 = min(ih, int(math.ceil((ch-self.offset_y)/self.scale)))
        if x1 <= x0 or y1 <= y0:
            if self.image_item is not None: self.itemconfigure(self.image_item, state="hidden")
            return
        crop = (self._display_image or self.original_image).crop((x0, y0, x1, y1))
        dw = max(1, int(round((x1-x0)*self.scale)))
        dh = max(1, int(round((y1-y0)*self.scale)))
        if (dw, dh) != crop.size:
            filt = Image.Resampling.LANCZOS if self.scale < 1 else Image.Resampling.BILINEAR
            crop = crop.resize((dw, dh), filt)
        self.tk_image = ImageTk.PhotoImage(crop)
        cx, cy = self.offset_x + x0*self.scale, self.offset_y + y0*self.scale
        if self.image_item is None:
            self.image_item = self.create_image(cx, cy, anchor="nw", image=self.tk_image, tags=("base_image",))
        else:
            self.coords(self.image_item, cx, cy)
            self.itemconfigure(self.image_item, image=self.tk_image, state="normal")
        self.tag_lower("base_image")

    def _on_configure(self, _e):
        if self._pending_initial_fit and self._try_initial_fit():
            return
        self.request_render()
        # Ordinary resizes preserve a user's independent pan and zoom.
        self._notify_view_changed()
    def _on_motion(self, e):
        if not self.on_cursor: return
        x, y = self.canvas_to_image(e.x, e.y)
        self.on_cursor(x, y) if self.inside_image(x, y) else self.on_cursor(None, None)
    def _on_left_press(self, e):
        if not self.on_left_press: return
        x, y = self.canvas_to_image(e.x, e.y)
        if self.inside_image(x, y): self.on_left_press(x, y)
    def _bounded(self, x, y):
        w, h = self.original_image.size
        return min(max(x, 0), w-1), min(max(y, 0), h-1)
    def _on_left_drag(self, e):
        if self.on_left_drag and self.original_image:
            self.on_left_drag(*self._bounded(*self.canvas_to_image(e.x, e.y)))
    def _on_left_release(self, e):
        if self.on_left_release and self.original_image:
            self.on_left_release(*self._bounded(*self.canvas_to_image(e.x, e.y)))
    def _on_right_press(self,e):
        x,y=self.canvas_to_image(e.x,e.y)
        handled=(self.on_right_click(x,y,e.x_root,e.y_root) if self.on_right_click and
                 self.inside_image(x,y) else False)
        self._right_pan_active=not handled
        if self._right_pan_active:self._pan_start(e)

    def _on_right_move(self,e):
        if self._right_pan_active:self._pan_move(e)

    def _pan_start(self, e): self._pan_last_x, self._pan_last_y = e.x, e.y
    def _pan_move(self, e):
        self.offset_x += e.x-self._pan_last_x; self.offset_y += e.y-self._pan_last_y
        self._pan_last_x, self._pan_last_y = e.x, e.y
        self.request_render(); self._notify_view_changed()
    def _on_mousewheel(self, e):
        if e.delta: self.zoom_at(e.x, e.y, 1.15 if e.delta > 0 else 1/1.15)
    def _notify_view_changed(self):
        if self.on_view_changed: self.on_view_changed()
