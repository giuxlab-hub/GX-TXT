# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

from PIL import Image, ImageTk, UnidentifiedImageError

from table_extractor_model import (
    HANDLES,
    Rect,
    Word,
    build_columns,
    filter_words,
    handle_points,
    hit_test,
    normalize_numeric_text,
    parse_pdftotext_tsv,
    parse_tesseract_tsv,
    reconstruct_table,
)

APP_NAME = "GX-TXT Table Extractor"
WORKSPACE_FORMAT = "gxtxt.table_extractor.workspace"
WORKSPACE_VERSION = "1.0"
PLUGIN_VERSION = "1.0.0"
DPI_LEVELS = (150, 200, 300, 400, 600)
ZOOM_LEVELS = (25, 33, 50, 67, 75, 100, 125, 150, 200, 250, 300, 400)
PSM_CHOICES = {
    "Auto": "3",
    "Block": "6",
    "Sparse text": "11",
}
MODE_CHOICES = ("Auto", "Native PDF text", "OCR")
RESAMPLE_LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def b64e(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def b64d(value: str) -> str:
    return base64.b64decode(value.encode("ascii")).decode("utf-8")


def parse_records(payload: str) -> list[tuple[str, list[str]]]:
    out: list[tuple[str, list[str]]] = []
    for line in payload.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        out.append((fields[0], [b64d(x) for x in fields[1:]]))
    return out


def command_text(args: list[str], timeout: int | None = None) -> str:
    proc = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"Command failed with exit code {proc.returncode}: {args[0]}")
    return proc.stdout


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_dataset_id(value: str, fallback: str = "table.extracted") -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", ".", value.strip()).strip(".-_")
    if not value or not value[0].isalpha():
        value = fallback
    return value[:120]


