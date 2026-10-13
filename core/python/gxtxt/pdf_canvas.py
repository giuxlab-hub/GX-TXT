# SPDX-License-Identifier: GPL-3.0-or-later
"""Shared GX-TXT PDF canvas and Poppler renderer, independent of OCR."""
from __future__ import annotations
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk
from .pdf_model import Rect, hit_test, handle_points
import subprocess
from pathlib import Path
RESAMPLE_LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def render_page(path, page, dpi, base):
    subprocess.run(["pdftoppm", "-f", str(page), "-l", str(page), "-singlefile", "-png", "-r", str(dpi), str(path), str(base)], check=True, capture_output=True, timeout=180)
    result = Path(str(base)+".png")
    if not result.is_file(): raise RuntimeError("Poppler produced no readable page")
    return result

class PdfCanvas(ttk.Frame):
    HANDLE_SCREEN_RADIUS = 6

    def __init__(self, master, on_selection_changed):
        super().__init__(master)
        self.on_selection_changed = on_selection_changed
        self.canvas = tk.Canvas(self, background="#303030", cursor="crosshair", highlightthickness=0)
        self.xbar = ttk.Scrollbar(self, orient="horizontal", command=self.canvas.xview)
        self.ybar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(xscrollcommand=self.xbar.set, yscrollcommand=self.ybar.set)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        self.ybar.grid(row=0, column=1, sticky="ns")
        self.xbar.grid(row=1, column=0, sticky="ew")
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)

        self.source_image: Image.Image | None = None
        self.photo = None
        self.scale = 0.5
        self.selection: Rect | None = None
        self.action = "new"
        self.handle = ""
        self.drag_start: tuple[int, int] | None = None
        self.drag_original: Rect | None = None

        self.canvas.bind("<ButtonPress-1>", self._mouse_down)
        self.canvas.bind("<B1-Motion>", self._mouse_drag)
        self.canvas.bind("<ButtonRelease-1>", self._mouse_up)
        self.canvas.bind("<Motion>", self._motion)
        self.canvas.bind("<ButtonPress-2>", lambda e: self.canvas.scan_mark(e.x, e.y))
        self.canvas.bind("<B2-Motion>", lambda e: self.canvas.scan_dragto(e.x, e.y, gain=1))
        self.canvas.bind("<MouseWheel>", self._wheel_windows)
        self.canvas.bind("<Button-4>", lambda e: self._wheel(1, e.x, e.y))
        self.canvas.bind("<Button-5>", lambda e: self._wheel(-1, e.x, e.y))
        self.canvas.bind("<Left>", lambda _e: self.canvas.xview_scroll(-2, "units"))
        self.canvas.bind("<Right>", lambda _e: self.canvas.xview_scroll(2, "units"))
        self.canvas.bind("<Up>", lambda _e: self.canvas.yview_scroll(-2, "units"))
        self.canvas.bind("<Down>", lambda _e: self.canvas.yview_scroll(2, "units"))
        self.canvas.configure(takefocus=True)
        self.zoom_callback = None

    def _wheel_windows(self, event):
        self._wheel(1 if event.delta > 0 else -1, event.x, event.y)

    def _wheel(self, direction: int, x: int, y: int):
        if self.zoom_callback:
            self.zoom_callback(direction, x, y)

    def set_image(self, image: Image.Image, zoom_percent: int, selection: Rect | None = None):
        self.source_image = image
        self.selection = selection.clamp(*image.size) if selection else None
        self.set_zoom(zoom_percent, keep_source_anchor=None)

    def set_zoom(self, zoom_percent: int, keep_source_anchor: tuple[float, float, int, int] | None = None):
        if self.source_image is None:
            return
        self.scale = max(0.01, zoom_percent / 100.0)
        w = max(1, round(self.source_image.width * self.scale))
        h = max(1, round(self.source_image.height * self.scale))
        display = self.source_image if (w, h) == self.source_image.size else self.source_image.resize((w, h), RESAMPLE_LANCZOS)
        self.photo = ImageTk.PhotoImage(display)
        self.canvas.delete("page")
        self.canvas.create_image(0, 0, anchor="nw", image=self.photo, tags="page")
        self.canvas.configure(scrollregion=(0, 0, w, h))
        self._redraw_selection()
        if keep_source_anchor:
            sx, sy, px, py = keep_source_anchor
            self.canvas.update_idletasks()
            if w > 0:
                self.canvas.xview_moveto(max(0.0, min(1.0, (sx * self.scale - px) / w)))
            if h > 0:
                self.canvas.yview_moveto(max(0.0, min(1.0, (sy * self.scale - py) / h)))

    def zoom_anchor(self, x: int, y: int) -> tuple[float, float, int, int]:
        cx = self.canvas.canvasx(x)
        cy = self.canvas.canvasy(y)
        return (cx / self.scale, cy / self.scale, x, y)

    def source_coords(self, event) -> tuple[int, int]:
        if self.source_image is None:
            return (0, 0)
        sx = round(self.canvas.canvasx(event.x) / self.scale)
        sy = round(self.canvas.canvasy(event.y) / self.scale)
        return (max(0, min(self.source_image.width, sx)), max(0, min(self.source_image.height, sy)))

    def clear_selection(self):
        self.selection = None
        self._redraw_selection()
        self.on_selection_changed(None)

    def _hit(self, event) -> tuple[str, str]:
        if self.source_image is None:
            return ("new", "")
        sx, sy = self.source_coords(event)
        return hit_test(self.selection, sx, sy, self.HANDLE_SCREEN_RADIUS / self.scale)

    def _motion(self, event):
        action, handle = self._hit(event)
        cursors = {
            "nw": "top_left_corner", "se": "bottom_right_corner", "ne": "top_right_corner", "sw": "bottom_left_corner",
            "n": "top_side", "s": "bottom_side", "e": "right_side", "w": "left_side",
        }
        if action == "move":
            cursor = "fleur"
        elif action == "resize":
            cursor = cursors.get(handle, "crosshair")
        else:
            cursor = "crosshair"
        try:
            self.canvas.configure(cursor=cursor)
        except tk.TclError:
            self.canvas.configure(cursor="crosshair")

    def _mouse_down(self, event):
        if self.source_image is None:
            return
        self.canvas.focus_set()
        sx, sy = self.source_coords(event)
        self.action, self.handle = self._hit(event)
        self.drag_start = (sx, sy)
        self.drag_original = self.selection
        if self.action == "new":
            self.selection = Rect(sx, sy, sx, sy)
        self._redraw_selection()

    def _mouse_drag(self, event):
        if self.source_image is None or self.drag_start is None:
            return
        sx, sy = self.source_coords(event)
        dsx, dsy = self.drag_start
        if self.action == "new":
            self.selection = Rect(dsx, dsy, sx, sy).clamp(*self.source_image.size)
        elif self.action == "move" and self.drag_original:
            self.selection = self.drag_original.moved(sx - dsx, sy - dsy, *self.source_image.size)
        elif self.action == "resize" and self.drag_original:
            self.selection = self.drag_original.resized(self.handle, sx, sy, *self.source_image.size)
        self._redraw_selection()
        self.on_selection_changed(self.selection)

    def _mouse_up(self, _event):
        if self.selection and (self.selection.width < 2 or self.selection.height < 2):
            self.selection = self.drag_original if self.action != "new" else None
        self.action = "new"
        self.handle = ""
        self.drag_start = None
        self.drag_original = None
        self._redraw_selection()
        self.on_selection_changed(self.selection)

    def _redraw_selection(self):
        self.canvas.delete("selection_overlay")
        if self.selection is None:
            return
        r = self.selection.normalized()
        x1, y1, x2, y2 = [v * self.scale for v in (r.x1, r.y1, r.x2, r.y2)]
        self.canvas.create_rectangle(x1, y1, x2, y2, outline="#ff4040", width=2, dash=(6, 4), tags="selection_overlay")
        for name, (hx, hy) in handle_points(r).items():
            hx *= self.scale
            hy *= self.scale
            rad = self.HANDLE_SCREEN_RADIUS
            self.canvas.create_rectangle(hx-rad, hy-rad, hx+rad, hy+rad, fill="#ffffff", outline="#c00000", tags=("selection_overlay", f"handle_{name}"))
        self.canvas.tag_raise("selection_overlay")

