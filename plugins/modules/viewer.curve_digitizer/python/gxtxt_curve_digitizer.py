# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import base64
import copy
import json
import math
import logging
import queue
import threading
import time
import os
import re
import sys
import uuid
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

import numpy as np
from PIL import Image, ImageTk, UnidentifiedImageError

from digitizer_model import AxisConfig, CalibrationError, CORNER_ORDER, DigitizedPoint, Project, Series
from image_canvas import ImageCanvas
from uncertainty_dialog import UncertaintyDialog

APP_NAME = "GX-TXT Curve Digitalizer"
LOG = logging.getLogger("gx.curve_digitizer")
STARTUP_TIMEOUT_SECONDS = 45.0
RPC_TIMEOUT_SECONDS = 120.0
CONFIG_FORMAT = "gxtxt.curve_digitizer.configuration"
CONFIG_VERSION = "1.0"
PLUGIN_VERSION = "1.2.4"
SERIES_COLORS = ("#d62728", "#1f77b4", "#2ca02c", "#9467bd", "#ff7f0e", "#17becf", "#e377c2", "#8c564b", "#bcbd22")
CORNER_LABELS = {"bottom_left": "BL", "bottom_right": "BR", "top_left": "TL", "top_right": "TR"}
RESAMPLE_LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def b64e(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def b64d(value: str) -> str:
    return base64.b64decode(value.encode("ascii")).decode("utf-8")


def parse_records(payload: str) -> list[tuple[str, list[str]]]:
    out = []
    for line in payload.splitlines():
        if not line:
            continue
        fields = line.split("\t")
        out.append((fields[0], [b64d(x) for x in fields[1:]]))
    return out


def fmt(value, digits=10):
    if value is None:
        return "—"
    return f"{value:.{digits}g}" if math.isfinite(value) else str(value)


def slug_id(name: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9_.-]+", ".", name.strip()).strip(".-_").lower()
    if not slug or not slug[0].isalpha():
        slug = "curve." + slug
    return "digitized." + slug[:60]


class RpcError(RuntimeError):
    pass


class RpcClient:
    """One portable pipe reader; all Tk work stays on the GUI thread.

    Windows Tk has no createfilehandler. A daemon thread therefore owns stdin
    on every platform and hands complete lines to the GUI via a Queue. This
    handles CONTROL/FOCUS while idle, not only during a scientific RPC call.
    Synchronous state-changing calls are never retried after a timeout.
    """

    def __init__(self, root=None, *, timeout=RPC_TIMEOUT_SECONDS):
        self.counter = 0
        self.focus_callback = None
        self.timeout = timeout
        self._root = None
        self._incoming = queue.Queue()
        self._responses = {}
        self._pending = set()
        self._failure = None
        self._focus_pending = False
        self._input = sys.stdin
        self._output = sys.stdout
        self._reader = threading.Thread(target=self._read_loop, daemon=True,
                                        name="curve-digitizer-pipe-reader")
        self._reader.start()
        if root is not None:
            self.attach(root)

    def attach(self, root):
        if self._root is root:
            return
        self._root = root
        root.after(50, self._poll_controls)

    def _read_loop(self):
        # No tkinter calls here, including root.after: this thread only does I/O.
        # Raw descriptor reads avoid leaving a daemon thread holding Python's
        # BufferedReader lock at interpreter shutdown (the parent may still
        # have its pipe writer open when the user closes this window).
        try:
            fd = self._input.fileno()
            pending = b""
            while True:
                chunk = os.read(fd, 65536)
                if not chunk:
                    self._incoming.put(("error", "The GX-TXT host connection closed."))
                    return
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    self._incoming.put(("line", line.rstrip(b"\r").decode("utf-8")))
        except Exception as exc:
            self._incoming.put(("error", f"Unable to read the GX-TXT connection: {exc}"))

    def _accept(self, item):
        kind, line = item
        if kind == "error":
            self._failure = line
            LOG.warning("%s", line)
            return
        if line == "CONTROL\tFOCUS":
            self._focus_pending = True
            return
        fields = line.split("\t")
        if len(fields) != 4 or fields[0] != "RES":
            LOG.warning("Ignoring an unrecognized host protocol frame")
            return
        if fields[1] in self._pending:
            self._responses[fields[1]] = fields[2:]
            LOG.info("Response received id=%s status=%s", fields[1], fields[2])

    def _drain(self):
        for _ in range(64):
            try:
                self._accept(self._incoming.get_nowait())
            except queue.Empty:
                return

    def _poll_controls(self):
        self._drain()
        if self._focus_pending and self.focus_callback is not None:
            self._focus_pending = False
            self.focus_callback()
        try:
            if self._root.winfo_exists():
                self._root.after(50, self._poll_controls)
        except tk.TclError:
            pass

    def _write(self, line):
        try:
            self._output.write(line + "\n")
            self._output.flush()
        except (OSError, ValueError, AttributeError) as exc:
            self._failure = f"Unable to write to the GX-TXT connection: {exc}"
            raise RpcError(self._failure) from exc

    def notify(self, event):
        self._write("EVT\t" + event)

    def begin(self, command, *args):
        if self._failure:
            raise RpcError(self._failure)
        self.counter += 1
        request_id = str(self.counter)
        self._pending.add(request_id)
        LOG.info("Request id=%s command=%s", request_id, command)
        self._write("\t".join(["REQ", request_id, command] + [b64e(str(a)) for a in args]))
        return request_id

    def poll_response(self, request_id):
        """Return a response or None without waiting or pumping nested Tk events."""
        self._drain()
        if request_id in self._responses:
            status, encoded = self._responses.pop(request_id)
            self._pending.discard(request_id)
            try:
                payload = b64d(encoded)
            except Exception as exc:
                raise RpcError("Invalid UTF-8/base64 response from GX-TXT.") from exc
            if status == "ERR":
                raise RpcError(payload)
            if status != "OK":
                raise RpcError(f"Unknown GX-TXT response status: {status}")
            return payload
        if self._failure:
            raise RpcError(self._failure)
        return None

    def call(self, command: str, *args: str) -> str:
        request_id = self.begin(command, *args)
        deadline = time.monotonic() + self.timeout
        while True:
            payload = self.poll_response(request_id)
            if payload is not None:
                return payload
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                # A late reply to a write must not invite an automatic retry:
                # the host may already have committed the operation.
                self._failure = (f"GX-TXT did not reply to {command} within {self.timeout:g} seconds. "
                                 "Close and reopen this viewer, then check the Session before retrying: "
                                 "the operation may have completed on the host.")
                raise RpcError(self._failure)
            try:
                self._accept(self._incoming.get(timeout=min(remaining, 0.25)))
            except queue.Empty:
                pass


class SourcePreviewDialog(tk.Toplevel):
    def __init__(self, master, dataset_id: str, image, info: dict):
        super().__init__(master)
        self.title("Preview source image")
        self.transient(master)
        self.grab_set()
        self.result = False
        self.resizable(True, True)

        outer = ttk.Frame(self, padding=12)
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text=f"Preview before linking: {dataset_id}", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")

        body = ttk.Frame(outer)
        body.pack(fill="both", expand=True, pady=(8, 0))

        preview = image.copy()
        preview.thumbnail((720, 420), RESAMPLE_LANCZOS)
        self.photo = ImageTk.PhotoImage(preview)
        preview_frame = ttk.Frame(body, padding=(0, 0, 12, 0))
        preview_frame.pack(side="left", fill="both", expand=True)
        ttk.Label(preview_frame, image=self.photo, relief="solid", borderwidth=1).pack(anchor="center")

        details = ttk.Frame(body)
        details.pack(side="left", fill="both", expand=True)
        ttk.Label(details, text="Dataset details", font=("TkDefaultFont", 9, "bold")).pack(anchor="w")
        lines = [
            f"Dataset ID: {dataset_id}",
            f"Image size: {image.size[0]} × {image.size[1]}",
        ]
        if info.get("format"):
            lines.append(f"Format: {info['format']}")
        if info.get("media_type"):
            lines.append(f"Media type: {info['media_type']}")
        if info.get("sha256"):
            lines.append(f"SHA-256: {info['sha256']}")
        metadata = info.get("metadata", {}) or {}
        for key, label in (("source.original_filename", "Source file"), ("source.document", "Source document"),
                           ("document.title", "Document"), ("page.number", "Page"), ("source.page", "Page"),
                           ("manufacturer", "Manufacturer"), ("source.url", "Source URL")):
            value = metadata.get(key)
            if value:
                line = f"{label}: {value}"
                if line not in lines:
                    lines.append(line)
        text_widget = tk.Text(details, width=48, height=16, wrap="word")
        text_widget.pack(fill="both", expand=True, pady=(6, 0))
        text_widget.insert("1.0", "\n".join(lines))
        text_widget.configure(state="disabled")

        hint = ttk.Label(outer, text="Review the preview and confirm only if this is the correct source image for the new configuration.", wraplength=820, justify="left")
        hint.pack(anchor="w", pady=(8, 0))

        buttons = ttk.Frame(outer)
        buttons.pack(fill="x", pady=(12, 0))
        ttk.Button(buttons, text="Cancel", command=self.cancel).pack(side="right")
        ttk.Button(buttons, text="Use this image", command=self.accept).pack(side="right", padx=(0, 6))

        self.bind("<Escape>", lambda _e: self.cancel())
        self.bind("<Return>", lambda _e: self.accept())
        self.update_idletasks()
        try:
            self.minsize(max(700, self.winfo_reqwidth()), max(480, self.winfo_reqheight()))
        except tk.TclError:
            pass

    def accept(self):
        self.result = True
        self.destroy()

    def cancel(self):
        self.result = False
        self.destroy()


class SeriesDialog(tk.Toplevel):
    def __init__(self, master, series=None, family_name="Family parameter", family_unit=""):
        super().__init__(master)
        self.title("Edit curve" if series else "New curve")
        self.transient(master)
        self.grab_set()
        self.resizable(False, False)
        self.result = None
        self.vars = [
            tk.StringVar(value=series.name if series else ""),
            tk.StringVar(value=series.parameter_value if series else ""),
            tk.StringVar(value=series.parameter_unit if series else family_unit),
        ]
        frame = ttk.Frame(self, padding=12)
        frame.pack(fill="both", expand=True)
        labels = ("Curve label", f"{family_name} value (optional)", "Family unit (optional)")
        for row, (label, var) in enumerate(zip(labels, self.vars)):
            ttk.Label(frame, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=4)
            ttk.Entry(frame, textvariable=var, width=32).grid(row=row, column=1, sticky="ew", pady=4)
        buttons = ttk.Frame(frame)
        buttons.grid(row=4, column=0, columnspan=2, sticky="e", pady=(10, 0))
        ttk.Button(buttons, text="Cancel", command=self.destroy).pack(side="right", padx=(6, 0))
        ttk.Button(buttons, text="OK", command=self.accept).pack(side="right")
        self.bind("<Return>", lambda _e: self.accept())
        self.bind("<Escape>", lambda _e: self.destroy())

    def accept(self):
        label, value, unit = [v.get().strip() for v in self.vars]
        if not label:
            messagebox.showerror(APP_NAME, "Curve label is required.", parent=self)
            return
        self.result = {"name": label, "parameter_value": value, "parameter_unit": unit}
        self.destroy()


class CurveDigitizerApp:
    def __init__(self, root: tk.Tk, rpc: RpcClient, *, bootstrap_payload=None):
        self.root = root
        self.rpc = rpc
        self.rpc.focus_callback = self.focus_window
        self.rpc.attach(root)
        root.title(APP_NAME)
        root.geometry("1380x880")
        root.minsize(1000, 650)

        self.session_token = ""
        self.units: list[str] = []
        self.roles: list[str] = []
        self.datasets: dict[str, dict] = {}
        self.documents: dict[str, dict] = {}
        self.document_sha: dict[str, str] = {}
        self.current_doc_id: str | None = None
        self.config: dict = {}
        self.project = Project()
        self.image = None
        self.gray_image = None
        self.source_metadata: dict[str, str] = {}
        self.stale_source = False
        self.active_series_id = None
        self.selected_point_id = None
        self.pending_corner = None
        self.undo_stack: list[dict] = []
        self.redo_stack: list[dict] = []
        self.dragging = False
        self.drag_snapshot = None
        self.loading_ui = False

        self.mode = tk.StringVar(value="add")
        self.status = tk.StringVar(value="Ready")
        self.config_var = tk.StringVar()
        self.source_var = tk.StringVar()
        self.source_diag = tk.StringVar()
        self.family_enabled = tk.BooleanVar(value=False)
        self.family_label = tk.StringVar(value="Family parameter")
        self.family_unit = tk.StringVar()
        self.family_role = tk.StringVar(value="family")
        self.output_dataset_id = tk.StringVar()
        self.output_display_name = tk.StringVar()
        self.x_name = tk.StringVar(value="X")
        self.x_unit = tk.StringVar()
        self.x_role = tk.StringVar(value="independent")
        self.x_min = tk.StringVar(value="0")
        self.x_max = tk.StringVar(value="1")
        self.x_scale = tk.StringVar(value="linear")
        self.y_name = tk.StringVar(value="Y")
        self.y_unit = tk.StringVar()
        self.y_role = tk.StringVar(value="measured")
        self.y_min = tk.StringVar(value="0")
        self.y_max = tk.StringVar(value="1")
        self.y_scale = tk.StringVar(value="linear")
        self.show_numbers = tk.BooleanVar(value=False)
        self.snap_enabled = tk.BooleanVar(value=False)
        self.snap_radius = tk.IntVar(value=3)
        self.cal_status = tk.StringVar(value="Calibration incomplete")
        self.selected_label = tk.StringVar(value="No point selected.")
        self.verify_result = tk.StringVar()
        self.exp_x = tk.StringVar()
        self.exp_y = tk.StringVar()

        self.bootstrap(bootstrap_payload)
        LOG.info("Building Curve Digitalizer widgets")
        self.build_ui()
        self.bind_keys()
        self.refresh_configuration_selector()
        if self.documents:
            self.open_document(next(iter(self.documents)))
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        scenario = os.environ.get("GX_CURVE_DIGITIZER_TEST_SCENARIO", "").strip()
        if scenario:
            self.root.after(250, lambda: self.run_test_scenario(scenario))

    def focus_window(self):
        try:
            if os.name == "nt" and not getattr(self, "_initial_show_done", False):
                # Force a real remap after startup; do not rely on the initial
                # show state inherited from the process-launch environment.
                self.root.withdraw()
                self.root.update_idletasks()
                self._initial_show_done = True
            self.root.deiconify()
            self.root.lift()
            self.root.focus_force()
            if os.name == "nt":
                # Temporary foreground hint, never leave the viewer always-on-top.
                pending = getattr(self, "_focus_restore_after", None)
                if pending is not None:
                    self.root.after_cancel(pending)
                else:
                    self._focus_was_topmost = self.root.attributes("-topmost")
                self.root.attributes("-topmost", True)
                self._focus_restore_after = self.root.after(150, self._restore_focus_topmost)
            self.rpc.notify("FOCUSED")
            LOG.info("Window focus requested; state=%s", self.root.state())
        except (tk.TclError, RpcError):
            LOG.exception("Unable to bring the digitizer window to the foreground")

    def _restore_focus_topmost(self):
        self._focus_restore_after = None
        try:
            self.root.attributes("-topmost", self._focus_was_topmost)
        except tk.TclError:
            pass

    def bootstrap(self, payload=None):
        if payload is None:
            payload = self.rpc.call("BOOTSTRAP")
        for kind, fields in parse_records(payload):
            if kind == "SESSION":
                self.session_token = fields[0]
            elif kind == "UNIT":
                self.units.append(fields[0])
            elif kind == "ROLE":
                self.roles.append(fields[0])
            elif kind == "DATASET":
                did, contract, fmt_, media, sha = fields
                self.datasets[did] = {"contract": contract, "format": fmt_, "media_type": media, "sha256": sha}
            elif kind == "DOCUMENT":
                if len(fields) < 3:
                    continue
                doc_id, text, _updated = fields[:3]
                document_sha = fields[3] if len(fields) >= 4 else ""
                try:
                    data = json.loads(text)
                except json.JSONDecodeError:
                    continue
                if data.get("format") == CONFIG_FORMAT:
                    self.documents[doc_id] = data
                    self.document_sha[doc_id] = document_sha
        if not self.session_token:
            raise RpcError("GX-TXT did not provide a Session token.")

    @staticmethod
    def new_configuration(name: str) -> dict:
        return {
            "format": CONFIG_FORMAT,
            "version": CONFIG_VERSION,
            "configuration_id": "digcfg_" + uuid.uuid4().hex,
            "name": name,
            "source": {
                "dataset_id": "",
                "resource_identity": "",
                "sha256": "",
                "format": "",
                "media_type": "",
                "width": 0,
                "height": 0,
            },
            "axes": {
                "x": {"name": "X", "unit": "", "minimum": 0.0, "maximum": 1.0, "scale": "linear", "semantic_role": "independent"},
                "y": {"name": "Y", "unit": "", "minimum": 0.0, "maximum": 1.0, "scale": "linear", "semantic_role": "measured"},
            },
            "calibration": {"points": {}},
            "curves": [],
            "family": {"enabled": False, "quantity_label": "Family parameter", "unit": "", "semantic_role": "family"},
            "display": {"show_point_numbers": False},
            "snap": {"enabled": False, "radius": 3},
            "view": {"scale": 1.0, "offset_x": 0.0, "offset_y": 0.0},
            "publication": {"dataset_id": "", "display_name": ""},
            "notes": "",
        }

    @staticmethod
    def parse_document_result(payload: str) -> tuple[str, str]:
        fields = payload.split("\t", 1)
        return fields[0], fields[1] if len(fields) > 1 else ""

    def config_to_project(self, cfg: dict) -> Project:
        p = Project.from_dict({
            "version": cfg.get("version", CONFIG_VERSION),
            "image": {"path": "", "width": cfg.get("source", {}).get("width", 0), "height": cfg.get("source", {}).get("height", 0)},
            "axes": cfg.get("axes", {}),
            "calibration": cfg.get("calibration", {}),
            "series": cfg.get("curves", []),
            "notes": cfg.get("notes", ""),
            "display": cfg.get("display", {}),
            "snap": cfg.get("snap", {}),
        })
        return p

    def serialize_configuration(self) -> dict:
        cfg = copy.deepcopy(self.config) if self.config else self.new_configuration("Untitled")
        cfg["format"] = CONFIG_FORMAT
        cfg["version"] = CONFIG_VERSION
        x = self.project.x_axis.to_dict()
        y = self.project.y_axis.to_dict()
        x["semantic_role"] = self.x_role.get().strip()
        y["semantic_role"] = self.y_role.get().strip()
        cfg["axes"] = {"x": x, "y": y}
        cfg["calibration"] = self.project.calibration.to_dict()
        cfg["curves"] = [s.to_dict() for s in self.project.series]
        cfg["family"] = {
            "enabled": bool(self.family_enabled.get()),
            "quantity_label": self.family_label.get().strip() or "Family parameter",
            "unit": self.family_unit.get().strip(),
            "semantic_role": self.family_role.get().strip() or "family",
        }
        cfg["display"] = {"show_point_numbers": bool(self.show_numbers.get())}
        cfg["snap"] = {"enabled": bool(self.snap_enabled.get()), "radius": max(0, int(self.snap_radius.get()))}
        cfg["notes"] = self.notes.get("1.0", "end-1c") if hasattr(self, "notes") else cfg.get("notes", "")
        cfg["publication"] = {
            "dataset_id": self.output_dataset_id.get().strip(),
            "display_name": self.output_display_name.get().strip(),
        }
        if hasattr(self, "canvas"):
            cfg["view"] = {"scale": self.canvas.scale, "offset_x": self.canvas.offset_x, "offset_y": self.canvas.offset_y}
        return cfg

    def persist(self):
        if self.loading_ui or not self.current_doc_id:
            return
        self.config = self.serialize_configuration()
        payload = json.dumps(self.config, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        try:
            expected_sha = self.document_sha.get(self.current_doc_id, "")
            result = self.rpc.call("DOC_UPDATE", self.current_doc_id, payload, self.session_token, expected_sha)
            doc_id, doc_sha = self.parse_document_result(result)
            if doc_id != self.current_doc_id:
                raise RpcError("GX-TXT returned an unexpected Interactive Document identity while saving.")
            self.document_sha[self.current_doc_id] = doc_sha
            self.documents[self.current_doc_id] = copy.deepcopy(self.config)
            return True
        except RpcError as exc:
            messagebox.showerror(APP_NAME, f"Unable to save the digitizer configuration in the Session:\n{exc}")
            return False

    def snapshot(self):
        if self.current_doc_id:
            self.undo_stack.append(self.serialize_configuration())
            self.undo_stack = self.undo_stack[-100:]
            self.redo_stack.clear()

    def restore_snapshot(self, cfg: dict, *, persist=True):
        self.config = copy.deepcopy(cfg)
        self.project = self.config_to_project(self.config)
        self.active_series_id = self.project.series[0].id if self.project.series else None
        self.selected_point_id = None
        self.sync_controls_from_config(reload_source=False)
        self.refresh_curve_tree()
        self.redraw()
        if persist:
            self.persist()

    def undo(self):
        if not self.undo_stack:
            return
        current = self.serialize_configuration()
        previous = self.undo_stack.pop()
        self.redo_stack.append(current)
        self.restore_snapshot(previous)

    def redo(self):
        if not self.redo_stack:
            return
        current = self.serialize_configuration()
        nxt = self.redo_stack.pop()
        self.undo_stack.append(current)
        self.restore_snapshot(nxt)

    def build_ui(self):
        top = ttk.Frame(self.root, padding=(8, 6))
        top.pack(fill="x")
        ttk.Label(top, text="Configuration:").pack(side="left")
        self.config_combo = ttk.Combobox(top, textvariable=self.config_var, state="readonly", width=34)
        self.config_combo.pack(side="left", padx=(6, 5))
        self.config_combo.bind("<<ComboboxSelected>>", self.on_configuration_selected)
        for text, command in (("New", self.new_config), ("Rename", self.rename_config), ("Duplicate", self.duplicate_config), ("Delete", self.delete_config)):
            ttk.Button(top, text=text, command=command).pack(side="left", padx=2)
        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=8)
        ttk.Button(top, text="Undo", command=self.undo).pack(side="left", padx=2)
        ttk.Button(top, text="Redo", command=self.redo).pack(side="left", padx=2)
        ttk.Button(top, text="Fit image", command=lambda: self.canvas.fit_to_window()).pack(side="left", padx=2)

        sourcebar = ttk.Frame(self.root, padding=(8, 0, 8, 6))
        sourcebar.pack(fill="x")
        ttk.Label(sourcebar, text="Source image Dataset:").pack(side="left")
        self.source_combo = ttk.Combobox(sourcebar, textvariable=self.source_var, state="readonly", values=list(self.datasets), width=45)
        self.source_combo.pack(side="left", padx=(6, 8))
        self.source_combo.bind("<<ComboboxSelected>>", self.on_source_selected)
        ttk.Label(sourcebar, textvariable=self.source_diag).pack(side="left", fill="x", expand=True)

        pane = ttk.Panedwindow(self.root, orient="horizontal")
        pane.pack(fill="both", expand=True, padx=8)
        controls = ttk.Frame(pane, width=420)
        viewer = ttk.Frame(pane)
        pane.add(controls, weight=0)
        pane.add(viewer, weight=1)

        self.notebook = ttk.Notebook(controls)
        self.notebook.pack(fill="both", expand=True)
        self.build_source_tab()
        self.build_calibration_tab()
        self.build_curves_tab()
        self.build_publish_tab()
        self.build_notes_tab()

        self.canvas = ImageCanvas(viewer, on_cursor=self.on_cursor, on_left_press=self.canvas_press,
                                  on_left_drag=self.canvas_drag, on_left_release=self.canvas_release,
                                  on_view_changed=self.view_changed)
        self.canvas.pack(fill="both", expand=True)
        ttk.Label(self.root, textvariable=self.status, anchor="w", relief="sunken", padding=(5, 2)).pack(fill="x", padx=8, pady=(4, 8))

    def build_source_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Source")
        ttk.Label(tab, text="Source information", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        self.source_info = tk.Text(tab, height=20, width=48, wrap="word", state="disabled")
        self.source_info.pack(fill="both", expand=True, pady=(6, 0))

    def build_calibration_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Calibration")
        headers = ("", "X axis", "Y axis")
        for col, text in enumerate(headers):
            ttk.Label(tab, text=text, font=("TkDefaultFont", 9, "bold")).grid(row=0, column=col, sticky="w", padx=3, pady=(0, 4))
        rows = [
            ("Label", self.x_name, self.y_name, "entry"),
            ("Unit", self.x_unit, self.y_unit, "unit"),
            ("Semantic role", self.x_role, self.y_role, "role"),
            ("Minimum", self.x_min, self.y_min, "entry"),
            ("Maximum", self.x_max, self.y_max, "entry"),
            ("Scale", self.x_scale, self.y_scale, "scale"),
        ]
        for r, (label, xv, yv, kind) in enumerate(rows, 1):
            ttk.Label(tab, text=label).grid(row=r, column=0, sticky="w", padx=3, pady=3)
            for col, var in ((1, xv), (2, yv)):
                if kind == "unit":
                    w = ttk.Combobox(tab, textvariable=var, values=self.units, state="normal", width=16)
                elif kind == "role":
                    w = ttk.Combobox(tab, textvariable=var, values=self.roles, state="normal", width=16)
                elif kind == "scale":
                    w = ttk.Combobox(tab, textvariable=var, values=("linear", "log"), state="readonly", width=16)
                else:
                    w = ttk.Entry(tab, textvariable=var, width=18)
                w.grid(row=r, column=col, sticky="ew", padx=3, pady=3)
        ttk.Button(tab, text="Apply axis settings", command=lambda: self.commit_axes(True)).grid(row=7, column=0, columnspan=3, sticky="ew", pady=(7, 9))
        cal = ttk.LabelFrame(tab, text="Four-point projective calibration", padding=6)
        cal.grid(row=8, column=0, columnspan=3, sticky="ew")
        for i, corner in enumerate(CORNER_ORDER):
            ttk.Button(cal, text=f"Set {CORNER_LABELS[corner]}", command=lambda c=corner: self.start_corner(c)).grid(row=i // 2, column=i % 2, sticky="ew", padx=3, pady=3)
        ttk.Button(cal, text="Clear calibration", command=self.clear_calibration).grid(row=2, column=0, columnspan=2, sticky="ew", padx=3, pady=3)
        ttk.Label(cal, textvariable=self.cal_status, wraplength=330).grid(row=3, column=0, columnspan=2, sticky="w", padx=3, pady=(5, 0))
        verify = ttk.LabelFrame(tab, text="Calibration verification", padding=6)
        verify.grid(row=9, column=0, columnspan=3, sticky="ew", pady=(8, 0))
        ttk.Button(verify, text="Click image to verify", command=lambda: self.mode.set("verify")).grid(row=0, column=0, columnspan=2, sticky="ew")
        ttk.Label(verify, text="Expected X").grid(row=1, column=0, sticky="w")
        ttk.Entry(verify, textvariable=self.exp_x, width=14).grid(row=1, column=1, sticky="ew")
        ttk.Label(verify, text="Expected Y").grid(row=2, column=0, sticky="w")
        ttk.Entry(verify, textvariable=self.exp_y, width=14).grid(row=2, column=1, sticky="ew")
        ttk.Label(verify, textvariable=self.verify_result, justify="left").grid(row=3, column=0, columnspan=2, sticky="w", pady=(4, 0))
        for col in (1, 2):
            tab.columnconfigure(col, weight=1)

    def build_curves_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Curves")
        family = ttk.LabelFrame(tab, text="Curve family", padding=6)
        family.pack(fill="x")
        ttk.Checkbutton(family, text="This configuration is a numerical curve family", variable=self.family_enabled, command=self.family_changed).grid(row=0, column=0, columnspan=2, sticky="w")
        fields = (("Family quantity", self.family_label), ("Family unit", self.family_unit), ("Semantic role", self.family_role))
        for row, (label, var) in enumerate(fields, 1):
            ttk.Label(family, text=label).grid(row=row, column=0, sticky="w", padx=(0, 6), pady=2)
            values = self.units if label == "Family unit" else self.roles if label == "Semantic role" else ()
            widget = ttk.Combobox(family, textvariable=var, values=values, state="normal", width=24) if values else ttk.Entry(family, textvariable=var, width=27)
            widget.grid(row=row, column=1, sticky="ew", pady=2)
            widget.bind("<FocusOut>", lambda _e: self.persist())
        family.columnconfigure(1, weight=1)

        self.curve_tree = ttk.Treeview(tab, columns=("label", "family", "points"), show="headings", height=12, selectmode="browse")
        self.curve_tree.heading("label", text="Curve")
        self.curve_tree.heading("family", text="Family value")
        self.curve_tree.heading("points", text="Points")
        self.curve_tree.column("label", width=170)
        self.curve_tree.column("family", width=90)
        self.curve_tree.column("points", width=55, anchor="e")
        self.curve_tree.pack(fill="both", expand=True, pady=(8, 4))
        self.curve_tree.bind("<<TreeviewSelect>>", self.on_curve_selected)
        buttons = ttk.Frame(tab)
        buttons.pack(fill="x")
        for text, command in (("New curve", self.new_series), ("Edit", self.edit_series), ("Delete", self.delete_series), ("Show/Hide", self.toggle_visible)):
            ttk.Button(buttons, text=text, command=command).pack(side="left", padx=(0, 4))

        modes = ttk.LabelFrame(tab, text="Image interaction", padding=6)
        modes.pack(fill="x", pady=(8, 0))
        for text, value in (("Add points", "add"), ("Move points", "edit")):
            ttk.Radiobutton(modes, text=text, value=value, variable=self.mode, command=self.mode_changed).pack(side="left", padx=(0, 8))
        ttk.Button(modes, text="Delete selected point", command=self.delete_selected_point).pack(side="left")
        ttk.Label(tab, textvariable=self.selected_label, justify="left", wraplength=360).pack(anchor="w", pady=(6, 0))

        display = ttk.LabelFrame(tab, text="Display and snapping", padding=6)
        display.pack(fill="x", pady=(8, 0))
        ttk.Checkbutton(display, text="Show point numbers", variable=self.show_numbers, command=self.display_changed).grid(row=0, column=0, sticky="w")
        ttk.Checkbutton(display, text="Snap to darkest pixel", variable=self.snap_enabled, command=self.snap_changed).grid(row=1, column=0, sticky="w")
        ttk.Label(display, text="Radius (px)").grid(row=1, column=1, padx=(10, 3))
        spin = ttk.Spinbox(display, from_=0, to=25, textvariable=self.snap_radius, width=5, command=self.snap_changed)
        spin.grid(row=1, column=2)
        spin.bind("<FocusOut>", lambda _e: self.snap_changed())

    def build_publish_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Publish")
        ttk.Label(tab, text="Dataset publication", font=("TkDefaultFont", 10, "bold")).grid(row=0, column=0, columnspan=2, sticky="w")
        ttk.Label(tab, text="Output Dataset ID").grid(row=1, column=0, sticky="w", pady=(8, 3))
        ttk.Entry(tab, textvariable=self.output_dataset_id, width=36).grid(row=1, column=1, sticky="ew", pady=(8, 3))
        ttk.Label(tab, text="Display name").grid(row=2, column=0, sticky="w", pady=3)
        ttk.Entry(tab, textvariable=self.output_display_name, width=36).grid(row=2, column=1, sticky="ew", pady=3)
        self.publish_contract = tk.StringVar(value="table.generic")
        ttk.Label(tab, text="Contract").grid(row=3, column=0, sticky="w", pady=3)
        ttk.Label(tab, textvariable=self.publish_contract).grid(row=3, column=1, sticky="w", pady=3)
        ttk.Label(tab, text="Publishing writes the CSV scientific artifact and registers the Canonical Dataset in one transaction.", wraplength=355).grid(row=4, column=0, columnspan=2, sticky="w", pady=(8, 8))
        ttk.Button(tab, text="Publish Dataset", command=self.publish_dataset).grid(row=5, column=0, columnspan=2, sticky="ew")
        self.publish_result = tk.StringVar()
        ttk.Label(tab, textvariable=self.publish_result, wraplength=360, justify="left").grid(row=6, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Button(tab, text="Pixel / calibration uncertainty…", command=lambda: UncertaintyDialog(self) if self.current_doc_id else None).grid(row=7, column=0, columnspan=2, sticky="ew", pady=8)
        tab.columnconfigure(1, weight=1)
        for var in (self.output_dataset_id, self.output_display_name):
            var.trace_add("write", lambda *_: self.persist_later())

    def build_notes_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Notes")
        ttk.Label(tab, text="Configuration notes (plain UTF-8 text)").pack(anchor="w")
        self.notes = tk.Text(tab, wrap="word", height=24)
        self.notes.pack(fill="both", expand=True, pady=(6, 0))
        self.notes.bind("<FocusOut>", lambda _e: self.persist())

    def bind_keys(self):
        self.root.bind_all("<Control-z>", lambda _e: self.undo())
        self.root.bind_all("<Control-y>", lambda _e: self.redo())
        self.root.bind_all("<Delete>", lambda _e: self.delete_selected_point())

    def refresh_configuration_selector(self):
        labels = []
        self.label_to_doc = {}
        for doc_id, cfg in self.documents.items():
            label = cfg.get("name") or doc_id
            display = f"{label}  [{doc_id}]"
            labels.append(display)
            self.label_to_doc[display] = doc_id
        self.config_combo.configure(values=labels)
        if self.current_doc_id:
            for display, did in self.label_to_doc.items():
                if did == self.current_doc_id:
                    self.config_var.set(display)
                    break
        elif not labels:
            self.config_var.set("")

    def on_configuration_selected(self, _event=None):
        doc_id = self.label_to_doc.get(self.config_var.get())
        if doc_id and doc_id != self.current_doc_id:
            self.open_document(doc_id)

    def new_config(self):
        name = simpledialog.askstring(APP_NAME, "Configuration name:", parent=self.root)
        if not name or not name.strip():
            return
        cfg = self.new_configuration(name.strip())
        payload = json.dumps(cfg, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        try:
            doc_id, doc_sha = self.parse_document_result(self.rpc.call("DOC_CREATE", payload))
        except RpcError as exc:
            messagebox.showerror(APP_NAME, f"Unable to create configuration:\n{exc}")
            return
        self.documents[doc_id] = cfg
        self.document_sha[doc_id] = doc_sha
        self.refresh_configuration_selector()
        self.open_document(doc_id)

    def rename_config(self):
        if not self.current_doc_id:
            return
        name = simpledialog.askstring(APP_NAME, "Configuration name:", initialvalue=self.config.get("name", ""), parent=self.root)
        if not name or not name.strip():
            return
        self.snapshot()
        self.config["name"] = name.strip()
        if not self.output_display_name.get().strip():
            self.output_display_name.set(name.strip())
        self.persist()
        self.refresh_configuration_selector()

    def duplicate_config(self):
        if not self.current_doc_id:
            return
        cfg = self.serialize_configuration()
        cfg["configuration_id"] = "digcfg_" + uuid.uuid4().hex
        cfg["name"] = cfg.get("name", "Configuration") + " copy"
        cfg["publication"] = {"dataset_id": "", "display_name": cfg["name"]}
        payload = json.dumps(cfg, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        try:
            doc_id, doc_sha = self.parse_document_result(self.rpc.call("DOC_CREATE", payload))
        except RpcError as exc:
            messagebox.showerror(APP_NAME, f"Unable to duplicate configuration:\n{exc}")
            return
        self.documents[doc_id] = cfg
        self.document_sha[doc_id] = doc_sha
        self.refresh_configuration_selector()
        self.open_document(doc_id)

    def delete_config(self):
        if not self.current_doc_id:
            return
        if not messagebox.askyesno(APP_NAME, f"Delete configuration '{self.config.get('name', self.current_doc_id)}'?\n\nThis removes its Session-persisted digitizer state. Published Datasets are not deleted."):
            return
        doc_id = self.current_doc_id
        try:
            self.rpc.call("DOC_DELETE", doc_id, self.session_token)
        except RpcError as exc:
            messagebox.showerror(APP_NAME, f"Unable to delete configuration:\n{exc}")
            return
        self.documents.pop(doc_id, None)
        self.document_sha.pop(doc_id, None)
        self.current_doc_id = None
        self.config = {}
        self.project = Project()
        self.image = None
        if hasattr(self, "canvas"):
            self.canvas.original_image = None
            self.canvas.delete("all")
        self.refresh_configuration_selector()
        if self.documents:
            self.open_document(next(iter(self.documents)))
        else:
            self.clear_ui_no_config()

    def clear_ui_no_config(self):
        self.source_var.set("")
        self.source_diag.set("Create a configuration to begin.")
        self.status.set("No digitizer configuration is open.")
        self.refresh_source_info()
        self.refresh_curve_tree()

    def open_document(self, doc_id: str):
        cfg = copy.deepcopy(self.documents[doc_id])
        self.current_doc_id = doc_id
        self.config = cfg
        self.project = self.config_to_project(cfg)
        self.active_series_id = self.project.series[0].id if self.project.series else None
        self.selected_point_id = None
        self.undo_stack.clear()
        self.redo_stack.clear()
        self.sync_controls_from_config(reload_source=True)
        self.refresh_configuration_selector()
        self.refresh_curve_tree()
        self.redraw()

    def sync_controls_from_config(self, reload_source=True):
        self.loading_ui = True
        try:
            x = self.config.get("axes", {}).get("x", {})
            y = self.config.get("axes", {}).get("y", {})
            for var, value in (
                (self.x_name, x.get("name", "X")), (self.x_unit, x.get("unit", "")), (self.x_role, x.get("semantic_role", "independent")),
                (self.x_min, fmt(float(x.get("minimum", 0)))), (self.x_max, fmt(float(x.get("maximum", 1)))), (self.x_scale, x.get("scale", "linear")),
                (self.y_name, y.get("name", "Y")), (self.y_unit, y.get("unit", "")), (self.y_role, y.get("semantic_role", "measured")),
                (self.y_min, fmt(float(y.get("minimum", 0)))), (self.y_max, fmt(float(y.get("maximum", 1)))), (self.y_scale, y.get("scale", "linear")),
            ):
                var.set(value)
            fam = self.config.get("family", {})
            self.family_enabled.set(bool(fam.get("enabled", False)))
            self.family_label.set(fam.get("quantity_label", "Family parameter"))
            self.family_unit.set(fam.get("unit", ""))
            self.family_role.set(fam.get("semantic_role", "family"))
            self.publish_contract.set("curve_family.table" if self.family_enabled.get() else "table.generic")
            pub = self.config.get("publication", {})
            self.output_dataset_id.set(pub.get("dataset_id", ""))
            self.output_display_name.set(pub.get("display_name", self.config.get("name", "")))
            self.show_numbers.set(bool(self.config.get("display", {}).get("show_point_numbers", False)))
            self.snap_enabled.set(bool(self.config.get("snap", {}).get("enabled", False)))
            self.snap_radius.set(max(0, int(self.config.get("snap", {}).get("radius", 3))))
            self.notes.delete("1.0", "end")
            self.notes.insert("1.0", self.config.get("notes", ""))
            source_id = self.config.get("source", {}).get("dataset_id", "")
            self.source_var.set(source_id)
            if reload_source:
                self.load_current_source()
            self.update_cal_status()
            self.update_selected()
        finally:
            self.loading_ui = False

    def on_source_selected(self, _event=None):
        if self.loading_ui or not self.current_doc_id:
            return
        selected = self.source_var.get().strip()
        current = self.config.get("source", {}).get("dataset_id", "")
        if current and selected != current:
            self.source_var.set(current)
            messagebox.showwarning(APP_NAME, "A calibrated configuration cannot be silently reassociated with another image. Create a new configuration for a different source image.")
            return
        if not selected:
            return
        if current == selected:
            return
        try:
            info = self.fetch_source(selected)
            image = self.open_dataset_image(info["path"])
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Unable to open source Image Dataset:\n{exc}")
            self.source_var.set(current)
            return
        if not self.confirm_source_selection(selected, info, image):
            self.source_var.set(current)
            self.status.set("Source selection cancelled.")
            return
        self.snapshot()
        w, h = image.size
        self.config["source"] = {
            "dataset_id": selected,
            "resource_identity": "sha256:" + info["sha256"],
            "sha256": info["sha256"],
            "format": info.get("format", ""),
            "media_type": info.get("media_type", ""),
            "width": w,
            "height": h,
        }
        self.project.image_width, self.project.image_height = w, h
        self.set_image(image)
        self.source_metadata = info.get("metadata", {})
        self.stale_source = False
        self.source_diag.set("Source linked by Dataset ID and SHA-256.")
        self.refresh_source_info()
        if not self.output_dataset_id.get().strip():
            self.output_dataset_id.set(slug_id(self.config.get("name", "digitized.curves")))
        if not self.output_display_name.get().strip():
            self.output_display_name.set(self.config.get("name", "Digitized curves"))
        self.persist()

    def fetch_source(self, dataset_id: str) -> dict:
        payload = self.rpc.call("SOURCE", dataset_id)
        info = {"metadata": {}}
        for kind, fields in parse_records(payload):
            if kind == "METADATA":
                info["metadata"][fields[0]] = fields[1]
            elif fields:
                info[kind.lower()] = fields[0]
        return info

    @staticmethod
    def open_dataset_image(path: str):
        try:
            image = Image.open(path)
            image.load()
            return image.convert("RGB")
        except (OSError, UnidentifiedImageError) as exc:
            raise RuntimeError(f"The canonical Image Dataset payload cannot be decoded by Pillow: {exc}") from exc

    def confirm_source_selection(self, dataset_id: str, info: dict, image) -> bool:
        if os.environ.get("GX_CURVE_DIGITIZER_TEST_SCENARIO", "").strip():
            return True
        dialog = SourcePreviewDialog(self.root, dataset_id, image, info)
        self.root.wait_window(dialog)
        return bool(dialog.result)

    def load_current_source(self):
        source = self.config.get("source", {})
        dataset_id = source.get("dataset_id", "")
        self.source_metadata = {}
        self.stale_source = False
        if not dataset_id:
            self.image = None
            self.source_diag.set("Select an Image Dataset for this new configuration.")
            self.refresh_source_info()
            return
        if dataset_id not in self.datasets:
            self.image = None
            self.stale_source = True
            self.source_diag.set("SOURCE MISSING — the saved Dataset ID is not present in this Session.")
            self.refresh_source_info()
            return
        try:
            info = self.fetch_source(dataset_id)
            image = self.open_dataset_image(info["path"])
        except Exception as exc:
            self.image = None
            self.stale_source = True
            self.source_diag.set(f"SOURCE ERROR — {exc}")
            self.refresh_source_info()
            return
        self.source_metadata = info.get("metadata", {})
        expected = source.get("sha256", "").lower()
        actual = info.get("sha256", "").lower()
        if expected and actual and expected != actual:
            self.stale_source = True
            self.source_diag.set("STALE SOURCE — image SHA-256 changed; calibration and publication are disabled.")
        else:
            self.source_diag.set("Source Dataset verified by SHA-256.")
        self.set_image(image, restore_view=True)
        self.refresh_source_info()

    def set_image(self, image, restore_view=False):
        self.image = image
        self.gray_image = image.convert("L")
        self.canvas.set_image(image)
        if restore_view:
            view = self.config.get("view", {})
            if all(k in view for k in ("scale", "offset_x", "offset_y")):
                def restore():
                    try:
                        self.canvas.scale = max(self.canvas.min_scale, min(self.canvas.max_scale, float(view["scale"])))
                        self.canvas.offset_x = float(view["offset_x"])
                        self.canvas.offset_y = float(view["offset_y"])
                        self.canvas.request_render()
                        self.redraw()
                    except Exception:
                        pass
                self.canvas.after_idle(restore)
        self.redraw()

    def refresh_source_info(self):
        source = self.config.get("source", {}) if self.config else {}
        lines = []
        if source.get("dataset_id"):
            lines.append(f"Source Dataset: {source['dataset_id']}")
        for key, label in (("source.original_filename", "Source file"), ("source.document", "Source document"), ("document.title", "Document"), ("page.number", "Page"), ("source.page", "Page"), ("manufacturer", "Manufacturer"), ("source.url", "Source URL")):
            value = self.source_metadata.get(key)
            if value and f"{label}: {value}" not in lines:
                lines.append(f"{label}: {value}")
        width = self.source_metadata.get("image.width_px") or source.get("width")
        height = self.source_metadata.get("image.height_px") or source.get("height")
        if width and height:
            lines.append(f"Image: {width} × {height}")
        image_format = self.source_metadata.get("image.format") or source.get("format")
        if image_format:
            lines.append(f"Format: {image_format}")
        if source.get("sha256"):
            lines.append(f"SHA-256: {source['sha256']}")
        if self.source_metadata:
            lines.append("\nAvailable Dataset Metadata:")
            for key in sorted(self.source_metadata):
                value = self.source_metadata[key]
                if len(str(value)) > 220:
                    value = str(value)[:217] + "..."
                lines.append(f"{key} = {value}")
        self.source_info.configure(state="normal")
        self.source_info.delete("1.0", "end")
        self.source_info.insert("1.0", "\n".join(lines) if lines else "No source is associated with this configuration.")
        self.source_info.configure(state="disabled")

    def commit_axes(self, push=True):
        try:
            x = AxisConfig(self.x_name.get().strip() or "X", self.x_unit.get().strip(), float(self.x_min.get()), float(self.x_max.get()), self.x_scale.get())
            y = AxisConfig(self.y_name.get().strip() or "Y", self.y_unit.get().strip(), float(self.y_min.get()), float(self.y_max.get()), self.y_scale.get())
            x.validate(); y.validate()
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Invalid axis configuration:\n{exc}")
            return False
        changed = x.to_dict() != self.project.x_axis.to_dict() or y.to_dict() != self.project.y_axis.to_dict()
        if changed and push:
            self.snapshot()
        self.project.x_axis, self.project.y_axis = x, y
        self.project.recalculate_all_points()
        self.update_cal_status()
        self.redraw()
        if changed or push:
            self.persist()
        return True

    def start_corner(self, corner):
        if not self.require_working_source():
            return
        self.pending_corner = corner
        self.mode.set("calibrate")
        self.status.set(f"Click the image at calibration corner {CORNER_LABELS[corner]}.")

    def clear_calibration(self):
        if not self.project.calibration.pixels:
            return
        self.snapshot()
        self.project.calibration.clear()
        self.project.recalculate_all_points()
        self.update_cal_status()
        self.redraw()
        self.persist()

    def update_cal_status(self):
        if not self.project.calibration.is_complete():
            self.cal_status.set(f"Calibration points: {len(self.project.calibration.pixels)}/4")
            return
        try:
            _H, cond = self.project.calibration.matrix()
            rms = self.project.calibration.reprojection_rms()
            self.cal_status.set(f"Calibration ready · homography condition {cond:.3g} · corner RMS {rms:.3g}")
        except CalibrationError as exc:
            self.cal_status.set(f"Calibration invalid: {exc}")

    def family_changed(self):
        if self.loading_ui:
            return
        self.snapshot()
        self.publish_contract.set("curve_family.table" if self.family_enabled.get() else "table.generic")
        self.persist()

    def active_series(self):
        return self.project.find_series(self.active_series_id)

    def refresh_curve_tree(self):
        if not hasattr(self, "curve_tree"):
            return
        selected = self.active_series_id
        for item in self.curve_tree.get_children():
            self.curve_tree.delete(item)
        for series in self.project.series:
            family = series.parameter_value
            if family and series.parameter_unit:
                family += f" {series.parameter_unit}"
            label = series.name + (" (hidden)" if not series.visible else "")
            self.curve_tree.insert("", "end", iid=series.id, values=(label, family, len(series.points)))
        if selected and self.curve_tree.exists(selected):
            self.curve_tree.selection_set(selected)

    def on_curve_selected(self, _event=None):
        selected = self.curve_tree.selection()
        if selected:
            self.active_series_id = selected[0]
            self.selected_point_id = None
            self.update_selected()
            self.redraw()

    def new_series(self):
        if not self.current_doc_id:
            return
        dialog = SeriesDialog(self.root, family_name=self.family_label.get().strip() or "Family parameter", family_unit=self.family_unit.get().strip())
        self.root.wait_window(dialog)
        if not dialog.result:
            return
        self.snapshot()
        result = dialog.result
        series = Series(name=result["name"], parameter_name=self.family_label.get().strip() or "Family parameter",
                        parameter_value=result["parameter_value"], parameter_unit=result["parameter_unit"],
                        color=SERIES_COLORS[len(self.project.series) % len(SERIES_COLORS)])
        self.project.series.append(series)
        self.active_series_id = series.id
        self.refresh_curve_tree(); self.redraw(); self.persist()

    def edit_series(self):
        series = self.active_series()
        if not series:
            return
        dialog = SeriesDialog(self.root, series, self.family_label.get().strip() or "Family parameter", self.family_unit.get().strip())
        self.root.wait_window(dialog)
        if not dialog.result:
            return
        self.snapshot()
        series.name = dialog.result["name"]
        series.parameter_name = self.family_label.get().strip() or "Family parameter"
        series.parameter_value = dialog.result["parameter_value"]
        series.parameter_unit = dialog.result["parameter_unit"]
        self.refresh_curve_tree(); self.redraw(); self.persist()

    def delete_series(self):
        series = self.active_series()
        if not series or not messagebox.askyesno(APP_NAME, f"Delete curve '{series.name}' and its {len(series.points)} points?"):
            return
        self.snapshot()
        self.project.series = [s for s in self.project.series if s.id != series.id]
        self.active_series_id = self.project.series[0].id if self.project.series else None
        self.selected_point_id = None
        self.refresh_curve_tree(); self.update_selected(); self.redraw(); self.persist()

    def toggle_visible(self):
        series = self.active_series()
        if not series:
            return
        self.snapshot()
        series.visible = not series.visible
        self.refresh_curve_tree(); self.redraw(); self.persist()

    def require_working_source(self):
        if not self.current_doc_id:
            messagebox.showinfo(APP_NAME, "Create a digitizer configuration first.")
            return False
        if self.image is None:
            messagebox.showerror(APP_NAME, "A source Image Dataset is required.")
            return False
        if self.stale_source:
            messagebox.showerror(APP_NAME, "The source Image Dataset changed or is missing. Existing calibration cannot be reused silently.")
            return False
        return True

    def canvas_press(self, x, y):
        if not self.require_working_source():
            return
        mode = self.mode.get()
        if mode == "calibrate":
            if self.pending_corner:
                self.snapshot()
                self.project.calibration.set_corner(self.pending_corner, x, y)
                self.project.recalculate_all_points()
                self.pending_corner = None
                self.mode.set("add")
                self.update_cal_status(); self.redraw(); self.persist()
        elif mode == "verify":
            self.verify(x, y)
        elif mode == "add":
            self.add_point(x, y)
        elif mode == "edit":
            self.begin_drag(x, y)

    def canvas_drag(self, x, y):
        if not self.dragging:
            return
        point = self.selected_point()
        if not point:
            return
        sx, sy = self.snap(x, y)
        point.manual_pixel_x, point.manual_pixel_y = x, y
        point.pixel_x, point.pixel_y = sx, sy
        self.project.update_point_calibration(point)
        self.update_selected(); self.redraw()

    def canvas_release(self, _x, _y):
        if self.dragging and self.drag_snapshot is not None:
            self.undo_stack.append(self.drag_snapshot)
            self.undo_stack = self.undo_stack[-100:]
            self.redo_stack.clear()
            self.drag_snapshot = None
            self.dragging = False
            self.refresh_curve_tree(); self.persist()

    def verify(self, x, y):
        try:
            cx, cy = self.project.pixel_to_calibrated(x, y)
        except CalibrationError as exc:
            messagebox.showerror(APP_NAME, str(exc))
            return
        lines = [f"Pixel: {x:.3f}, {y:.3f}", f"Calculated X: {fmt(cx)} {self.project.x_axis.unit}", f"Calculated Y: {fmt(cy)} {self.project.y_axis.unit}"]
        for label, text, value, unit in (("ΔX", self.exp_x.get().strip(), cx, self.project.x_axis.unit), ("ΔY", self.exp_y.get().strip(), cy, self.project.y_axis.unit)):
            if text:
                try:
                    lines.append(f"{label}: {fmt(value - float(text))} {unit}")
                except ValueError:
                    lines.append(f"{label}: invalid expected value")
        self.verify_result.set("\n".join(lines))

    def add_point(self, x, y):
        series = self.active_series()
        if not series:
            messagebox.showinfo(APP_NAME, "Create or select an active curve first.")
            return
        self.snapshot()
        sx, sy = self.snap(x, y)
        point = DigitizedPoint(manual_pixel_x=x, manual_pixel_y=y, pixel_x=sx, pixel_y=sy)
        self.project.update_point_calibration(point)
        series.points.append(point)
        self.selected_point_id = point.id
        self.refresh_curve_tree(); self.update_selected(); self.redraw(); self.persist()

    def begin_drag(self, x, y):
        series = self.active_series()
        if not series:
            return
        cx, cy = self.canvas.image_to_canvas(x, y)
        best, best_distance = None, None
        for point in series.points:
            px, py = self.canvas.image_to_canvas(point.pixel_x, point.pixel_y)
            distance = math.hypot(px - cx, py - cy)
            if distance <= 10 and (best_distance is None or distance < best_distance):
                best, best_distance = point, distance
        self.selected_point_id = best.id if best else None
        self.dragging = bool(best)
        self.drag_snapshot = self.serialize_configuration() if best else None
        self.update_selected(); self.redraw()

    def selected_point(self):
        series = self.active_series()
        return next((p for p in series.points if p.id == self.selected_point_id), None) if series else None

    def delete_selected_point(self):
        series = self.active_series(); point = self.selected_point()
        if not series or not point:
            return
        self.snapshot()
        series.points = [p for p in series.points if p.id != point.id]
        self.selected_point_id = None
        self.refresh_curve_tree(); self.update_selected(); self.redraw(); self.persist()

    def snap(self, x, y):
        if not self.snap_enabled.get() or self.gray_image is None:
            return x, y
        try:
            radius = max(0, int(self.snap_radius.get()))
        except Exception:
            radius = 3
        if radius == 0:
            return x, y
        width, height = self.gray_image.size
        cx, cy = int(round(x)), int(round(y))
        x0, y0 = max(0, cx - radius), max(0, cy - radius)
        x1, y1 = min(width, cx + radius + 1), min(height, cy + radius + 1)
        patch = np.asarray(self.gray_image.crop((x0, y0, x1, y1)), dtype=np.uint8)
        candidates = np.argwhere(patch == patch.min())
        best, best_distance = None, None
        for local_y, local_x in candidates:
            px, py = x0 + int(local_x), y0 + int(local_y)
            distance = (px - x) ** 2 + (py - y) ** 2
            if best_distance is None or distance < best_distance:
                best, best_distance = (float(px), float(py)), distance
        return best or (x, y)

    def redraw(self):
        if not hasattr(self, "canvas"):
            return
        self.canvas.delete("overlay")
        if not self.image:
            return
        for corner, point in self.project.calibration.pixels.items():
            x, y = self.canvas.image_to_canvas(*point)
            radius = 6
            self.canvas.create_rectangle(x-radius, y-radius, x+radius, y+radius, outline="cyan", width=2, tags=("overlay",))
            self.canvas.create_text(x+9, y-9, text=CORNER_LABELS[corner], fill="cyan", anchor="sw", tags=("overlay",))
        for series in self.project.series:
            if not series.visible:
                continue
            for index, point in enumerate(series.points, 1):
                x, y = self.canvas.image_to_canvas(point.pixel_x, point.pixel_y)
                selected = series.id == self.active_series_id and point.id == self.selected_point_id
                radius = 6 if selected else 4
                width = 3 if selected else 2
                self.canvas.create_oval(x-radius, y-radius, x+radius, y+radius, outline=series.color, width=width, tags=("overlay",))
                if self.show_numbers.get():
                    self.canvas.create_text(x+radius+3, y-radius-2, text=str(index), fill=series.color, anchor="sw", tags=("overlay",))

    def on_cursor(self, x, y):
        if x is None:
            self.status.set(f"Mode: {self.mode.get()}")
            return
        text = f"Pixel X,Y: {x:.3f}, {y:.3f}"
        if self.project.calibration_ready():
            try:
                cx, cy = self.project.pixel_to_calibrated(x, y)
                text += f"    |    {self.project.x_axis.name}: {fmt(cx)} {self.project.x_axis.unit}    |    {self.project.y_axis.name}: {fmt(cy)} {self.project.y_axis.unit}"
            except CalibrationError:
                pass
        self.status.set(text + f"    |    Mode: {self.mode.get()}")

    def update_selected(self):
        point = self.selected_point()
        if not point:
            self.selected_label.set("No point selected.")
            return
        lines = [f"Manual click: {point.manual_pixel_x:.3f}, {point.manual_pixel_y:.3f} px", f"Stored pixel: {point.pixel_x:.3f}, {point.pixel_y:.3f} px"]
        if point.calibrated_x is not None:
            lines += [f"X = {fmt(point.calibrated_x)} {self.project.x_axis.unit}", f"Y = {fmt(point.calibrated_y)} {self.project.y_axis.unit}"]
        self.selected_label.set("\n".join(lines))

    def mode_changed(self):
        self.pending_corner = None
        self.selected_point_id = None
        self.dragging = False
        self.drag_snapshot = None
        self.update_selected(); self.redraw()

    def display_changed(self):
        if self.loading_ui:
            return
        self.snapshot()
        self.project.show_point_numbers = bool(self.show_numbers.get())
        self.redraw(); self.persist()

    def snap_changed(self):
        if self.loading_ui:
            return
        try:
            radius = max(0, int(self.snap_radius.get()))
        except Exception:
            radius = 3
            self.snap_radius.set(3)
        self.snapshot()
        self.project.snap_enabled = bool(self.snap_enabled.get())
        self.project.snap_radius = radius
        self.persist()

    def view_changed(self):
        self.redraw()
        self.persist_later()

    def persist_later(self):
        if self.loading_ui:
            return
        if hasattr(self, "_persist_after") and self._persist_after:
            try:
                self.root.after_cancel(self._persist_after)
            except tk.TclError:
                pass
        self._persist_after = self.root.after(350, self.persist)

    def publish_dataset(self):
        if not self.require_working_source():
            return
        if not self.commit_axes(False):
            return
        if not self.project.calibration_ready():
            messagebox.showerror(APP_NAME, "A complete valid four-point calibration is required before publication.")
            return
        if not self.project.series:
            messagebox.showerror(APP_NAME, "Create at least one curve before publication.")
            return
        self.project.recalculate_all_points()
        mode = "family" if self.family_enabled.get() else "generic"
        rows = []
        for series in self.project.series:
            family = series.parameter_value.strip()
            if mode == "family":
                try:
                    float(family)
                except ValueError:
                    messagebox.showerror(APP_NAME, f"Curve '{series.name}' needs a numerical family value for curve_family.table publication.")
                    return
                declared_family_unit = self.family_unit.get().strip()
                if series.parameter_unit.strip() and series.parameter_unit.strip() != declared_family_unit:
                    messagebox.showerror(APP_NAME, f"Curve '{series.name}' uses family unit '{series.parameter_unit}', which differs from the configured family unit '{declared_family_unit}'.")
                    return
            for point_index, point in enumerate(series.points):
                if point.calibrated_x is None or point.calibrated_y is None:
                    continue
                rows.append("\t".join((b64e(series.id), b64e(series.name), str(point_index), format(point.calibrated_x, ".17g"), format(point.calibrated_y, ".17g"), family, b64e(point.id))))
        if not rows:
            messagebox.showerror(APP_NAME, "There are no calibrated digitized points to publish.")
            return
        dataset_id = self.output_dataset_id.get().strip()
        if not dataset_id:
            dataset_id = slug_id(self.config.get("name", "digitized.curves"))
            self.output_dataset_id.set(dataset_id)
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", dataset_id):
            messagebox.showerror(APP_NAME, "Dataset ID must start with a letter and contain only letters, digits, underscore, dot or hyphen.")
            return
        display_name = self.output_display_name.get().strip() or self.config.get("name", dataset_id)
        source = self.config.get("source", {})
        if not self.persist():
            return
        uncertainty = self.config.get("uncertainty", {}).get("mode", "none") != "none"
        extra = [self.document_sha[self.current_doc_id]] if uncertainty else []
        try:
            result = self.rpc.call(
                "PUBLISH", self.session_token, self.current_doc_id, dataset_id, display_name, mode,
                self.project.x_axis.name, self.project.x_axis.unit, self.x_role.get().strip() or "independent",
                self.project.y_axis.name, self.project.y_axis.unit, self.y_role.get().strip() or "measured",
                self.family_label.get().strip() or "Family parameter", self.family_unit.get().strip(), self.family_role.get().strip() or "family",
                source.get("dataset_id", ""), source.get("sha256", ""), "four_point_homography", self.project.x_axis.scale, self.project.y_axis.scale,
                self.config.get("name", "Curve Digitalizer configuration"), "\n".join(rows), *extra
            )
        except RpcError as exc:
            messagebox.showerror(APP_NAME, f"Dataset publication failed:\n{exc}")
            return
        dataset, path, sha, contract = result.split("\t")
        self.publish_result.set(f"Published {dataset}\nContract: {contract}\nCSV artifact: {path}\nSHA-256: {sha}")
        self.persist()

    def close(self):
        try:
            self.persist()
        finally:
            self.root.destroy()

    # Deterministic GUI exercise used only by the packaged integration test.
    def run_test_scenario(self, scenario: str):
        # Automated packaged validation must never block on a modal dialog.
        # Interactive use retains the normal message boxes.
        captured = []
        original_showerror = messagebox.showerror
        original_showwarning = messagebox.showwarning
        original_showinfo = messagebox.showinfo
        messagebox.showerror = lambda *a, **k: captured.append("ERROR: " + " | ".join(str(x) for x in a))
        messagebox.showwarning = lambda *a, **k: captured.append("WARNING: " + " | ".join(str(x) for x in a))
        messagebox.showinfo = lambda *a, **k: captured.append("INFO: " + " | ".join(str(x) for x in a))
        try:
            if scenario == "create_and_publish":
                self._test_create_and_publish()
            elif scenario == "reopen_and_family":
                self._test_reopen_and_family()
            elif scenario == "expect_stale":
                self._test_expect_stale()
            elif scenario == "expect_missing":
                self._test_expect_missing()
            else:
                raise RuntimeError(f"Unknown test scenario: {scenario}")
            marker = os.environ.get("GX_CURVE_DIGITIZER_TEST_MARKER", "")
            if marker:
                Path(marker).write_text("PASS\n", encoding="utf-8")
        except Exception as exc:
            marker = os.environ.get("GX_CURVE_DIGITIZER_TEST_MARKER", "")
            if marker:
                detail = ("; ".join(captured) + "; ") if captured else ""
                Path(marker).write_text(f"FAIL: {detail}{exc}\n", encoding="utf-8")
        finally:
            messagebox.showerror = original_showerror
            messagebox.showwarning = original_showwarning
            messagebox.showinfo = original_showinfo
            self.root.after(100, self.close)

    def _test_create_and_publish(self):
        if not self.documents:
            cfg = self.new_configuration("Automated curve digitizer validation")
            doc_id, doc_sha = self.parse_document_result(self.rpc.call("DOC_CREATE", json.dumps(cfg, separators=(",", ":"))))
            self.documents[doc_id] = cfg
            self.document_sha[doc_id] = doc_sha
            self.open_document(doc_id)
        if not self.datasets:
            raise RuntimeError("No image Dataset available")
        original_doc = self.current_doc_id
        if not self.config.get("source", {}).get("dataset_id"):
            did = sorted(self.datasets)[0]
            self.source_var.set(did)
            self.on_source_selected()
        if self.stale_source or self.image is None:
            raise RuntimeError("Source image is unavailable or stale")
        width, height = self.image.size
        self.x_name.set("Voltage"); self.x_unit.set("V"); self.x_role.set("independent"); self.x_min.set("1"); self.x_max.set("100"); self.x_scale.set("log")
        self.y_name.set("Current"); self.y_unit.set("mA"); self.y_role.set("measured"); self.y_min.set("0"); self.y_max.set("10"); self.y_scale.set("linear")
        if not self.commit_axes(True):
            raise RuntimeError("Axis configuration failed")
        self.project.calibration.clear()
        for corner, xy in zip(CORNER_ORDER, ((10, height-10), (width-10, height-10), (10, 10), (width-10, 10))):
            self.project.calibration.set_corner(corner, *xy)
        self.project.series = []
        for value, ypos in (("-2", 0.35), ("-4", 0.65)):
            series = Series(name=f"Vg = {value} V", parameter_name="Grid voltage", parameter_value=value, parameter_unit="V")
            for frac in (0.15, 0.45, 0.8):
                point = DigitizedPoint(manual_pixel_x=width*frac, manual_pixel_y=height*ypos, pixel_x=width*frac, pixel_y=height*ypos)
                self.project.update_point_calibration(point)
                series.points.append(point)
            self.project.series.append(series)
        self.active_series_id = self.project.series[0].id
        self.family_enabled.set(False)
        self.output_dataset_id.set("digitized.validation.generic")
        self.output_display_name.set("Digitizer generic validation")
        self.persist(); self.refresh_curve_tree(); self.publish_dataset()
        if "Published" not in self.publish_result.get():
            raise RuntimeError("Generic publication did not complete")
        first = self.publish_result.get()
        first_path = next(line.split(": ", 1)[1] for line in first.splitlines() if line.startswith("CSV artifact:"))
        first_sha = next(line.split(": ", 1)[1] for line in first.splitlines() if line.startswith("SHA-256:"))

        # Edit one point and republish. Dataset identity/target must remain stable
        # while the numerical artifact and its hash change.
        point = self.project.series[0].points[0]
        point.pixel_x += 3.0
        point.manual_pixel_x += 3.0
        self.project.update_point_calibration(point)
        self.persist(); self.publish_dataset()
        second = self.publish_result.get()
        second_path = next(line.split(": ", 1)[1] for line in second.splitlines() if line.startswith("CSV artifact:"))
        second_sha = next(line.split(": ", 1)[1] for line in second.splitlines() if line.startswith("SHA-256:"))
        if first_path != second_path or first_sha == second_sha:
            raise RuntimeError("Republish did not preserve Dataset target and update numerical content")

        # Exercise multiple independent configurations for the same source.
        self.duplicate_config()
        if self.current_doc_id == original_doc:
            raise RuntimeError("Configuration duplication did not create a new Session object")
        self.config["name"] = "Independent second configuration"
        self.x_max.set("50")
        if not self.commit_axes(False):
            raise RuntimeError("Second configuration axis edit failed")
        self.project.series = self.project.series[:1]
        self.project.calibration.clear()
        self.persist()
        self.open_document(original_doc)
        if self.project.x_axis.maximum != 100.0 or len(self.project.series) != 2 or not self.project.calibration_ready():
            raise RuntimeError("Multiple configurations cross-contaminated one another")

    def _test_reopen_and_family(self):
        candidates = [(doc_id, cfg) for doc_id, cfg in self.documents.items() if cfg.get("name") == "Automated curve digitizer validation"]
        if len(candidates) != 1:
            raise RuntimeError("Original persisted configuration was not restored uniquely")
        doc_id, _cfg = candidates[0]
        self.open_document(doc_id)
        if not self.project.calibration_ready() or len(self.project.series) != 2 or any(len(series.points) != 3 for series in self.project.series):
            raise RuntimeError("Persisted calibration/curves/points were not restored")
        self.family_enabled.set(True)
        self.family_label.set("Grid voltage")
        self.family_unit.set("V")
        self.family_role.set("family")
        self.publish_contract.set("curve_family.table")
        self.output_dataset_id.set("digitized.validation.family")
        self.output_display_name.set("Digitizer family validation")
        self.persist(); self.publish_dataset()
        if "curve_family.table" not in self.publish_result.get():
            raise RuntimeError("Curve-family publication did not complete")

    def _test_expect_stale(self):
        candidates = [(doc_id, cfg) for doc_id, cfg in self.documents.items() if cfg.get("name") == "Automated curve digitizer validation"]
        if len(candidates) != 1:
            raise RuntimeError("Persisted configuration unavailable for stale-source test")
        self.open_document(candidates[0][0])
        if not self.stale_source or "STALE SOURCE" not in self.source_diag.get():
            raise RuntimeError("Changed source image was not diagnosed as stale")

    def _test_expect_missing(self):
        candidates = [(doc_id, cfg) for doc_id, cfg in self.documents.items() if cfg.get("name") == "Automated curve digitizer validation"]
        if len(candidates) != 1:
            raise RuntimeError("Persisted configuration unavailable for missing-source test")
        self.open_document(candidates[0][0])
        if not self.stale_source or "SOURCE MISSING" not in self.source_diag.get():
            raise RuntimeError("Missing source Dataset did not produce an explicit diagnostic")


def main():
    # Keep stdout exclusively for the protocol. Tcl captures stderr in the
    # Session logs, including failures before the GUI is constructed.
    logging.basicConfig(stream=sys.stderr, level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    LOG.info("Curve Digitalizer %s; Python %s; executable=%s", PLUGIN_VERSION, sys.version, sys.executable)
    root = None
    rpc = None
    exit_code = 0

    def failed(exc):
        nonlocal exit_code
        exit_code = 1
        LOG.error("Initialization failed: %s", exc, exc_info=True)
        if rpc is not None:
            try:
                rpc.notify("FAILED")
            except RpcError:
                pass
        marker = os.environ.get("GX_CURVE_DIGITIZER_TEST_MARKER", "")
        if marker:
            Path(marker).write_text(f"FAIL: initialization: {exc}\n", encoding="utf-8")
        elif root is not None:
            root.deiconify()
            root.lift()
            messagebox.showerror(APP_NAME, f"Unable to initialize Curve Digitalizer:\n{exc}\n\n"
                                 "Details are in the Session logs: curve_digitizer_python.log.", parent=root)
        if root is not None:
            root.destroy()

    try:
        if sys.stdin is None or sys.stdout is None:
            raise RpcError("This viewer requires Python with standard pipes; do not use pythonw.exe.")
        # Frame terminators are explicit. Input still accepts both CRLF and LF.
        for stream, newline in ((sys.stdin, None), (sys.stdout, "\n")):
            reconfigure = getattr(stream, "reconfigure", None)
            if reconfigure:
                reconfigure(encoding="utf-8", errors="strict", newline=newline)
        root = tk.Tk()
        root.title(APP_NAME + " — Starting")
        root.geometry("600x180")
        startup = ttk.Frame(root, padding=24)
        startup.pack(fill="both", expand=True)
        ttk.Label(startup, text="Connecting to the GX-TXT Session…", font=("TkDefaultFont", 11, "bold")).pack(anchor="w")
        ttk.Label(startup, text="Loading image references and saved digitizer configurations.", wraplength=540).pack(anchor="w", pady=12)
        ttk.Button(startup, text="Cancel", command=root.destroy).pack(anchor="e")
        root.update_idletasks()
        if os.name == "nt":
            root.withdraw()
            root.update_idletasks()
        root.deiconify()
        root.lift()
        root.update_idletasks()
        LOG.info("Tk %s; startup window mapped=%s", root.tk.call("info", "patchlevel"), root.winfo_viewable())
        rpc = RpcClient(root)
        rpc.notify("STARTING")
        request_id = rpc.begin("BOOTSTRAP")
        deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS

        def finish_startup():
            try:
                payload = rpc.poll_response(request_id)
                if payload is None:
                    if time.monotonic() >= deadline:
                        raise RpcError(f"GX-TXT did not reply to BOOTSTRAP within {STARTUP_TIMEOUT_SECONDS:g} seconds. "
                                       "Inspect curve_digitizer_host.log for the last completed startup step.")
                    root.after(50, finish_startup)
                    return
                LOG.info("Bootstrap complete; constructing the viewer")
                startup.destroy()
                app = CurveDigitizerApp(root, rpc, bootstrap_payload=payload)
                root.update_idletasks()
                app.focus_window()
                root.update_idletasks()
                LOG.info("GUI READY; mapped=%s geometry=%s", root.winfo_viewable(), root.geometry())
                rpc.notify("READY")
            except Exception as exc:
                failed(exc)

        # The initial RPC is polled from the normal event loop. A missing reply
        # cannot keep the process alive indefinitely with no visible window.
        root.after(50, finish_startup)
        root.mainloop()
    except Exception as exc:
        failed(exc)
    if rpc is not None:
        try:
            rpc.notify("CLOSED")
        except RpcError:
            pass
    LOG.info("Viewer process exiting code=%s", exit_code)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
