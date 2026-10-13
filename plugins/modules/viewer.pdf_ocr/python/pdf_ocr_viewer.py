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

sys.path.insert(0, sys.argv[2] if len(sys.argv)>2 and sys.argv[1]=="--core-python" else str(Path(__file__).resolve().parents[4] / "core" / "python"))
from gxtxt.pdf_canvas import PdfCanvas, render_page as shared_render_page
from pdf_ocr_model import HANDLES, Rect, handle_points, hit_test

APP_NAME = "GX-TXT PDF OCR Viewer"
WORKSPACE_FORMAT = "gxtxt.pdf_ocr.workspace"
WORKSPACE_VERSION = "1.0"
PLUGIN_VERSION = "1.0.3"
ZOOM_LEVELS = (25, 33, 50, 67, 75, 100, 125, 150, 200, 250, 300, 400)
DPI_LEVELS = (150, 200, 300, 400, 600)
PSM_CHOICES = {
    "Auto": "3",
    "Block": "6",
    "Single line": "7",
    "Sparse text": "11",
}
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


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_dataset_id(value: str, fallback: str = "ocr.output") -> str:
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


def command_text(args: list[str], timeout: int | None = None) -> str:
    proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=timeout, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"Command failed with exit code {proc.returncode}: {args[0]}")
    return proc.stdout


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