def parse_pdfinfo(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        out[key.strip().lower()] = value.strip()
    return out


def shift_words(words: list[Word], dx: float, dy: float) -> list[Word]:
    return [Word(w.x + dx, w.y + dy, w.w, w.h, w.text, w.confidence) for w in words]


class RpcError(RuntimeError):
    pass


class RpcClient:
    def __init__(self):
        self.counter = 0
        self.focus_callback = None

    def call(self, command: str, *args: str) -> str:
        self.counter += 1
        request_id = str(self.counter)
        sys.stdout.write("\t".join(["REQ", request_id, command] + [b64e(str(a)) for a in args]) + "\n")
        sys.stdout.flush()
        while True:
            response = sys.stdin.readline()
            if response == "":
                raise RpcError("The GX-TXT host connection closed.")
            response = response.rstrip("\n")
            if response == "CONTROL\tFOCUS":
                if self.focus_callback:
                    self.focus_callback()
                continue
            fields = response.split("\t")
            if len(fields) != 4 or fields[0] != "RES" or fields[1] != request_id:
                continue
            payload = b64d(fields[3])
            if fields[2] == "ERR":
                raise RpcError(payload)
            return payload


class SourceCanvas(ttk.Frame):
    HANDLE_SCREEN_RADIUS = 6

    def __init__(self, master, selection_callback):
        super().__init__(master)
        self.selection_callback = selection_callback
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
        self.zoom_callback = None

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

    def _wheel_windows(self, event):
        self._wheel(1 if event.delta > 0 else -1, event.x, event.y)

    def _wheel(self, direction: int, x: int, y: int):
        if self.zoom_callback:
            self.zoom_callback(direction, x, y)

    def set_image(self, image: Image.Image, zoom_percent: int, selection: Rect | None = None):
        self.source_image = image
        self.selection = selection.clamp(*image.size) if selection else None
        self.set_zoom(zoom_percent)

    def set_zoom(self, zoom_percent: int, keep_source_anchor: tuple[float, float, int, int] | None = None):
        if self.source_image is None:
            return
        self.scale = max(0.01, zoom_percent / 100.0)
        width = max(1, round(self.source_image.width * self.scale))
        height = max(1, round(self.source_image.height * self.scale))
        display = self.source_image if (width, height) == self.source_image.size else self.source_image.resize((width, height), RESAMPLE_LANCZOS)
        self.photo = ImageTk.PhotoImage(display)
        self.canvas.delete("page")
        self.canvas.create_image(0, 0, anchor="nw", image=self.photo, tags="page")
        self.canvas.configure(scrollregion=(0, 0, width, height))
        self._redraw_selection()
        if keep_source_anchor:
            sx, sy, px, py = keep_source_anchor
            self.canvas.update_idletasks()
            if width > 0:
                self.canvas.xview_moveto(max(0.0, min(1.0, (sx * self.scale - px) / width)))
            if height > 0:
                self.canvas.yview_moveto(max(0.0, min(1.0, (sy * self.scale - py) / height)))

    def zoom_anchor(self, x: int, y: int) -> tuple[float, float, int, int]:
        return (self.canvas.canvasx(x) / self.scale, self.canvas.canvasy(y) / self.scale, x, y)

    def source_coords(self, event) -> tuple[int, int]:
        if self.source_image is None:
            return (0, 0)
        sx = round(self.canvas.canvasx(event.x) / self.scale)
        sy = round(self.canvas.canvasy(event.y) / self.scale)
        return (max(0, min(self.source_image.width, sx)), max(0, min(self.source_image.height, sy)))

    def clear_selection(self):
        self.selection = None
        self._redraw_selection()
        self.selection_callback(None)

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
        cursor = "fleur" if action == "move" else cursors.get(handle, "crosshair") if action == "resize" else "crosshair"
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
        self.selection_callback(self.selection)

    def _mouse_up(self, _event):
        if self.selection and (self.selection.width < 2 or self.selection.height < 2):
            self.selection = self.drag_original if self.action != "new" else None
        self.action = "new"
        self.handle = ""
        self.drag_start = None
        self.drag_original = None
        self._redraw_selection()
        self.selection_callback(self.selection)

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
            radius = self.HANDLE_SCREEN_RADIUS
            self.canvas.create_rectangle(hx-radius, hy-radius, hx+radius, hy+radius, fill="#ffffff", outline="#c00000", tags=("selection_overlay", f"handle_{name}"))
        self.canvas.tag_raise("selection_overlay")

    def draw_boundaries(self, boundaries: list[float], roi: Rect | None):
        self.canvas.delete("table_boundary")
        if self.source_image is None:
            return
        top = roi.normalized().y1 if roi else 0
        bottom = roi.normalized().y2 if roi else self.source_image.height
        for x in boundaries:
            self.canvas.create_line(x*self.scale, top*self.scale, x*self.scale, bottom*self.scale, fill="#40d0ff", width=2, dash=(3, 3), tags="table_boundary")
        self.canvas.tag_raise("table_boundary")


class TableExtractorApp:
    def __init__(self, root: tk.Tk, rpc: RpcClient):
        self.root = root
        self.rpc = rpc
        self.rpc.focus_callback = self.focus_window
        self.root.title(APP_NAME)
        self.root.geometry("1520x940")
        self.root.minsize(1100, 720)

        self.tempdir = Path(tempfile.mkdtemp(prefix="gxtxt_table_extractor_"))
        self.session_token = ""
        self.datasets: dict[str, dict] = {}
        self.documents: dict[str, dict] = {}
        self.current_doc_id: str | None = None
        self.current_source_id = ""
        self.source_info: dict = {}
        self.source_path: Path | None = None
        self.pdf_info: dict[str, str] = {}
        self.page_image: Image.Image | None = None
        self.render_cache: dict[tuple[str, int, int], Path] = {}
        self.table_rows: list[list[str]] = []
        self.last_boundaries: list[float] = []
        self.last_method = ""
        self.last_token_count = 0
        self.last_extraction_roi: Rect | None = None
        self.loading_state = False
        self.edit_entry: tk.Entry | None = None

        self.workspace_var = tk.StringVar()
        self.workspace_name = tk.StringVar(value="Table extraction workspace")
        self.source_var = tk.StringVar()
        self.page_var = tk.IntVar(value=1)
        self.page_count_var = tk.StringVar(value="/ 1")
        self.dpi_var = tk.IntVar(value=300)
        self.zoom_var = tk.IntVar(value=50)
        self.mode_var = tk.StringVar(value="Auto")
        self.psm_var = tk.StringVar(value="Block")
        self.expected_columns_var = tk.IntVar(value=0)
        self.first_row_header_var = tk.BooleanVar(value=True)
        self.selection_info = tk.StringVar(value="No ROI: full page/image will be analyzed")
        self.status = tk.StringVar(value="Ready")
        self.output_id = tk.StringVar(value="")
        self.output_name = tk.StringVar(value="Extracted table")
        self.method_info = tk.StringVar(value="No extraction yet")

        self.bootstrap()
        self.languages = self.detect_languages()
        self.build_ui()
        self.refresh_workspace_selector()
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        if self.documents:
            self.open_workspace(next(iter(self.documents)))
        elif self.datasets:
            self.source_var.set(next(iter(self.datasets)))
            self.load_source()

        autoclose = os.environ.get("GX_TABLE_EXTRACTOR_TEST_AUTOCLOSE_MS", "").strip()
        if autoclose.isdigit() and int(autoclose) > 0:
            self.root.after(int(autoclose), self.close)

    def focus_window(self):
        try:
            self.root.deiconify(); self.root.lift(); self.root.focus_force()
        except tk.TclError:
            pass

    def bootstrap(self):
        payload = self.rpc.call("BOOTSTRAP")
        for kind, fields in parse_records(payload):
            if kind == "SESSION":
                self.session_token = fields[0]
            elif kind == "DATASET":
                did, contract, fmt_, media, sha, title = fields
                self.datasets[did] = {"contract": contract, "format": fmt_, "media_type": media, "sha256": sha, "title": title}
            elif kind == "DOCUMENT":
                doc_id, text, _updated = fields
                try:
                    data = json.loads(text)
                except json.JSONDecodeError:
                    continue
                if data.get("format") == WORKSPACE_FORMAT:
                    self.documents[doc_id] = data
        if not self.session_token:
            raise RpcError("GX-TXT did not provide a Session token.")

    def detect_languages(self) -> list[str]:
        try:
            text = command_text(["tesseract", "--list-langs"], timeout=20)
        except Exception:
            return []
        langs = []
        for line in text.splitlines()[1:]:
            line = line.strip()
            if line and not line.startswith("List of available languages"):
                langs.append(line)
        return sorted(set(langs))

    def build_ui(self):
        main = ttk.Frame(self.root, padding=8)
        main.pack(fill="both", expand=True)

        workspace = ttk.Frame(main)
        workspace.pack(fill="x", pady=(0, 6))
        ttk.Label(workspace, text="Workspace:").pack(side="left")
        self.workspace_combo = ttk.Combobox(workspace, state="readonly", width=34, textvariable=self.workspace_var)
        self.workspace_combo.pack(side="left", padx=(5, 4))
        self.workspace_combo.bind("<<ComboboxSelected>>", lambda _e: self.open_workspace_by_label())
        ttk.Button(workspace, text="New", command=self.new_workspace).pack(side="left", padx=2)
        ttk.Button(workspace, text="Save", command=self.save_workspace).pack(side="left", padx=2)
        ttk.Button(workspace, text="Delete", command=self.delete_workspace).pack(side="left", padx=2)
        ttk.Label(workspace, text="Name:").pack(side="left", padx=(14, 4))
        ttk.Entry(workspace, textvariable=self.workspace_name, width=34).pack(side="left")

        source = ttk.Frame(main)
        source.pack(fill="x", pady=(0, 6))
        ttk.Label(source, text="Source Dataset:").pack(side="left")
        self.source_combo = ttk.Combobox(source, state="readonly", width=40, values=list(self.datasets), textvariable=self.source_var)
        self.source_combo.pack(side="left", padx=(5, 4))
        ttk.Button(source, text="Load", command=self.load_source).pack(side="left", padx=2)
        ttk.Button(source, text="◀", width=3, command=self.prev_page).pack(side="left", padx=(14, 2))
        tk.Spinbox(source, from_=1, to=99999, width=6, textvariable=self.page_var, command=self.render_source).pack(side="left")
        ttk.Label(source, textvariable=self.page_count_var, width=8).pack(side="left")
        ttk.Button(source, text="▶", width=3, command=self.next_page).pack(side="left", padx=2)
        ttk.Label(source, text="DPI:").pack(side="left", padx=(12, 3))
        ttk.Combobox(source, state="readonly", width=6, values=DPI_LEVELS, textvariable=self.dpi_var).pack(side="left")
        ttk.Button(source, text="Render", command=self.render_source).pack(side="left", padx=3)
        ttk.Label(source, text="Zoom:").pack(side="left", padx=(12, 3))
        zoom = ttk.Combobox(source, state="readonly", width=6, values=ZOOM_LEVELS, textvariable=self.zoom_var)
        zoom.pack(side="left")
        zoom.bind("<<ComboboxSelected>>", lambda _e: self.apply_zoom())
        ttk.Button(source, text="Clear ROI", command=lambda: self.canvas.clear_selection()).pack(side="left", padx=(12, 2))

        controls = ttk.Frame(main)
        controls.pack(fill="x", pady=(0, 6))
        ttk.Label(controls, text="Method:").pack(side="left")
        ttk.Combobox(controls, state="readonly", width=17, values=MODE_CHOICES, textvariable=self.mode_var).pack(side="left", padx=(4, 8))
        ttk.Label(controls, text="OCR languages:").pack(side="left")
        self.lang_list = tk.Listbox(controls, selectmode="extended", exportselection=False, height=3, width=18)
        self.lang_list.pack(side="left", padx=(4, 8))
        for lang in self.languages:
            self.lang_list.insert("end", lang)
        if "eng" in self.languages:
            self.lang_list.selection_set(self.languages.index("eng"))
        elif self.languages:
            self.lang_list.selection_set(0)
        ttk.Label(controls, text="PSM:").pack(side="left")
        ttk.Combobox(controls, state="readonly", width=12, values=list(PSM_CHOICES), textvariable=self.psm_var).pack(side="left", padx=(4, 8))
        ttk.Label(controls, text="Expected columns (0=auto):").pack(side="left")
        tk.Spinbox(controls, from_=0, to=40, width=4, textvariable=self.expected_columns_var).pack(side="left", padx=(4, 8))
        ttk.Checkbutton(controls, text="First row is header", variable=self.first_row_header_var).pack(side="left", padx=4)
        ttk.Button(controls, text="Extract table", command=self.extract_table).pack(side="left", padx=(12, 4))
        ttk.Label(controls, textvariable=self.method_info).pack(side="left", padx=(10, 0))

        paned = ttk.Panedwindow(main, orient="vertical")
        paned.pack(fill="both", expand=True)
        image_frame = ttk.Frame(paned)
        table_frame = ttk.Frame(paned)
        paned.add(image_frame, weight=4)
        paned.add(table_frame, weight=3)

        self.canvas = SourceCanvas(image_frame, self.selection_changed)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.zoom_callback = self.wheel_zoom

        table_top = ttk.Frame(table_frame)
        table_top.pack(fill="x", pady=(5, 3))
        ttk.Label(table_top, textvariable=self.selection_info).pack(side="left")
        ttk.Label(table_top, text="Double-click a cell to edit before publication.").pack(side="right")

        grid_frame = ttk.Frame(table_frame)
        grid_frame.pack(fill="both", expand=True)
        self.table_tree = ttk.Treeview(grid_frame, show="headings", selectmode="browse")
        table_y = ttk.Scrollbar(grid_frame, orient="vertical", command=self.table_tree.yview)
        table_x = ttk.Scrollbar(grid_frame, orient="horizontal", command=self.table_tree.xview)
        self.table_tree.configure(yscrollcommand=table_y.set, xscrollcommand=table_x.set)
        self.table_tree.grid(row=0, column=0, sticky="nsew")
        table_y.grid(row=0, column=1, sticky="ns")
        table_x.grid(row=1, column=0, sticky="ew")
        grid_frame.rowconfigure(0, weight=1)
        grid_frame.columnconfigure(0, weight=1)
        self.table_tree.bind("<Double-1>", self.begin_cell_edit)

        publish = ttk.Frame(main)
        publish.pack(fill="x", pady=(6, 0))
        ttk.Label(publish, text="Output Dataset ID:").pack(side="left")
        ttk.Entry(publish, width=34, textvariable=self.output_id).pack(side="left", padx=(4, 8))
        ttk.Label(publish, text="Name:").pack(side="left")
        ttk.Entry(publish, width=30, textvariable=self.output_name).pack(side="left", padx=(4, 8))
        ttk.Button(publish, text="Publish table.generic Dataset", command=self.publish_table).pack(side="left", padx=4)
        ttk.Label(publish, textvariable=self.status, anchor="e").pack(side="right", fill="x", expand=True)

    def selected_languages(self) -> list[str]:
        return [self.lang_list.get(i) for i in self.lang_list.curselection()]

    def selected_language_spec(self) -> str:
        langs = self.selected_languages()
        if not langs:
            raise RuntimeError("Select at least one installed Tesseract language for OCR.")
        return "+".join(langs)

    def set_selected_languages(self, languages):
        self.lang_list.selection_clear(0, "end")
        selected = False
        for lang in languages or []:
            if lang in self.languages:
                self.lang_list.selection_set(self.languages.index(lang))
                selected = True
        if not selected:
            if "eng" in self.languages:
                self.lang_list.selection_set(self.languages.index("eng"))
            elif self.languages:
                self.lang_list.selection_set(0)

    def source_is_pdf(self) -> bool:
        contract = str(self.source_info.get("contract", ""))
        media = str(self.source_info.get("media_type", ""))
        fmt = str(self.source_info.get("format", ""))
        return contract == "document.pdf" or media == "application/pdf" or fmt.lower() == "pdf"

    def load_source(self, render=True):
        dataset_id = self.source_var.get().strip()
        if not dataset_id:
            return
        try:
            payload = self.rpc.call("SOURCE", dataset_id)
            info: dict[str, object] = {"metadata": {}}
            for kind, fields in parse_records(payload):
                if kind in {"ID", "PATH", "SHA256", "CONTRACT", "FORMAT", "MEDIA_TYPE"}:
                    info[kind.lower()] = fields[0]
                elif kind == "METADATA":
                    info["metadata"][fields[0]] = fields[1]
            path = Path(str(info["path"]))
            actual_sha = sha256_file(path)
            if str(info.get("sha256", "")).lower() != actual_sha.lower():
                raise RuntimeError(f"Source Dataset integrity check failed for '{dataset_id}'.")
            self.current_source_id = dataset_id
            self.source_info = info
            self.source_path = path
            self.table_rows = []
            self.last_boundaries = []
            self.last_method = ""
            self.last_token_count = 0
            self.refresh_table_preview()
            if self.source_is_pdf():
                self.pdf_info = parse_pdfinfo(command_text(["pdfinfo", str(path)], timeout=30))
                pages = int(self.pdf_info.get("pages", "0") or 0)
                if pages < 1:
                    raise RuntimeError("The PDF contains no renderable pages.")
                self.page_var.set(max(1, min(pages, int(self.page_var.get()))))
                self.page_count_var.set(f"/ {pages}")
            else:
                self.pdf_info = {}
                self.page_var.set(1)
                self.page_count_var.set("/ 1")
            self.update_default_output_id(force=True)
            self.status.set(f"Loaded {dataset_id}")
            if render:
                self.render_source()
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Load failed")

    def page_count(self) -> int:
        if not self.source_is_pdf():
            return 1
        try:
            return int(self.pdf_info.get("pages", "0") or 0)
        except ValueError:
            return 0

    def rendered_pdf_path(self, page: int, dpi: int) -> Path:
        if not self.source_path:
            raise RuntimeError("Load a source Dataset first.")
        key = (self.current_source_id, page, dpi)
        out = self.render_cache.get(key)
        if not out or not out.exists():
            base = self.tempdir / f"page-{abs(hash(self.current_source_id)) & 0xfffffff:x}-{page:04d}-{dpi}dpi"
            command_text(["pdftoppm", "-f", str(page), "-l", str(page), "-singlefile", "-png", "-r", str(dpi), str(self.source_path), str(base)], timeout=180)
            out = Path(str(base) + ".png")
            if not out.is_file():
                raise RuntimeError("Poppler did not create the rendered page image.")
            self.render_cache[key] = out
        return out

    def render_source(self):
        if not self.source_path:
            self.load_source(render=False)
        if not self.source_path:
            return
        try:
            dpi = int(self.dpi_var.get())
            if self.source_is_pdf():
                page = max(1, min(self.page_count(), int(self.page_var.get())))
                self.page_var.set(page)
                self.status.set(f"Rendering PDF page {page} at {dpi} DPI…")
                self.root.update_idletasks()
                path = self.rendered_pdf_path(page, dpi)
            else:
                path = self.source_path
            try:
                with Image.open(path) as image:
                    self.page_image = image.convert("RGB").copy()
            except UnidentifiedImageError as exc:
                raise RuntimeError("The source image payload cannot be decoded by Pillow.") from exc
            self.canvas.set_image(self.page_image, int(self.zoom_var.get()))
            self.selection_changed(None)
            self.canvas.draw_boundaries([], None)
            self.status.set(f"Source ready: {self.page_image.width} × {self.page_image.height} px")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Render failed")

    def update_default_output_id(self, force=False):
        if not self.current_source_id:
            return
        base = safe_dataset_id(self.current_source_id, "source")
        suffix = f".p{int(self.page_var.get()):03d}.table" if self.source_is_pdf() else ".table"
        if force or not self.output_id.get().strip():
            self.output_id.set(base + suffix)

    def apply_zoom(self):
        if self.page_image:
            self.canvas.set_zoom(int(self.zoom_var.get()))
            self.canvas.draw_boundaries(self.last_boundaries, self.last_extraction_roi)

    def wheel_zoom(self, direction: int, x: int, y: int):
        if not self.page_image:
            return
        current = int(self.zoom_var.get())
        try:
            index = ZOOM_LEVELS.index(current)
        except ValueError:
            index = ZOOM_LEVELS.index(50)
        new_index = max(0, min(len(ZOOM_LEVELS) - 1, index + direction))
        if new_index == index:
            return
        anchor = self.canvas.zoom_anchor(x, y)
        self.zoom_var.set(ZOOM_LEVELS[new_index])
        self.canvas.set_zoom(ZOOM_LEVELS[new_index], keep_source_anchor=anchor)
        self.canvas.draw_boundaries(self.last_boundaries, self.last_extraction_roi)

    def selection_changed(self, rect: Rect | None):
        self.canvas.draw_boundaries([], None)
        self.last_boundaries = []
        if not rect:
            self.selection_info.set("No ROI: full page/image will be analyzed")
            return
        r = rect.normalized()
        self.selection_info.set(f"ROI: x={r.x1} y={r.y1}  {r.width} × {r.height} px")

    def extraction_roi(self) -> Rect | None:
        if not self.page_image:
            raise RuntimeError("Render a source first.")
        if not self.canvas.selection:
            return None
        r = self.canvas.selection.clamp(*self.page_image.size)
        if r.width < 2 or r.height < 2:
            raise RuntimeError("The ROI is too small.")
        return r

    def extract_native_pdf_words(self, roi: Rect | None) -> list[Word]:
        if not self.source_path or not self.source_is_pdf():
            return []
        page = int(self.page_var.get())
        dpi = int(self.dpi_var.get())
        tsv = command_text(["pdftotext", "-tsv", "-f", str(page), "-l", str(page), str(self.source_path), "-"], timeout=60)
        return filter_words(parse_pdftotext_tsv(tsv, dpi), roi)

    def ocr_words(self, roi: Rect | None) -> list[Word]:
        if not self.page_image:
            raise RuntimeError("Render a source first.")
        languages = self.selected_language_spec()
        psm = PSM_CHOICES.get(self.psm_var.get(), "6")
        image = self.page_image
        offset_x = 0
        offset_y = 0
        if roi:
            r = roi.normalized()
            image = image.crop((r.x1, r.y1, r.x2, r.y2))
            offset_x, offset_y = r.x1, r.y1
        temp = self.tempdir / f"ocr-table-{time.time_ns()}.png"
        image.save(temp, format="PNG")
        tsv = command_text(["tesseract", str(temp), "stdout", "-l", languages, "--psm", psm, "tsv"], timeout=600)
        words = parse_tesseract_tsv(tsv)
        if offset_x or offset_y:
            words = shift_words(words, offset_x, offset_y)
        return words

    def extract_table(self):
        if not self.source_path or not self.page_image:
            return
        try:
            roi = self.extraction_roi()
            expected = max(0, int(self.expected_columns_var.get()))
            mode = self.mode_var.get()
            method = ""
            words: list[Word] = []
            table: list[list[str]] = []
            boundaries: list[float] = []

            if self.source_is_pdf() and mode in {"Auto", "Native PDF text"}:
                self.status.set("Reading positioned native PDF text…")
                self.root.update_idletasks()
                words = self.extract_native_pdf_words(roi)
                table, boundaries = reconstruct_table(words, expected_columns=expected)
                usable = len(words) >= 2 and len(table) >= 2 and (expected <= 1 or len(boundaries) + 1 >= expected)
                if mode == "Native PDF text" and not usable:
                    raise RuntimeError("The selected PDF region does not contain enough usable native positioned text. Choose OCR or Auto.")
                if usable:
                    method = "pdf_native_text"
                else:
                    words = []
                    table = []
                    boundaries = []

            if not method:
                self.status.set("Running Tesseract OCR and layout extraction…")
                self.root.update_idletasks()
                words = self.ocr_words(roi)
                table, boundaries = reconstruct_table(words, expected_columns=expected)
                method = "tesseract_ocr"

            if len(table) < 2:
                raise RuntimeError("No usable tabular structure was reconstructed. Adjust the ROI, OCR mode, PSM or expected column count.")
            if max(len(row) for row in table) < 2:
                raise RuntimeError("Only one column was detected. Set Expected columns or choose a tighter table ROI.")

            self.table_rows = table
            self.last_boundaries = boundaries
            self.last_method = method
            self.last_token_count = len(words)
            self.last_extraction_roi = roi if roi else Rect(0, 0, self.page_image.width, self.page_image.height)
            self.refresh_table_preview()
            self.canvas.draw_boundaries(boundaries, self.last_extraction_roi)
            self.method_info.set(f"{method}; {len(words)} tokens; {len(table)} rows × {max(len(r) for r in table)} columns")
            self.status.set("Table reconstructed. Review/edit cells before publication.")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Extraction failed")

    def refresh_table_preview(self):
        for item in self.table_tree.get_children():
            self.table_tree.delete(item)
        if not self.table_rows:
            self.table_tree["columns"] = ()
            return
        col_count = max(len(row) for row in self.table_rows)
        columns = [f"c{i+1}" for i in range(col_count)]
        self.table_tree["columns"] = columns
        for i, column in enumerate(columns):
            self.table_tree.heading(column, text=f"Column {i+1}")
            self.table_tree.column(column, width=150, minwidth=70, stretch=True)
        for ri, row in enumerate(self.table_rows):
            values = row + [""] * (col_count - len(row))
            self.table_tree.insert("", "end", iid=f"r{ri}", values=values)

    def begin_cell_edit(self, event):
        if not self.table_rows:
            return
        region = self.table_tree.identify_region(event.x, event.y)
        if region != "cell":
            return
        row_id = self.table_tree.identify_row(event.y)
        column_id = self.table_tree.identify_column(event.x)
        if not row_id or not column_id:
            return
        ri = int(row_id[1:])
        ci = int(column_id[1:]) - 1
        bbox = self.table_tree.bbox(row_id, column_id)
        if not bbox:
            return
        x, y, width, height = bbox
        value = self.table_rows[ri][ci] if ci < len(self.table_rows[ri]) else ""
        if self.edit_entry:
            self.edit_entry.destroy()
        entry = tk.Entry(self.table_tree)
        entry.insert(0, value)
        entry.select_range(0, "end")
        entry.place(x=x, y=y, width=width, height=height)
        entry.focus_set()
        self.edit_entry = entry

        def commit(_event=None):
            while len(self.table_rows[ri]) <= ci:
                self.table_rows[ri].append("")
            self.table_rows[ri][ci] = entry.get()
            entry.destroy()
            self.edit_entry = None
            self.refresh_table_preview()

        entry.bind("<Return>", commit)
        entry.bind("<FocusOut>", commit)
        entry.bind("<Escape>", lambda _e: (entry.destroy(), setattr(self, "edit_entry", None)))

    def serialize_table_for_publication(self) -> tuple[str, int, int]:
        columns, data_rows = build_columns(self.table_rows, bool(self.first_row_header_var.get()))
        if not columns or not data_rows:
            raise RuntimeError("The preview does not contain publishable data rows.")
        lines: list[str] = []
        for col in columns:
            lines.append("\t".join(["COL", b64e(col["id"]), b64e(col["label"]), b64e(col["dtype"])]))
        for row in data_rows:
            values = []
            for i, col in enumerate(columns):
                value = row[i] if i < len(row) else ""
                if col["dtype"] != "string":
                    value = normalize_numeric_text(value)
                values.append(b64e(value))
            lines.append("\t".join(["ROW"] + values))
        return ("\n".join(lines), len(data_rows), len(columns))

    def publish_table(self):
        try:
            if not self.table_rows or not self.last_method or not self.last_extraction_roi:
                raise RuntimeError("Extract a table before publication.")
            payload, row_count, col_count = self.serialize_table_for_publication()
            dataset_id = safe_dataset_id(self.output_id.get(), "table.extracted")
            display_name = self.output_name.get().strip() or "Extracted table"
            languages = self.selected_language_spec() if self.last_method == "tesseract_ocr" else ""
            psm = PSM_CHOICES.get(self.psm_var.get(), "6") if self.last_method == "tesseract_ocr" else ""
            page = str(int(self.page_var.get()) if self.source_is_pdf() else 1)
            roi = self.last_extraction_roi.as_csv()
            result = self.rpc.call(
                "PUBLISH_TABLE",
                self.session_token,
                dataset_id,
                display_name,
                self.current_source_id,
                str(self.source_info.get("sha256", "")),
                self.last_method,
                page,
                roi,
                languages,
                psm,
                str(self.last_token_count),
                "1" if self.first_row_header_var.get() else "0",
                payload,
            )
            self.output_id.set(dataset_id)
            self.status.set(f"Published {row_count} × {col_count} table.generic Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Publication failed")

    def prev_page(self):
        if self.source_is_pdf() and int(self.page_var.get()) > 1:
            self.page_var.set(int(self.page_var.get()) - 1)
            self.canvas.clear_selection()
            self.update_default_output_id(force=True)
            self.render_source()

    def next_page(self):
        if self.source_is_pdf() and int(self.page_var.get()) < self.page_count():
            self.page_var.set(int(self.page_var.get()) + 1)
            self.canvas.clear_selection()
            self.update_default_output_id(force=True)
            self.render_source()

    def workspace_payload(self) -> str:
        roi = None
        if self.canvas.selection:
            r = self.canvas.selection.normalized()
            roi = [r.x1, r.y1, r.x2, r.y2]
        data = {
            "format": WORKSPACE_FORMAT,
            "version": WORKSPACE_VERSION,
            "name": self.workspace_name.get().strip() or "Table extraction workspace",
            "source_dataset_id": self.current_source_id or self.source_var.get().strip(),
            "source_sha256": self.source_info.get("sha256", ""),
            "page": int(self.page_var.get()),
            "dpi": int(self.dpi_var.get()),
            "zoom": int(self.zoom_var.get()),
            "roi": roi,
            "mode": self.mode_var.get(),
            "ocr_languages": self.selected_languages(),
            "psm_label": self.psm_var.get(),
            "expected_columns": int(self.expected_columns_var.get()),
            "first_row_header": bool(self.first_row_header_var.get()),
            "table_rows": self.table_rows,
            "last_method": self.last_method,
            "last_token_count": self.last_token_count,
            "last_boundaries": self.last_boundaries,
            "output_dataset_id": self.output_id.get().strip(),
            "output_name": self.output_name.get().strip(),
        }
        return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)

    def new_workspace(self):
        name = simpledialog.askstring(APP_NAME, "Workspace name:", initialvalue="Table extraction workspace", parent=self.root)
        if not name:
            return
        self.current_doc_id = None
        self.workspace_name.set(name.strip())
        self.table_rows = []
        self.last_method = ""
        self.last_token_count = 0
        self.last_boundaries = []
        self.refresh_table_preview()
        self.status.set("New workspace")

    def save_workspace(self):
        try:
            payload = self.workspace_payload()
            if self.current_doc_id:
                doc_id = self.rpc.call("DOC_UPDATE", self.current_doc_id, payload, self.session_token)
            else:
                doc_id = self.rpc.call("DOC_CREATE", payload)
                self.current_doc_id = doc_id
            self.documents[doc_id] = json.loads(payload)
            self.refresh_workspace_selector()
            self.status.set(f"Workspace saved: {doc_id}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def delete_workspace(self):
        if not self.current_doc_id:
            return
        if not messagebox.askyesno(APP_NAME, "Delete this saved Table Extractor workspace? Published Datasets are not deleted.", parent=self.root):
            return
        try:
            self.rpc.call("DOC_DELETE", self.current_doc_id, self.session_token)
            self.documents.pop(self.current_doc_id, None)
            self.current_doc_id = None
            self.workspace_var.set("")
            self.refresh_workspace_selector()
            self.status.set("Workspace deleted")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def refresh_workspace_selector(self):
        labels = []
        self.workspace_label_to_id = {}
        for doc_id, data in self.documents.items():
            label = data.get("name") or doc_id
            if label in self.workspace_label_to_id:
                label = f"{label} [{doc_id}]"
            self.workspace_label_to_id[label] = doc_id
            labels.append(label)
        self.workspace_combo.configure(values=labels)
        if self.current_doc_id:
            for label, did in self.workspace_label_to_id.items():
                if did == self.current_doc_id:
                    self.workspace_var.set(label)
                    break

    def open_workspace_by_label(self):
        doc_id = self.workspace_label_to_id.get(self.workspace_var.get())
        if doc_id:
            self.open_workspace(doc_id)

    def open_workspace(self, doc_id: str):
        data = self.documents.get(doc_id)
        if not data:
            return
        self.loading_state = True
        try:
            self.current_doc_id = doc_id
            self.workspace_name.set(data.get("name", "Table extraction workspace"))
            self.source_var.set(data.get("source_dataset_id", ""))
            self.page_var.set(int(data.get("page", 1)))
            self.dpi_var.set(int(data.get("dpi", 300)))
            self.zoom_var.set(int(data.get("zoom", 50)))
            self.mode_var.set(data.get("mode", "Auto") if data.get("mode", "Auto") in MODE_CHOICES else "Auto")
            self.psm_var.set(data.get("psm_label", "Block") if data.get("psm_label", "Block") in PSM_CHOICES else "Block")
            self.expected_columns_var.set(int(data.get("expected_columns", 0)))
            self.first_row_header_var.set(bool(data.get("first_row_header", True)))
            self.output_id.set(data.get("output_dataset_id", ""))
            self.output_name.set(data.get("output_name", "Extracted table"))
            self.load_source(render=False)
            self.set_selected_languages(data.get("ocr_languages", []))
            self.render_source()
            roi = data.get("roi")
            if roi and len(roi) == 4 and self.page_image:
                self.canvas.selection = Rect(*[int(v) for v in roi]).clamp(*self.page_image.size)
                self.canvas._redraw_selection()
                self.selection_changed(self.canvas.selection)
            self.table_rows = [[str(cell) for cell in row] for row in data.get("table_rows", [])]
            self.last_method = str(data.get("last_method", ""))
            self.last_token_count = int(data.get("last_token_count", 0))
            self.last_boundaries = [float(x) for x in data.get("last_boundaries", [])]
            self.last_extraction_roi = self.canvas.selection if self.canvas.selection else (Rect(0, 0, self.page_image.width, self.page_image.height) if self.page_image else None)
            self.refresh_table_preview()
            self.canvas.draw_boundaries(self.last_boundaries, self.last_extraction_roi)
            if self.last_method:
                self.method_info.set(f"{self.last_method}; {self.last_token_count} tokens")
            self.status.set(f"Workspace loaded: {self.workspace_name.get()}")
        finally:
            self.loading_state = False
            self.refresh_workspace_selector()

    def close(self):
        try:
            shutil.rmtree(self.tempdir, ignore_errors=True)
        finally:
            self.root.destroy()


def main() -> int:
    rpc = RpcClient()
    root = tk.Tk()
    try:
        TableExtractorApp(root, rpc)
    except Exception as exc:
        try:
            messagebox.showerror(APP_NAME, str(exc), parent=root)
        finally:
            root.destroy()
        return 1
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