class PdfOcrApp:
    def __init__(self, root: tk.Tk, rpc: RpcClient):
        self.root = root
        self.rpc = rpc
        self.rpc.focus_callback = self.focus_window
        self.root.title(APP_NAME)
        self.root.geometry("1450x920")
        self.root.minsize(1040, 700)

        self.tempdir = Path(tempfile.mkdtemp(prefix="gxtxt_pdf_ocr_"))
        self.session_token = ""
        self.datasets: dict[str, dict] = {}
        self.documents: dict[str, dict] = {}
        self.current_doc_id: str | None = None
        self.current_source_id = ""
        self.source_info: dict = {}
        self.source_path: Path | None = None
        self.pdf_info: dict[str, str] = {}
        self.page_image: Image.Image | None = None
        self.render_file: Path | None = None
        self.render_cache: dict[tuple[str, int, int], Path] = {}
        self.last_ocr_text = ""
        self.loading_state = False

        self.workspace_var = tk.StringVar()
        self.workspace_name = tk.StringVar(value="PDF OCR workspace")
        self.source_var = tk.StringVar()
        self.page_var = tk.IntVar(value=1)
        self.page_count_var = tk.StringVar(value="/ 0")
        self.dpi_var = tk.IntVar(value=300)
        self.zoom_var = tk.IntVar(value=50)
        self.psm_var = tk.StringVar(value="Auto")
        self.selection_info = tk.StringVar(value="No selection")
        self.status = tk.StringVar(value="Ready")
        self.crop_id = tk.StringVar(value="")
        self.page_image_id = tk.StringVar(value="")
        self.text_id = tk.StringVar(value="")
        self.page_text_id = tk.StringVar(value="")
        self.pdf_id = tk.StringVar(value="")
        self.pdf_text_id = tk.StringVar(value="")

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

        autoclose = os.environ.get("GX_PDF_OCR_TEST_AUTOCLOSE_MS", "").strip()
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
                did, contract, fmt_, media, sha, title, pages = fields
                self.datasets[did] = {"contract": contract, "format": fmt_, "media_type": media, "sha256": sha, "title": title, "page_count": pages}
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

    @staticmethod
    def detect_languages() -> list[str]:
        text = command_text(["tesseract", "--list-langs"], timeout=20)
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        if lines and lines[0].lower().startswith("list of available languages"):
            lines = lines[1:]
        return sorted(set(lines), key=str.casefold)

    def build_ui(self):
        main = ttk.Frame(self.root, padding=6)
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

        top = ttk.Frame(main)
        top.pack(fill="x", pady=(0, 6))
        ttk.Label(top, text="PDF Dataset:").pack(side="left")
        self.source_combo = ttk.Combobox(top, state="readonly", width=38, values=list(self.datasets), textvariable=self.source_var)
        self.source_combo.pack(side="left", padx=(5, 4))
        ttk.Button(top, text="Load", command=self.load_source).pack(side="left", padx=2)
        ttk.Button(top, text="◀", width=3, command=self.prev_page).pack(side="left", padx=(14, 2))
        tk.Spinbox(top, from_=1, to=99999, width=6, textvariable=self.page_var, command=self.render_page).pack(side="left")
        ttk.Label(top, textvariable=self.page_count_var, width=8).pack(side="left")
        ttk.Button(top, text="▶", width=3, command=self.next_page).pack(side="left", padx=2)
        ttk.Label(top, text="DPI:").pack(side="left", padx=(14, 3))
        ttk.Combobox(top, state="readonly", width=6, values=DPI_LEVELS, textvariable=self.dpi_var).pack(side="left")
        ttk.Button(top, text="Render", command=self.render_page).pack(side="left", padx=3)
        ttk.Label(top, text="Zoom:").pack(side="left", padx=(14, 3))
        zc = ttk.Combobox(top, state="readonly", width=6, values=ZOOM_LEVELS, textvariable=self.zoom_var)
        zc.pack(side="left")
        zc.bind("<<ComboboxSelected>>", lambda _e: self.apply_zoom())
        ttk.Button(top, text="Clear ROI", command=lambda: self.canvas.clear_selection()).pack(side="left", padx=(14, 2))

        paned = ttk.Panedwindow(main, orient="vertical")
        paned.pack(fill="both", expand=True)
        view_frame = ttk.Frame(paned)
        lower = ttk.Frame(paned)
        paned.add(view_frame, weight=4)
        paned.add(lower, weight=2)

        self.canvas = PdfCanvas(view_frame, self.selection_changed)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.zoom_callback = self.wheel_zoom

        roi = ttk.Frame(lower)
        roi.pack(fill="x", pady=(6, 4))
        ttk.Label(roi, textvariable=self.selection_info, width=46).pack(side="left")
        ttk.Label(roi, text="Crop Dataset ID:").pack(side="left", padx=(8, 3))
        ttk.Entry(roi, width=24, textvariable=self.crop_id).pack(side="left")
        ttk.Button(roi, text="Publish crop Dataset", command=self.publish_crop).pack(side="left", padx=4)
        ttk.Label(roi, text="Whole-page image ID:").pack(side="left", padx=(10, 3))
        ttk.Entry(roi, width=24, textvariable=self.page_image_id).pack(side="left")
        ttk.Button(roi, text="Publish whole page Dataset", command=self.publish_whole_page).pack(side="left", padx=4)

        ocr = ttk.Frame(lower)
        ocr.pack(fill="x", pady=4)
        ttk.Label(ocr, text="OCR languages:").pack(side="left")
        self.lang_list = tk.Listbox(ocr, selectmode="extended", exportselection=False, height=4, width=22)
        self.lang_list.pack(side="left", padx=(5, 10))
        for lang in self.languages:
            self.lang_list.insert("end", lang)
        if "eng" in self.languages:
            self.lang_list.selection_set(self.languages.index("eng"))
        elif self.languages:
            self.lang_list.selection_set(0)
        ttk.Label(ocr, text="Layout:").pack(side="left")
        ttk.Combobox(ocr, state="readonly", width=13, values=list(PSM_CHOICES), textvariable=self.psm_var).pack(side="left", padx=(4, 8))
        ttk.Button(ocr, text="OCR selection", command=self.ocr_selection).pack(side="left", padx=3)
        ttk.Label(ocr, text="ROI text ID:").pack(side="left", padx=(10, 3))
        ttk.Entry(ocr, width=22, textvariable=self.text_id).pack(side="left")
        ttk.Button(ocr, text="Publish ROI text Dataset", command=self.publish_text).pack(side="left", padx=4)
        ttk.Label(ocr, text="Whole-page text ID:").pack(side="left", padx=(10, 3))
        ttk.Entry(ocr, width=22, textvariable=self.page_text_id).pack(side="left")
        ttk.Button(ocr, text="OCR whole page → Dataset", command=self.ocr_whole_page).pack(side="left", padx=4)
        ttk.Button(ocr, text="Copy OCR", command=self.copy_text).pack(side="left", padx=3)

        full = ttk.Frame(lower)
        full.pack(fill="x", pady=4)
        ttk.Label(full, text="OCR PDF Dataset ID:").pack(side="left")
        ttk.Entry(full, width=28, textvariable=self.pdf_id).pack(side="left", padx=(5, 4))
        ttk.Button(full, text="OCR whole PDF → PDF Dataset", command=self.ocr_whole_pdf).pack(side="left", padx=4)
        ttk.Label(full, text="Whole-PDF text ID:").pack(side="left", padx=(10, 3))
        ttk.Entry(full, width=28, textvariable=self.pdf_text_id).pack(side="left")
        ttk.Button(full, text="OCR whole PDF → text Dataset", command=self.ocr_whole_pdf_text).pack(side="left", padx=4)

        text_frame = ttk.Frame(lower)
        text_frame.pack(fill="both", expand=True, pady=(4, 0))
        self.ocr_text = tk.Text(text_frame, wrap="word", height=9)
        text_scroll = ttk.Scrollbar(text_frame, orient="vertical", command=self.ocr_text.yview)
        self.ocr_text.configure(yscrollcommand=text_scroll.set)
        self.ocr_text.pack(side="left", fill="both", expand=True)
        text_scroll.pack(side="right", fill="y")

        bottom = ttk.Frame(main)
        bottom.pack(fill="x", pady=(5, 0))
        ttk.Label(bottom, text="Wheel: zoom  •  Arrow keys: pan  •  Middle drag: pan  •  Left drag: create/move ROI  •  Handles: resize", anchor="w").pack(side="left", fill="x", expand=True)
        ttk.Label(bottom, textvariable=self.status, anchor="e").pack(side="right")

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

    def new_workspace(self):
        name = simpledialog.askstring(APP_NAME, "Workspace name:", initialvalue="PDF OCR workspace", parent=self.root)
        if not name:
            return
        self.current_doc_id = None
        self.workspace_name.set(name.strip())
        if self.datasets and not self.source_var.get():
            self.source_var.set(next(iter(self.datasets)))
        self.status.set("New workspace")

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
            self.workspace_name.set(data.get("name", "PDF OCR workspace"))
            self.source_var.set(data.get("source_dataset_id", ""))
            self.page_var.set(int(data.get("page", 1)))
            self.dpi_var.set(int(data.get("dpi", 300)))
            self.zoom_var.set(int(data.get("zoom", 50)))
            self.psm_var.set(data.get("psm_label", "Auto") if data.get("psm_label") in PSM_CHOICES else "Auto")
            self.crop_id.set(data.get("crop_dataset_id", ""))
            self.page_image_id.set(data.get("page_image_dataset_id", ""))
            self.text_id.set(data.get("text_dataset_id", ""))
            self.page_text_id.set(data.get("page_text_dataset_id", ""))
            self.pdf_id.set(data.get("pdf_dataset_id", ""))
            self.pdf_text_id.set(data.get("pdf_text_dataset_id", ""))
            self.load_source(render=False)
            self.set_selected_languages(data.get("ocr_languages", []))
            self.render_page()
            roi = data.get("roi")
            if roi and len(roi) == 4 and self.page_image:
                self.canvas.selection = Rect(*[int(v) for v in roi]).clamp(*self.page_image.size)
                self.canvas._redraw_selection()
                self.selection_changed(self.canvas.selection)
            self.status.set(f"Workspace loaded: {self.workspace_name.get()}")
        finally:
            self.loading_state = False
            self.refresh_workspace_selector()

    def workspace_payload(self) -> str:
        roi = None
        if self.canvas.selection:
            r = self.canvas.selection.normalized()
            roi = [r.x1, r.y1, r.x2, r.y2]
        data = {
            "format": WORKSPACE_FORMAT,
            "version": WORKSPACE_VERSION,
            "name": self.workspace_name.get().strip() or "PDF OCR workspace",
            "source_dataset_id": self.current_source_id or self.source_var.get().strip(),
            "source_sha256": self.source_info.get("sha256", ""),
            "page": int(self.page_var.get()),
            "dpi": int(self.dpi_var.get()),
            "zoom": int(self.zoom_var.get()),
            "roi": roi,
            "ocr_languages": self.selected_languages(),
            "psm_label": self.psm_var.get(),
            "crop_dataset_id": self.crop_id.get().strip(),
            "page_image_dataset_id": self.page_image_id.get().strip(),
            "text_dataset_id": self.text_id.get().strip(),
            "page_text_dataset_id": self.page_text_id.get().strip(),
            "pdf_dataset_id": self.pdf_id.get().strip(),
            "pdf_text_dataset_id": self.pdf_text_id.get().strip(),
        }
        return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)

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
        if not messagebox.askyesno(APP_NAME, "Delete this saved OCR workspace? Published Datasets are not deleted.", parent=self.root):
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

    def selected_languages(self) -> list[str]:
        return [self.lang_list.get(i) for i in self.lang_list.curselection()]

    def selected_language_spec(self) -> str:
        langs = self.selected_languages()
        if not langs:
            raise RuntimeError("Select at least one installed Tesseract language.")
        return "+".join(langs)

    def set_selected_languages(self, languages):
        self.lang_list.selection_clear(0, "end")
        selected = False
        for lang in languages or []:
            if lang in self.languages:
                self.lang_list.selection_set(self.languages.index(lang)); selected = True
        if not selected:
            if "eng" in self.languages:
                self.lang_list.selection_set(self.languages.index("eng"))
            elif self.languages:
                self.lang_list.selection_set(0)

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
            registered = str(info.get("sha256", "")).lower()
            if registered and actual_sha.lower() != registered:
                raise RuntimeError(f"Source Dataset integrity check failed for '{dataset_id}'.")
            pdf_text = command_text(["pdfinfo", str(path)], timeout=30)
            self.pdf_info = parse_pdfinfo(pdf_text)
            pages = int(self.pdf_info.get("pages", "0") or 0)
            if pages < 1:
                raise RuntimeError("The PDF contains no renderable pages.")
            self.current_source_id = dataset_id
            self.source_info = info
            self.source_path = path
            self.page_count_var.set(f"/ {pages}")
            self.page_var.set(max(1, min(pages, int(self.page_var.get()))))
            self.update_default_output_ids(force=not any((
                self.crop_id.get(), self.page_image_id.get(), self.text_id.get(),
                self.page_text_id.get(), self.pdf_id.get(), self.pdf_text_id.get())))
            self.status.set(f"Loaded {dataset_id} ({pages} pages)")
            if render:
                self.render_page()
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def page_count(self) -> int:
        try:
            return int(self.pdf_info.get("pages", "0") or 0)
        except ValueError:
            return 0

    def update_default_output_ids(self, force=False):
        if not self.current_source_id:
            return
        base = safe_dataset_id(self.current_source_id, "document")
        page = max(1, int(self.page_var.get()))
        defaults = (
            (self.crop_id, f"{base}.p{page:03d}.crop"),
            (self.page_image_id, f"{base}.p{page:03d}.page_image"),
            (self.text_id, f"{base}.p{page:03d}.ocr_text"),
            (self.page_text_id, f"{base}.p{page:03d}.page_text"),
            (self.pdf_id, f"{base}.ocr_pdf"),
            (self.pdf_text_id, f"{base}.ocr_text"),
        )
        for var, value in defaults:
            if force or not var.get().strip():
                var.set(value)

    def render_page(self):
        if not self.source_path:
            self.load_source(render=False)
        if not self.source_path:
            return
        try:
            pages = self.page_count()
            page = max(1, min(pages, int(self.page_var.get())))
            self.page_var.set(page)
            dpi = int(self.dpi_var.get())
            self.status.set(f"Rendering page {page} at {dpi} DPI…")
            self.root.update_idletasks()
            out = self.rendered_page_path(page, dpi)
            try:
                with Image.open(out) as image:
                    self.page_image = image.convert("RGB").copy()
            except UnidentifiedImageError as exc:
                raise RuntimeError(f"Rendered page is not a readable image: {exc}") from exc
            self.render_file = out
            old = self.canvas.selection
            self.canvas.set_image(self.page_image, int(self.zoom_var.get()), old)
            self.update_default_output_ids(force=False)
            self.selection_changed(self.canvas.selection)
            self.status.set(f"Page {page} / {pages} ready")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Render failed")

    def apply_zoom(self):
        if self.page_image:
            self.canvas.set_zoom(int(self.zoom_var.get()))

    def wheel_zoom(self, direction: int, x: int, y: int):
        if not self.page_image:
            return
        current = int(self.zoom_var.get())
        try:
            idx = ZOOM_LEVELS.index(current)
        except ValueError:
            idx = ZOOM_LEVELS.index(50)
        new_idx = max(0, min(len(ZOOM_LEVELS)-1, idx + direction))
        if new_idx == idx:
            return
        anchor = self.canvas.zoom_anchor(x, y)
        self.zoom_var.set(ZOOM_LEVELS[new_idx])
        self.canvas.set_zoom(ZOOM_LEVELS[new_idx], keep_source_anchor=anchor)
        self.status.set(f"Preview {ZOOM_LEVELS[new_idx]}%")

    def selection_changed(self, rect: Rect | None):
        if not rect:
            self.selection_info.set("No selection")
            return
        r = rect.normalized()
        self.selection_info.set(f"ROI: x={r.x1} y={r.y1}  {r.width} × {r.height} px")

    def require_selection(self) -> Rect:
        if not self.page_image or not self.canvas.selection:
            raise RuntimeError("Create a rectangular ROI on the rendered page first.")
        r = self.canvas.selection.clamp(*self.page_image.size)
        if r.width < 2 or r.height < 2:
            raise RuntimeError("The ROI is too small.")
        return r

    def require_page_image(self) -> Image.Image:
        if not self.page_image:
            raise RuntimeError("Render a page first.")
        return self.page_image

    def full_page_rect(self) -> Rect:
        image = self.require_page_image()
        return Rect(0, 0, image.width, image.height)

    def make_crop_for_rect(self, rect: Rect, prefix: str = "crop") -> tuple[Path, Rect, tuple[int, int]]:
        image = self.require_page_image()
        r = rect.clamp(*image.size)
        if r.width < 2 or r.height < 2:
            raise RuntimeError("The selected area is too small.")
        crop = image.crop((r.x1, r.y1, r.x2, r.y2))
        path = self.tempdir / f"{prefix}-{time.time_ns()}.png"
        crop.save(path, format="PNG")
        return path, r, crop.size

    def make_crop(self) -> tuple[Path, Rect, tuple[int, int]]:
        return self.make_crop_for_rect(self.require_selection(), prefix="crop")

    def run_tesseract(self, image_path: Path, languages: str, psm: str, timeout: int = 300) -> str:
        return command_text(["tesseract", str(image_path), "stdout", "-l", languages, "--psm", psm], timeout=timeout)

    def set_ocr_preview(self, text: str):
        self.last_ocr_text = text
        self.ocr_text.delete("1.0", "end")
        self.ocr_text.insert("1.0", text)

    def rendered_page_path(self, page: int, dpi: int) -> Path:
        if not self.source_path:
            raise RuntimeError("Load a PDF Dataset first.")
        key = (self.current_source_id, page, dpi)
        out = self.render_cache.get(key)
        if not out or not out.exists():
            base = self.tempdir / f"page-{abs(hash(self.current_source_id)) & 0xfffffff:x}-{page:04d}-{dpi}dpi"
            shared_render_page(self.source_path, page, dpi, base)
            out = Path(str(base) + ".png")
            if not out.is_file():
                raise RuntimeError("Poppler did not create the rendered page image.")
            self.render_cache[key] = out
        return out

    def publish_crop(self):
        try:
            path, r, size = self.make_crop()
            dataset_id = safe_dataset_id(self.crop_id.get(), "ocr.crop")
            result = self.rpc.call("PUBLISH_IMAGE", dataset_id, self.current_source_id, str(path), str(self.page_var.get()), str(self.dpi_var.get()), r.as_csv(), str(size[0]), str(size[1]), self.session_token)
            self.crop_id.set(dataset_id)
            self.status.set(f"Published image Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def publish_whole_page(self):
        try:
            path, r, size = self.make_crop_for_rect(self.full_page_rect(), prefix="page")
            dataset_id = safe_dataset_id(self.page_image_id.get(), "ocr.page")
            result = self.rpc.call("PUBLISH_IMAGE", dataset_id, self.current_source_id, str(path), str(self.page_var.get()), str(self.dpi_var.get()), r.as_csv(), str(size[0]), str(size[1]), self.session_token)
            self.page_image_id.set(dataset_id)
            self.status.set(f"Published whole-page image Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def ocr_selection(self):
        try:
            path, _r, _size = self.make_crop()
            languages = self.selected_language_spec()
            psm = PSM_CHOICES.get(self.psm_var.get(), "3")
            self.status.set(f"OCR selection ({languages}, PSM {psm})…")
            self.root.update_idletasks()
            text = self.run_tesseract(path, languages, psm, timeout=300)
            self.set_ocr_preview(text)
            self.status.set(f"OCR completed: {len(text)} characters")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("OCR failed")

    def publish_text(self):
        try:
            text = self.ocr_text.get("1.0", "end-1c")
            if not text.strip():
                raise RuntimeError("Run OCR or enter text before publishing a text Dataset.")
            r = self.require_selection()
            languages = self.selected_language_spec()
            psm = PSM_CHOICES.get(self.psm_var.get(), "3")
            path = self.tempdir / f"ocr-{time.time_ns()}.txt"
            path.write_text(text, encoding="utf-8", newline="")
            dataset_id = safe_dataset_id(self.text_id.get(), "ocr.text")
            result = self.rpc.call("PUBLISH_TEXT", dataset_id, self.current_source_id, str(path), languages, psm, str(self.page_var.get()), r.as_csv(), self.session_token)
            self.text_id.set(dataset_id)
            self.status.set(f"Published text Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)

    def ocr_whole_page(self):
        try:
            path, r, _size = self.make_crop_for_rect(self.full_page_rect(), prefix="page-ocr")
            languages = self.selected_language_spec()
            psm = PSM_CHOICES.get(self.psm_var.get(), "3")
            self.status.set(f"OCR whole page ({languages}, PSM {psm})…")
            self.root.update_idletasks()
            text = self.run_tesseract(path, languages, psm, timeout=300)
            self.set_ocr_preview(text)
            txt_path = self.tempdir / f"page-ocr-{time.time_ns()}.txt"
            txt_path.write_text(text, encoding="utf-8", newline="")
            dataset_id = safe_dataset_id(self.page_text_id.get(), "ocr.page_text")
            result = self.rpc.call("PUBLISH_TEXT", dataset_id, self.current_source_id, str(txt_path), languages, psm, str(self.page_var.get()), r.as_csv(), self.session_token)
            self.page_text_id.set(dataset_id)
            self.status.set(f"Published whole-page text Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Whole-page OCR failed")

    def copy_text(self):
        text = self.ocr_text.get("1.0", "end-1c")
        if not text:
            return
        self.root.clipboard_clear(); self.root.clipboard_append(text)
        self.status.set("OCR text copied to clipboard")

    def ocr_whole_pdf(self):
        if not self.source_path:
            return
        try:
            languages = self.selected_language_spec()
            dataset_id = safe_dataset_id(self.pdf_id.get(), "ocr.document")
            output = self.tempdir / f"ocr-pdf-{time.time_ns()}.pdf"
            self.status.set(f"Running whole-document OCR ({languages})…")
            self.root.update_idletasks()
            command_text(["ocrmypdf", "-l", languages, "--deskew", "--rotate-pages", str(self.source_path), str(output)], timeout=3600)
            command_text(["qpdf", "--check", str(output)], timeout=120)
            info = parse_pdfinfo(command_text(["pdfinfo", str(output)], timeout=30))
            pages = int(info.get("pages", "0") or 0)
            if pages < 1:
                raise RuntimeError("OCR output PDF contains no pages.")
            version = info.get("pdf version", "")
            result = self.rpc.call("PUBLISH_PDF", dataset_id, self.current_source_id, str(output), languages, str(pages), version, self.session_token)
            self.pdf_id.set(dataset_id)
            self.status.set(f"Published OCR PDF Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Whole-document OCR failed")

    def ocr_whole_pdf_text(self):
        if not self.source_path:
            return
        try:
            languages = self.selected_language_spec()
            psm = PSM_CHOICES.get(self.psm_var.get(), "3")
            dpi = int(self.dpi_var.get())
            pages = self.page_count()
            if pages < 1:
                raise RuntimeError("The PDF contains no pages.")
            chunks: list[str] = []
            for page in range(1, pages + 1):
                self.status.set(f"OCR whole PDF to text: page {page}/{pages} ({languages}, PSM {psm})…")
                self.root.update_idletasks()
                image_path = self.rendered_page_path(page, dpi)
                page_text = self.run_tesseract(image_path, languages, psm, timeout=600).rstrip()
                chunks.append(page_text)
            text = "\n\f\n".join(chunks).rstrip() + "\n"
            self.set_ocr_preview(text)
            txt_path = self.tempdir / f"pdf-ocr-text-{time.time_ns()}.txt"
            txt_path.write_text(text, encoding="utf-8", newline="")
            dataset_id = safe_dataset_id(self.pdf_text_id.get(), "ocr.document_text")
            result = self.rpc.call("PUBLISH_TEXT_DOCUMENT", dataset_id, self.current_source_id, str(txt_path), languages, psm, str(pages), str(dpi), self.session_token)
            self.pdf_text_id.set(dataset_id)
            self.status.set(f"Published whole-PDF text Dataset: {result.split(chr(9))[0]}")
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.status.set("Whole-document text OCR failed")

    def prev_page(self):
        if int(self.page_var.get()) > 1:
            self.page_var.set(int(self.page_var.get()) - 1)
            self.canvas.clear_selection()
            self.update_default_output_ids(force=True)
            self.render_page()

    def next_page(self):
        if int(self.page_var.get()) < self.page_count():
            self.page_var.set(int(self.page_var.get()) + 1)
            self.canvas.clear_selection()
            self.update_default_output_ids(force=True)
            self.render_page()

    def close(self):
        try:
            shutil.rmtree(self.tempdir, ignore_errors=True)
        finally:
            self.root.destroy()


def main() -> int:
    try:
        root = tk.Tk()
        rpc = RpcClient()
        PdfOcrApp(root, rpc)
        root.mainloop()
        return 0
    except Exception as exc:
        try:
            sys.stderr.write(f"{APP_NAME}: {exc}\n")
        except Exception:
            pass
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
