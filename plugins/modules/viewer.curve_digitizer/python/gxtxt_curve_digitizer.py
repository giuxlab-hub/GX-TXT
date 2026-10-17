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
from tkinter import messagebox, simpledialog, ttk, colorchooser

import numpy as np
from PIL import Image, ImageTk, UnidentifiedImageError

from digitizer_model import AxisConfig, Calibration, CalibrationError, CORNER_ORDER, DigitizedPoint, Project, Series
from point_ordering import normalize as normalize_ordering, order_project, order_series
from image_canvas import ImageCanvas
from processing_controls import FilterControls, STANDARD_ORDER, merge_filter_operations
from scale_bar import detect_scale_bar, ScaleDetectionError
from calibration_manifest import build_manifest, metadata_fields, encode_metadata_records
from publication_planning import DEFAULT_TEMPLATE, PUBLICATION_LAYOUTS, plan_datasets, validate_template
from assisted_sampling import sample_proposal_segments
from assisted_tracing import propose, samples_from_guides, repair, insert_correction
from quality_diagnostics import inspect as inspect_quality
from uncertainty_engine import checked_spec, propagate, compact_factors, review_fingerprint
from uncertainty_dialog import UncertaintyDialog
from auto_enhancement import recommend as recommend_enhancement
from image_processing import (OPERATION_KINDS, DEFAULT_PARAMETERS, ProcessingError,
                              normalize_operations, apply_processing, metadata as processing_metadata,
                              image_fingerprint)

APP_NAME = "GX-TXT Curve Digitalizer"
LOG = logging.getLogger("gx.curve_digitizer")
STARTUP_TIMEOUT_SECONDS = 45.0
RPC_TIMEOUT_SECONDS = 120.0
CONFIG_FORMAT = "gxtxt.curve_digitizer.configuration"
CONFIG_VERSION = "1.0"
PLUGIN_VERSION = "2.0.3"
SERIES_COLORS = ("#d62728", "#1f77b4", "#2ca02c", "#9467bd", "#ff7f0e", "#17becf", "#e377c2", "#8c564b", "#bcbd22")
CORNER_LABELS = {"bottom_left": "BL", "bottom_right": "BR", "top_left": "TL", "top_right": "TR"}
EDGE_MODES = {
    "Center-to-center (tick centers)": "center",
    "Inner edges of ticks": "inner",
    "Outer edges of ticks": "outer",
}
EDGE_LABELS = {value: key for key, value in EDGE_MODES.items()}
# Keys registered by the module descriptor with CONFIGURATION_API_v1.
# CORE User/Session values remain the authoritative *defaults*. Display-only
# opacity and background overrides for an individual configuration are stored
# in that Interactive Document, never in an independent settings file.
CORE_PREFS = {
    "show_point_numbers": "0",
    "show_scale_overlay": "1",
    "show_calibration_corners": "1",
    "snap_enabled": "0",
    "snap_radius": "3",
    "scale_edge": "center",
    "y_direction": "Upward (Cartesian)",
    "scale_length": "10",
    "scale_unit": "µm",
    "auto_catalog_check": "1",
    "verification_marker_size": "14",
    "verification_marker_width": "2",
    "verification_marker_color": "#ff3030",
    "publication_layout": "separate",
    "publication_name_template": DEFAULT_TEMPLATE,
    "processing_compare": "0", "processing_sync_views": "0",
    "processing_show_curve_overlays": "1", "processing_live_preview": "1",
    "processing_filter_mode": "standard",
    "canvas_background": "#303030", "image_opacity": "100",
}
CORE_PREF_DRAFT = {
    "numbers": "show_point_numbers", "overlay": "show_scale_overlay",
    "corners": "show_calibration_corners", "snapping": "snap_enabled",
    "radius": "snap_radius", "edge": "scale_edge",
    "direction": "y_direction", "length": "scale_length",
    "unit": "scale_unit", "catalog_auto": "auto_catalog_check",
    "verify_size": "verification_marker_size", "verify_width": "verification_marker_width",
    "verify_color": "verification_marker_color",
    "publish_layout": "publication_layout", "publish_template": "publication_name_template",
}
CORE_BOOL_PREFS = {"show_point_numbers", "show_scale_overlay",
    "show_calibration_corners", "snap_enabled", "auto_catalog_check",
    "processing_compare", "processing_sync_views", "processing_show_curve_overlays",
    "processing_live_preview"}


def preference_bool(value):
    return str(value).strip().lower() in ("1", "true", "yes", "on")


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
        # Stay inside the usable desktop on smaller displays and at 125-150% DPI.
        root.geometry(f"1380x{max(620, min(830, root.winfo_screenheight() - 100))}")
        root.minsize(1000, 590)

        self.session_token = ""
        self.units: list[str] = []
        self.roles: list[str] = []
        self.datasets: dict[str, dict] = {}
        self.dataset_namespaces: list[str] = []
        self.catalog_session_token: str = ""
        self.catalog_revision: int | None = None
        self.catalog_request_id: str | None = None
        self.catalog_request_kind: str = ""
        self.catalog_check_ms = 5000
        self.catalog_session_invalid = False
        # Session changes are independent of Dataset catalog auto-refresh.
        # Never retain a previous Session's scientific state or proposals.
        self.session_probe_id = None
        self.session_bootstrap_id = None
        self.session_refreshing = False
        self.session_check_ms = 3000
        self.documents: dict[str, dict] = {}
        self.document_sha: dict[str, str] = {}
        self.current_doc_id: str | None = None
        self.config: dict = {}
        self.project = Project()
        self.image = None
        self.processed_image = None
        self.processed_fingerprint = None
        self.processing_operations = []
        self.processing_executable = ""
        self.processing_engine_version = ""
        self.processing_result_queue = queue.Queue()
        self.processing_active = False
        self.processing_kind = tk.StringVar(value="grayscale")
        self.processing_value = tk.StringVar(value="")
        self.processing_dataset_id = tk.StringVar()
        self.processing_display_name = tk.StringVar()
        self.processing_show_result = tk.BooleanVar(value=True)
        self.processing_status = tk.StringVar(value="ImageMagick detection pending.")
        self.processing_compare = tk.BooleanVar(value=False)
        self.processing_sync_views = tk.BooleanVar(value=False)
        self.processing_overlay = tk.BooleanVar(value=True)
        self.processing_live = tk.BooleanVar(value=True)
        self.processing_filter_mode = tk.StringVar(value="standard")
        self.processing_filter_controls = None
        self._processing_update_after = None
        self._processing_resubmit = False
        self._compare_view_guard = False
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
        self.curve_monotonicity = tk.StringVar(value="none")
        self.point_order_source = tk.StringVar(value="insertion")
        self.guide_points = []  # transient, never authoritative
        self.assisted_proposal = None  # candidate only; Accept is a separate edit
        self.assist_status = tk.StringVar(value="")
        self.assist_radius = tk.IntVar(value=8)
        self.assist_step = tk.DoubleVar(value=2.0)
        self.assist_source = tk.StringVar(value="auto")  # original | processed | auto
        self.assist_segment = tk.IntVar(value=1)
        self.assist_output_points = tk.StringVar(value="0")  # 0 = native proposal count
        self.assist_accepted_point_ids = {}  # only points created by this live proposal
        self._assist_sampling_spec = None  # target count frozen at first acceptance
        self.assist_accepted_segments = set()
        self._assist_drag = None
        self._assist_preview_cursor = None
        # Transient proposal-only undo history; never saved into Dataset/Session.
        self._proposal_history = []
        self._proposal_last_insert = None
        self._assist_move_target = None
        self._auto_previous_pipeline = None
        self.assist_baseline_request = None
        self._assist_pending_points = None
        self._assist_context = None
        self.opacity_var = tk.IntVar(value=100)
        self.canvas_bg_var = tk.StringVar(value="#303030")
        self._appearance_after = None
        self._appearance_loading = False
        self.status = tk.StringVar(value="Ready")
        self.config_var = tk.StringVar()
        self.source_var = tk.StringVar()
        self.namespace_var = tk.StringVar(value="All namespaces")
        self.catalog_diag = tk.StringVar(value="Checking Dataset catalog...")
        self.auto_catalog_watch = tk.BooleanVar(value=True)
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
        self.auto_y_direction = tk.StringVar(value="Upward (Cartesian)")
        self.selected_label = tk.StringVar(value="No point selected.")
        self.verify_result = tk.StringVar()
        self.verify_point = None  # transient source-image pixel coordinate
        self.verify_panel_open = False
        self.hide_saved_scale_overlay = False  # view-only, does not reset calibration
        self.measurement_selected_id = None
        self.measurement_table = None
        self.publish_measurements = None
        self.publish_layout = tk.StringVar(value="separate")
        self.publish_name_template = tk.StringVar(value=DEFAULT_TEMPLATE)
        self.publish_selection = []
        self.exp_x = tk.StringVar()
        self.exp_y = tk.StringVar()
        self.scale_length = tk.StringVar(value="10")
        self.scale_unit = tk.StringVar(value="µm")
        self.scale_status = tk.StringVar(value="Auto-calibrate the full image first.")
        self.scale_candidate = None  # transient proposed endpoints, never persisted until Apply
        self.scale_first_endpoint = None
        self.scale_edge_convention = tk.StringVar(value=EDGE_LABELS["center"])
        self.show_scale_overlay = tk.BooleanVar(value=True)
        self.show_calibration_corners = tk.BooleanVar(value=True)
        self.settings_dialog = None
        self.help_request_id = None
        self.shared_settings = dict(CORE_PREFS)
        self.shared_settings_origin = {}
        self.settings_request_id = None

        self.bootstrap(bootstrap_payload)
        LOG.info("Building Curve Digitalizer widgets")
        self.build_ui()
        self.exp_x.trace_add("write", lambda *_: self.update_verification())
        self.exp_y.trace_add("write", lambda *_: self.update_verification())
        self.mode.trace_add("write", lambda *_: self._verification_mode_changed())
        self.bind_keys()
        self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
        self.refresh_configuration_selector()
        if self.documents:
            self.open_document(next(iter(self.documents)))
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.after(250, self._resolve_image_processing_tool)
        self.root.after(150, self._poll_image_processing)
        self.root.after(800, lambda: self.check_dataset_catalog(force=True))
        self.root.after(self.catalog_check_ms, self._scheduled_catalog_check)
        self.root.after(5000, self._scheduled_settings_check)
        self.root.after(self.session_check_ms, self._scheduled_session_check)

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
            elif kind == "SETTING" and len(fields) >= 2:
                key, effective = fields[:2]
                if key in CORE_PREFS:
                    self.shared_settings[key] = effective
                    self.shared_settings_origin[key] = fields[2] if len(fields) > 2 else ""
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
            "image_processing": {"operations": [], "show_processed": True},
            "scale_reference": None,
            "curves": [],
            "curve_ordering": {"monotonicity": "none", "source": "insertion"},
            "assisted_tracing": {"output_points": 0},
            "uncertainty": {"mode": "none"},
            "family": {"enabled": False, "quantity_label": "Family parameter", "unit": "", "semantic_role": "family"},
            "display": {"show_point_numbers": False, "show_scale_overlay": True,
                        "show_calibration_corners": True,
                        "canvas_background": "#303030", "image_opacity": 100},
            "scale_preferences": {"edge_convention": "center", "y_direction": "Upward (Cartesian)",
                                  "length": "10", "unit": "µm"},
            "snap": {"enabled": False, "radius": 3},
            "view": {"scale": 1.0, "offset_x": 0.0, "offset_y": 0.0},
            "publication": {"dataset_id": "", "display_name": ""},
            "catalog_preferences": {"selected_namespace": "All namespaces", "automatic": True},
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
        if self.config:
            self._sync_active_measurement()
        cfg = copy.deepcopy(self.config) if self.config else self.new_configuration("Untitled")
        cfg["format"] = CONFIG_FORMAT
        cfg["version"] = CONFIG_VERSION
        x = self.project.x_axis.to_dict()
        y = self.project.y_axis.to_dict()
        x["semantic_role"] = self.x_role.get().strip()
        y["semantic_role"] = self.y_role.get().strip()
        cfg["axes"] = {"x": x, "y": y}
        cfg["calibration"] = self.project.calibration.to_dict()
        # Apply the selected point order before serialization so Undo/Redo,
        # Interactive Documents and scientific publication share one ordering.
        order_project(self.project, self._ordering_policy())
        cfg["curves"] = [s.to_dict() for s in self.project.series]
        cfg["curve_ordering"] = self._ordering_policy()
        try:
            saved_density=self._valid_assist_output_points()
        except (ValueError, tk.TclError):
            saved_density=int((cfg.get("assisted_tracing") or {}).get("output_points",0))
        cfg["assisted_tracing"] = {"output_points": saved_density}
        cfg["family"] = {
            "enabled": bool(self.family_enabled.get()),
            "quantity_label": self.family_label.get().strip() or "Family parameter",
            "unit": self.family_unit.get().strip(),
            "semantic_role": self.family_role.get().strip() or "family",
        }
        cfg["display"] = {
            "show_point_numbers": bool(self.show_numbers.get()),
            "show_scale_overlay": bool(self.show_scale_overlay.get()),
            "show_calibration_corners": bool(self.show_calibration_corners.get()),
            "canvas_background": self.canvas_bg_var.get().lower(),
            "image_opacity": max(0,min(100,int(self.opacity_var.get()))),
        }
        cfg["scale_preferences"] = {
            "edge_convention": EDGE_MODES.get(self.scale_edge_convention.get(), "center"),
            "y_direction": self.auto_y_direction.get(),
            "length": self.scale_length.get(),
            "unit": self.scale_unit.get(),
        }
        cfg["snap"] = {"enabled": bool(self.snap_enabled.get()), "radius": max(0, int(self.snap_radius.get()))}
        cfg["catalog_preferences"] = {
            "selected_namespace": self.namespace_var.get(),
            "automatic": bool(self.auto_catalog_watch.get()),
        }
        cfg["image_processing"] = {"operations": copy.deepcopy(self.processing_operations),
                                   "show_processed": bool(self.processing_show_result.get())}
        cfg["notes"] = self.notes.get("1.0", "end-1c") if hasattr(self, "notes") else cfg.get("notes", "")
        cfg["publication"] = {
            "dataset_id": self.output_dataset_id.get().strip(),
            "display_name": self.output_display_name.get().strip(),
            "layout": self.publish_layout.get(),
            "selected_measurement_ids": self.selected_publication_ids(),
        }
        if hasattr(self, "canvas"):
            cfg["view"] = {"scale": self.canvas.scale, "offset_x": self.canvas.offset_x, "offset_y": self.canvas.offset_y}
        return cfg

    def persist(self):
        # A Session transition must never commit a previous Session's draft.
        # The CORE token guard is still the authoritative second protection.
        if (self.loading_ui or not self.current_doc_id or
                self.session_refreshing or self.catalog_session_invalid):
            return False
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
        # A restored Session snapshot may contain a different set of accepted
        # point identifiers. Invalidate only the transient proposal bookkeeping;
        # never edit restored scientific points by a stale segment number.
        self.assist_accepted_point_ids={}
        self.assist_accepted_segments=set()
        self._assist_sampling_spec=None
        self.assisted_proposal=None
        self.config = copy.deepcopy(cfg)
        self.project = self.config_to_project(self.config)
        self.measurement_selected_id = None
        self.verify_point = None
        self.active_series_id = self.project.series[0].id if self.project.series else None
        self.selected_point_id = None
        self.sync_controls_from_config(reload_source=False)
        self.refresh_measurements()
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

    def _parse_shared_settings(self, payload):
        settings = dict(CORE_PREFS)
        origins = {}
        for kind, fields in parse_records(payload):
            if kind == "SETTING" and len(fields) >= 2 and fields[0] in CORE_PREFS:
                settings[fields[0]] = fields[1]
                origins[fields[0]] = fields[2] if len(fields) > 2 else ""
        return settings, origins

    def _apply_shared_settings(self, settings, origins=None, *, force=False):
        """Apply effective host-owned preferences; preserve scientific calibration."""
        if not settings:
            return
        if not force and settings == self.shared_settings and origins == self.shared_settings_origin:
            return
        previous_edge = self.scale_edge_convention.get()
        previous_publication_default = self.shared_settings.get("publication_layout")
        self.shared_settings = dict(settings)
        if origins is not None:
            self.shared_settings_origin = dict(origins)
        self.show_numbers.set(preference_bool(settings["show_point_numbers"]))
        self.show_scale_overlay.set(preference_bool(settings["show_scale_overlay"]))
        self.show_calibration_corners.set(preference_bool(settings["show_calibration_corners"]))
        self.snap_enabled.set(preference_bool(settings["snap_enabled"]))
        self.snap_radius.set(int(settings["snap_radius"]))
        self.project.show_point_numbers = self.show_numbers.get()
        self.project.snap_enabled = self.snap_enabled.get()
        self.project.snap_radius = self.snap_radius.get()
        self.auto_catalog_watch.set(preference_bool(settings["auto_catalog_check"]))
        # Screen-pixel dimensions are independent from zoom or image resolution.
        try:
            self.verification_marker_size = max(4, min(64, int(settings["verification_marker_size"])))
            self.verification_marker_width = max(1, min(12, int(settings["verification_marker_width"])))
        except (ValueError, TypeError):
            self.verification_marker_size, self.verification_marker_width = 14, 2
        color = str(settings.get("verification_marker_color", "#ff3030"))
        self.verification_marker_color = color if re.fullmatch(r"#[0-9a-fA-F]{6}", color) else "#ff3030"
        # Physical calibration fields belong to the individual digitalization.
        # User/Session Configuration provides defaults ONLY before calibration.
        if not (self.config.get("scale_reference") or {}):
            self.scale_edge_convention.set(EDGE_LABELS[settings["scale_edge"]])
            self.scale_length.set(settings["scale_length"])
            self.scale_unit.set(settings["scale_unit"])
        if not (self.project.calibration.pixels or {}):
            self.auto_y_direction.set(settings["y_direction"])
        if previous_edge != self.scale_edge_convention.get():
            # Only invalidate an uncommitted candidate, never rewrite a saved
            # measurement or a published Dataset after a preference change.
            if self.scale_candidate is not None:
                self.scale_candidate = None
                self.scale_first_endpoint = None
                self.mode.set("add")
                self.scale_status.set("Tick reference changed. Detect the scale bar again.")
        if hasattr(self, "publish_layout"):
            current = self.publish_layout.get()
            if (force or current not in PUBLICATION_LAYOUTS or
                    previous_publication_default != settings["publication_layout"]):
                self.publish_layout.set(settings["publication_layout"])
            self.publish_name_template.set(settings["publication_name_template"])
            if hasattr(self, "publish_plan_preview"):
                self.preview_publication()
        for key, var in (("processing_compare", self.processing_compare),
                         ("processing_sync_views", self.processing_sync_views),
                         ("processing_show_curve_overlays", self.processing_overlay),
                         ("processing_live_preview", self.processing_live)):
            var.set(preference_bool(settings.get(key, CORE_PREFS[key])))
        mode = settings.get("processing_filter_mode", "standard")
        if mode in ("standard", "advanced"):
            self.processing_filter_mode.set(mode)
            if hasattr(self, "processing_advanced_box"):
                self._processing_mode_visibility()
        if hasattr(self, "canvas"):
            self._appearance_loading=True
            try:
                display=(self.config or {}).get("display",{})
                try:self.opacity_var.set(max(0,min(100,int(display.get("image_opacity", settings.get("image_opacity","100"))))) )
                except (ValueError,TypeError):self.opacity_var.set(100)
                color=display.get("canvas_background",settings.get("canvas_background","#303030"))
                self.canvas_bg_var.set(color if re.fullmatch(r"#[0-9a-fA-F]{6}",str(color)) else "#303030")
                self._apply_canvas_appearance()
            finally:self._appearance_loading=False
            self._update_processing_view_layout()
            self.redraw()

    def _sync_shared_settings(self):
        """Reload CORE values after a central-editor change (no derived storage)."""
        try:
            payload = self.rpc.call("CONFIG_READ")
            settings, origins = self._parse_shared_settings(payload)
            self._apply_shared_settings(settings, origins)
        except (RpcError, ValueError, KeyError) as exc:
            self.status.set(f"GX-TXT Configuration unavailable: {exc}")

    def _scheduled_settings_check(self):
        if not self.root.winfo_exists():
            return
        if self.settings_request_id is None:
            try:
                self.settings_request_id = self.rpc.begin("CONFIG_READ")
                self.root.after(80, self._poll_settings_reply)
            except RpcError as exc:
                self.status.set(f"Configuration synchronization failed: {exc}")
        self.root.after(5000, self._scheduled_settings_check)

    def _poll_settings_reply(self):
        if self.session_refreshing:
            return
        request = self.settings_request_id
        if request is None:
            return
        try:
            payload = self.rpc.poll_response(request)
            if payload is None:
                if self.root.winfo_exists():
                    self.root.after(100, self._poll_settings_reply)
                return
            self.settings_request_id = None
            settings, origins = self._parse_shared_settings(payload)
            self._apply_shared_settings(settings, origins)
        except (RpcError, ValueError, KeyError) as exc:
            self.settings_request_id = None
            self.status.set(f"Configuration synchronization failed: {exc}")

    def _commit_pref_values(self, updates, expected=None):
        """CORE Configuration.commit: atomic Session override with conflict check."""
        expected = dict(self.shared_settings if expected is None else expected)
        lines = []
        for key, value in updates.items():
            if key not in CORE_PREFS:
                raise ValueError(f"Unknown viewer setting: {key}")
            value = str(int(value)) if isinstance(value, bool) else str(value)
            if value != expected[key]:
                lines.append("\t".join((key, b64e(expected[key]), b64e(value))))
        if not lines:
            return
        payload = self.rpc.call("CONFIG_COMMIT", self.session_token, "\n".join(lines))
        settings, origins = self._parse_shared_settings(payload)
        self._apply_shared_settings(settings, origins)

    def open_core_settings(self):
        """Use the framework's native User/Session configuration module editor."""
        try:
            self.rpc.call("CONFIG_OPEN")
        except RpcError as exc:
            messagebox.showerror("GX-TXT Configuration", str(exc), parent=self.root)

    def build_menus(self):
        """Small native menubar; retains shortcuts and every legacy command."""
        menubar = tk.Menu(self.root, tearoff=False)
        configurations = tk.Menu(menubar, tearoff=False)
        configurations.add_command(label="New configuration...", command=self.new_config)
        configurations.add_command(label="Rename configuration...", command=self.rename_config)
        configurations.add_command(label="Duplicate configuration", command=self.duplicate_config)
        configurations.add_command(label="Delete configuration...", command=self.delete_config)
        configurations.add_separator()
        configurations.add_command(label="Viewer settings...", command=self.open_viewer_settings)
        configurations.add_command(label="GX-TXT module configuration...", command=self.open_core_settings)

        edit = tk.Menu(menubar, tearoff=False)
        edit.add_command(label="Undo", accelerator="Ctrl+Z", command=self.undo)
        edit.add_command(label="Redo", accelerator="Ctrl+Y", command=self.redo)
        edit.add_separator()
        edit.add_command(label="New curve...", command=self.new_series)
        edit.add_command(label="Edit selected curve...", command=self.edit_series)
        edit.add_command(label="Delete selected curve...", command=self.delete_series)
        edit.add_command(label="Delete selected point", command=self.delete_selected_point)
        menubar.add_cascade(label="Edit", menu=edit)

        view = tk.Menu(menubar, tearoff=False)
        view.add_command(label="Fit image to window", command=lambda: self.canvas.fit_to_window())
        view.add_command(label="Show source information", command=lambda: self.notebook.select(self.source_tab))
        view.add_command(label="Image Processing...", command=lambda: self.notebook.select(self.processing_tab))
        view.add_command(label="Show calibration", command=lambda: self.notebook.select(self.calibration_tab))
        view.add_command(label="Show curves", command=lambda: self.notebook.select(self.curves_tab))
        view.add_command(label="Show publishing", command=lambda: self.notebook.select(self.publish_tab))
        view.add_separator()
        view.add_checkbutton(label="Show point numbers", variable=self.show_numbers, command=self.display_changed)
        view.add_checkbutton(label="Show scale bar overlay", variable=self.show_scale_overlay, command=self.display_changed)
        view.add_checkbutton(label="Show calibration corners", variable=self.show_calibration_corners, command=self.display_changed)
        menubar.add_cascade(label="View", menu=view)

        calibration = tk.Menu(menubar, tearoff=False)
        calibration.add_command(label="Auto-calibrate full image", command=self.auto_calibrate_full_image)
        calibration.add_command(label="Detect scale bar (click image)", command=self.start_scale_detection)
        calibration.add_command(label="Select two scale bar endpoints", command=self.start_scale_manual)
        calibration.add_command(label="Apply physical scale", command=self.apply_image_scale)
        calibration.add_separator()
        calibration.add_command(label="Verify calibration...", command=self.start_verification)
        calibration.add_command(label="Clear verification", command=self.clear_verification)
        calibration.add_command(label="Clear scale selection overlay", command=self.cancel_scale_selection)
        calibration.add_command(label="Reset physical scale...", command=self.reset_scale_calibration)
        calibration.add_command(label="Clear calibration...", command=self.clear_calibration)
        menubar.add_cascade(label="Calibration", menu=calibration)

        publish = tk.Menu(menubar, tearoff=False)
        publish.add_command(label="Publish Dataset...", command=lambda: self.notebook.select(self.publish_tab))
        publish.add_command(label="Publish processed image...", command=lambda: self.notebook.select(self.processing_tab))
        publish.add_command(label="Publish now", command=self.publish_dataset)
        publish.add_separator()
        publish.add_command(label="Refresh Dataset catalog", command=lambda: self.check_dataset_catalog(force=True))
        publish.add_checkbutton(label="Check Dataset changes automatically", variable=self.auto_catalog_watch,
                                command=self.catalog_watch_changed)
        menubar.add_cascade(label="Dataset", menu=publish)

        namespaces = tk.Menu(menubar, tearoff=False)
        namespaces.add_command(label="Select Dataset namespace...", command=self.open_namespace_picker)
        namespaces.add_command(label="Show all namespaces", command=self.show_all_namespaces)
        menubar.add_cascade(label="Namespace", menu=namespaces)
        menubar.add_cascade(label="Configuration", menu=configurations)
        help_menu = tk.Menu(menubar, tearoff=False)
        help_menu.add_command(label="Curve Digitalizer user guide...", accelerator="F1", command=self.open_help)
        help_menu.add_separator()
        help_menu.add_command(label="About Curve Digitalizer", command=lambda: messagebox.showinfo(
            APP_NAME, f"{APP_NAME} {PLUGIN_VERSION}\nGNU GPL v3 or later\n\nSession-native Image Dataset digitization.",
            parent=self.root))
        menubar.add_cascade(label="Help", menu=help_menu)
        self.root.configure(menu=menubar)
        self.menubar = menubar

    def scale_convention_changed(self, _event=None):
        # This selection describes the individual scale-bar measurement, not
        # a new global User/Session preference.
        if self.scale_candidate is not None:
            self.scale_candidate = None
            self.scale_first_endpoint = None
            self.mode.set("add")
            self.scale_status.set("Tick reference changed. Detect the scale bar again before applying.")
            self.redraw()
        self.persist_later()

    def open_viewer_settings(self):
        """Edit CORE Session overrides and local scientific output in one dialog."""
        self._sync_shared_settings()
        captured_shared_settings = dict(self.shared_settings)
        if self.settings_dialog is not None and self.settings_dialog.winfo_exists():
            self.settings_dialog.lift()
            self.settings_dialog.focus_force()
            return
        window = tk.Toplevel(self.root)
        self.settings_dialog = window
        window.title("Curve Digitalizer — Viewer settings")
        window.transient(self.root)
        window.resizable(True, True)
        window.geometry("640x565")
        window.minsize(520, 435)
        draft = {
            "numbers": tk.BooleanVar(window, value=self.show_numbers.get()),
            "canvas_opacity": tk.StringVar(window,value=str(self.opacity_var.get())),
            "canvas_background": tk.StringVar(window,value=self.canvas_bg_var.get()),
            "curve_monotonicity": tk.StringVar(window,value=self.curve_monotonicity.get()),
            "point_order_source": tk.StringVar(window,value=self.point_order_source.get()),
            "assist_output_points": tk.StringVar(window,value=self.assist_output_points.get()),
            "overlay": tk.BooleanVar(window, value=self.show_scale_overlay.get()),
            "corners": tk.BooleanVar(window, value=self.show_calibration_corners.get()),
            "snapping": tk.BooleanVar(window, value=self.snap_enabled.get()),
            "radius": tk.StringVar(window, value=str(self.snap_radius.get())),
            "edge": tk.StringVar(window, value=EDGE_LABELS[self.shared_settings["scale_edge"]]),
            "direction": tk.StringVar(window, value=self.shared_settings["y_direction"]),
            "unit": tk.StringVar(window, value=self.shared_settings["scale_unit"]),
            "length": tk.StringVar(window, value=self.shared_settings["scale_length"]),
            "dataset_id": tk.StringVar(window, value=self.output_dataset_id.get()),
            "display_name": tk.StringVar(window, value=self.output_display_name.get()),
            "catalog_auto": tk.BooleanVar(window, value=self.auto_catalog_watch.get()),
            "verify_size": tk.StringVar(window, value=self.shared_settings["verification_marker_size"]),
            "verify_width": tk.StringVar(window, value=self.shared_settings["verification_marker_width"]),
            "verify_color": tk.StringVar(window, value=self.shared_settings["verification_marker_color"]),
            "publish_layout": tk.StringVar(window, value=self.shared_settings["publication_layout"]),
            "publish_template": tk.StringVar(window, value=self.shared_settings["publication_name_template"]),
        }
        # Persistent footer is allocated before the growing Notebook; Apply never
        # disappears below the bottom edge on compact screens.
        footer = ttk.Frame(window, padding=(12, 6, 12, 9))
        footer.pack(side="bottom", fill="x")
        apply_status = tk.StringVar(window, value="Changes not applied")
        ttk.Label(footer, textvariable=apply_status, anchor="w").pack(side="left", fill="x", expand=True)
        self.settings_apply_status = apply_status
        ttk.Label(window, text="Viewer preferences are managed by GX-TXT Configuration API v1."
                  " Apply writes Session overrides; User defaults are in GX-TXT module configuration.",
                  wraplength=565, justify="left").pack(fill="x", padx=12, pady=(8, 0))
        ttk.Button(window, text="Open GX-TXT module configuration (User / Session)...",
                   command=self.open_core_settings).pack(anchor="w", padx=12, pady=(4, 0))
        tabs = ttk.Notebook(window)
        tabs.pack(fill="both", expand=True, padx=12, pady=(12, 8))
        def tab(name):
            pane = ttk.Frame(tabs, padding=14)
            tabs.add(pane, text=name)
            return pane
        display = tab("Display")
        ttk.Label(display, text="Canvas overlays", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        for label, key in (("Show point numbers", "numbers"),
                           ("Show image scale bar overlay", "overlay"),
                           ("Show four-point calibration markers", "corners")):
            ttk.Checkbutton(display, text=label, variable=draft[key]).pack(anchor="w", pady=5)
        ttk.Label(display,text="Current configuration appearance",font=("TkDefaultFont",10,"bold")).pack(anchor="w",pady=(15,5))
        for caption,key in (("Image opacity (%)", "canvas_opacity"),
                            ("Canvas background (#RRGGBB)", "canvas_background")):
            line=ttk.Frame(display);line.pack(fill="x",pady=3)
            ttk.Label(line,text=caption,width=30).pack(side="left")
            ttk.Entry(line,textvariable=draft[key],width=16).pack(side="left",padx=5)
        ttk.Button(display,text="Use CORE default appearance",command=lambda: (
            draft["canvas_opacity"].set(self.shared_settings.get("image_opacity","100")),
            draft["canvas_background"].set(self.shared_settings.get("canvas_background","#303030")))).pack(anchor="w",pady=(6,3))
        ttk.Label(display, text="Background and opacity are saved in this configuration only. "
                  "New configurations use central CORE defaults. Rendering changes do not alter scientific pixels.",
                  wraplength=475).pack(anchor="w",pady=(7,0))

        digitizing = tab("Digitizing")
        ttk.Label(digitizing, text="Point selection", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Checkbutton(digitizing, text="Snap to darkest pixel", variable=draft["snapping"]).pack(anchor="w", pady=(12, 8))
        line = ttk.Frame(digitizing); line.pack(fill="x")
        ttk.Label(line, text="Snap radius (pixels):").pack(side="left")
        ttk.Spinbox(line, from_=0, to=25, textvariable=draft["radius"], width=8).pack(side="left", padx=8)
        ttk.Separator(digitizing, orient="horizontal").pack(fill="x",pady=(15,10))
        ttk.Label(digitizing, text="Curve ordering / monotonicity", font=("TkDefaultFont",10,"bold")).pack(anchor="w")
        monotonic_choices={"None":"none","Monotonic in X":"x","Monotonic in Y":"y"}
        source_choices={"Insertion order":"insertion","Sort by X":"x","Sort by Y":"y"}
        mono=ttk.Frame(digitizing);mono.pack(fill="x",pady=(6,3))
        ttk.Label(mono,text="Monotonicity",width=20).pack(side="left")
        mono_label=tk.StringVar(window,value=next(k for k,v in monotonic_choices.items() if v==draft["curve_monotonicity"].get()))
        source_label=tk.StringVar(window,value=next(k for k,v in source_choices.items() if v==draft["point_order_source"].get()))
        point_src=ttk.Frame(digitizing);point_src.pack(fill="x",pady=3)
        ttk.Label(point_src,text="Point ordering source",width=20).pack(side="left")
        ttk.Combobox(mono,textvariable=mono_label,values=list(monotonic_choices),state="readonly",width=22).pack(side="left")
        ttk.Combobox(point_src,textvariable=source_label,values=list(source_choices),state="readonly",width=22).pack(side="left")
        updating=[False]
        def mono_changed(*_):
            if updating[0]:return
            updating[0]=True
            try:
                mode=monotonic_choices[mono_label.get()]
                draft["curve_monotonicity"].set(mode)
                if mode!='none':
                    draft["point_order_source"].set(mode)
                    source_label.set(next(k for k,v in source_choices.items() if v==mode))
            finally:updating[0]=False
        def source_changed(*_):
            if updating[0]:return
            updating[0]=True
            try:
                mode=source_choices[source_label.get()]
                draft["point_order_source"].set(mode)
                if draft["curve_monotonicity"].get()!='none' and mode!=draft["curve_monotonicity"].get():
                    draft["curve_monotonicity"].set('none')
                    mono_label.set('None')
            finally:updating[0]=False
        mono_label.trace_add('write',mono_changed)
        source_label.trace_add('write',source_changed)
        density=ttk.Frame(digitizing);density.pack(fill="x",pady=(14,4))
        ttk.Label(density,text="Assisted trace output points",width=27).pack(side="left")
        ttk.Spinbox(density,from_=0,to=10000,increment=10,
                    textvariable=draft["assist_output_points"],width=9).pack(side="left")
        ttk.Label(digitizing,text="0 retains proposal sampling. A positive count sets the total number "
                  "of assisted points in a fully accepted proposal; existing manual points are preserved.",
                  wraplength=470).pack(anchor="w",pady=(4,0))

        cal = tab("Calibration")
        ttk.Label(cal, text="Default scale-bar reference", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Combobox(cal, textvariable=draft["edge"], values=tuple(EDGE_MODES),
                     state="readonly", width=36).pack(anchor="w", pady=(5, 12))
        ttk.Label(cal, text="Use the centers of the terminal ticks unless the microscope convention is known.\n"
                  "A changed reference requires selecting the bar again.", wraplength=480).pack(anchor="w")
        ttk.Label(cal, text="Verification marker (screen pixels)", font=("TkDefaultFont", 10, "bold")).pack(anchor="w", pady=(12, 3))
        verify_row = ttk.Frame(cal); verify_row.pack(fill="x")
        for label, key in (("Size", "verify_size"), ("Line width", "verify_width"), ("Color", "verify_color")):
            ttk.Label(verify_row, text=label).pack(side="left", padx=(0, 4))
            ttk.Entry(verify_row, textvariable=draft[key], width=8).pack(side="left", padx=(0, 12))
        ttk.Label(cal, text="Full-image Y direction:").pack(anchor="w", pady=(16, 2))
        ttk.Combobox(cal, textvariable=draft["direction"],
                     values=("Upward (Cartesian)", "Downward (image pixels)"),
                     state="readonly", width=36).pack(anchor="w")
        row = ttk.Frame(cal); row.pack(anchor="w", pady=(18, 0))
        ttk.Label(row, text="Scale length:").pack(side="left")
        ttk.Entry(row, textvariable=draft["length"], width=10).pack(side="left", padx=6)
        ttk.Label(row, text="Unit:").pack(side="left")
        ttk.Combobox(row, textvariable=draft["unit"], width=10,
                     values=("µm", "nm", "mm", "cm", "m", "pm", "Å", "um", "in", "ft")).pack(side="left", padx=6)
        ttk.Label(cal, text="Changing preferences does not reapply an existing calibration.",
                  wraplength=480).pack(anchor="w", pady=(12, 0))

        output = tab("Axes & output")
        ttk.Label(output, text="Scientific axes", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Label(output, text=f"X: {self.x_name.get()} [{self.x_unit.get()}]   |   "
                  f"Y: {self.y_name.get()} [{self.y_unit.get()}]", wraplength=470).pack(anchor="w", pady=(7, 3))
        ttk.Label(output, text="Edit scientific axis limits, labels, units and calibration in the Calibration tab.",
                  wraplength=470).pack(anchor="w", pady=(3, 10))
        def to_axes():
            if apply():
                window.destroy()
                self.notebook.select(self.calibration_tab)
        ttk.Button(output, text="Go to axis calibration...", command=to_axes).pack(anchor="w", pady=(0, 20))
        ttk.Label(output, text="Output Dataset identity", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        for label, key in (("Dataset ID", "dataset_id"), ("Display name", "display_name")):
            row=ttk.Frame(output);row.pack(fill="x", pady=5)
            ttk.Label(row, text=label, width=15).pack(side="left")
            ttk.Entry(row, textvariable=draft[key]).pack(side="left", fill="x", expand=True)
        ttk.Label(output, text="Publication layout default", font=("TkDefaultFont", 10, "bold")).pack(anchor="w", pady=(10, 2))
        ttk.Combobox(output, textvariable=draft["publish_layout"], state="readonly",
                     values=PUBLICATION_LAYOUTS).pack(fill="x", pady=(2, 5))
        ttk.Label(output, text="Dataset name template", font=("TkDefaultFont", 10, "bold")).pack(anchor="w", pady=(3, 2))
        ttk.Entry(output, textvariable=draft["publish_template"]).pack(fill="x")
        ttk.Label(output, text="Tokens: [name], [calibration], [calibration_id], [configuration], [index], [mode]. The same naming rule applies to all layouts.", wraplength=475).pack(anchor="w", pady=4)
        ttk.Label(output, text="Saving settings does not publish a Dataset.", wraplength=470).pack(
            anchor="w", pady=(12, 0))

        browser = tab("Dataset browser")
        ttk.Label(browser, text="Source Dataset discovery", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Checkbutton(browser, text="Automatically check for Dataset changes (every 5 seconds)",
                        variable=draft["catalog_auto"]).pack(anchor="w", pady=(12, 6))
        ttk.Label(browser, text="Choose a source namespace with Namespace → Select Dataset namespace. "
                  "The selection only filters the Image Dataset list and never moves or renames "
                  "Datasets. A previously linked source is retained.", wraplength=475).pack(anchor="w", pady=(8, 14))
        ttk.Button(browser, text="Select Dataset namespace...",
                   command=self.open_namespace_picker).pack(anchor="w", pady=(0, 12))
        ttk.Label(browser, textvariable=self.catalog_diag, wraplength=475).pack(anchor="w")
        ttk.Button(browser, text="Refresh Dataset catalog now",
                   command=lambda: self.check_dataset_catalog(force=True)).pack(anchor="w")
        ttk.Label(browser, text="If the source image is replaced, deleted, or renamed, "
                  "digitizing and publishing are blocked. Existing points and calibration are preserved.",
                  wraplength=475).pack(anchor="w", pady=(15, 0))

        profiles = tab("Configurations")
        ttk.Label(profiles, text="Session configuration profiles", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Label(profiles, text="Select a profile with the selector in the main window.\n"
                  "Profiles are preserved in the GX-TXT Session.", wraplength=470).pack(anchor="w", pady=(5, 10))
        profile_names = [f"{cfg.get('name', 'Untitled')}  [{doc}]" for doc,cfg in self.documents.items()]
        names = tk.Listbox(profiles, height=8, exportselection=False)
        names.pack(fill="both", expand=True)
        for name in profile_names:
            names.insert("end", name)
        for idx, doc in enumerate(self.documents):
            if doc == self.current_doc_id:
                names.selection_set(idx)
                names.see(idx)
                break
        ttk.Label(profiles, text="Profile actions: Configuration menu → New / Rename / Duplicate / Delete.",
                  wraplength=470).pack(anchor="w", pady=(10, 0))

        def apply():
            try:
                radius = int(draft["radius"].get())
                if not 0 <= radius <= 25:
                    raise ValueError("Snap radius must be between 0 and 25 pixels.")
                length = float(draft["length"].get().strip().replace(",", "."))
                if not math.isfinite(length) or length <= 0:
                    raise ValueError("Default scale length must be a positive number.")
                unit = draft["unit"].get().strip()
                if unit not in ("pm", "nm", "µm", "μm", "um", "mm", "cm", "dm", "m", "km", "Å", "A", "in", "ft"):
                    raise ValueError("Choose a recognized physical length unit.")
                edge = draft["edge"].get()
                if edge not in EDGE_MODES:
                    raise ValueError("Choose a valid tick reference.")
                vsize = int(draft["verify_size"].get())
                vwidth = int(draft["verify_width"].get())
                vcolor = draft["verify_color"].get().strip()
                if not 4 <= vsize <= 64 or not 1 <= vwidth <= 12:
                    raise ValueError("Verification marker size must be 4..64 px, width 1..12 px.")
                if not re.fullmatch(r"#[0-9a-fA-F]{6}", vcolor):
                    raise ValueError("Marker color must be #RRGGBB.")
                naming_template = validate_template(draft["publish_template"].get())
                display_opacity=int(draft["canvas_opacity"].get())
                display_bg=draft["canvas_background"].get().strip()
                if not 0<=display_opacity<=100:raise ValueError("Image opacity must be between 0 and 100%.")
                if not re.fullmatch(r"#[0-9a-fA-F]{6}",display_bg):raise ValueError("Canvas background must be #RRGGBB.")
                ordering=normalize_ordering({"monotonicity":draft["curve_monotonicity"].get(),"source":draft["point_order_source"].get()})
                output_count=int(draft["assist_output_points"].get())
                if output_count==1 or not 0<=output_count<=10000:
                    raise ValueError("Assisted output points must be 0 or 2..10000.")
            except ValueError as exc:
                messagebox.showerror("Invalid viewer settings", str(exc), parent=window)
                apply_status.set("Invalid settings; nothing applied")
                return False
            changed_prefs = {
                "show_point_numbers": draft["numbers"].get(),
                "show_scale_overlay": draft["overlay"].get(),
                "show_calibration_corners": draft["corners"].get(),
                "snap_enabled": draft["snapping"].get(),
                "snap_radius": radius,
                "scale_edge": EDGE_MODES[edge],
                "y_direction": draft["direction"].get(),
                "scale_length": draft["length"].get().strip().replace(",", "."),
                "scale_unit": unit,
                "auto_catalog_check": draft["catalog_auto"].get(),
                "verification_marker_size": vsize,
                "verification_marker_width": vwidth,
                "verification_marker_color": vcolor,
                "publication_layout": draft["publish_layout"].get(),
                "publication_name_template": naming_template,
            }
            try:
                self._commit_pref_values(changed_prefs, captured_shared_settings)
                # A second click on Apply must use the fresh versioned CORE
                # values as the optimistic-commit baseline, not the original
                # snapshot captured when the window first opened.
                captured_shared_settings.clear()
                captured_shared_settings.update(self.shared_settings)
            except (RpcError, ValueError) as exc:
                messagebox.showerror("GX-TXT Configuration", str(exc), parent=window)
                apply_status.set("CORE settings could not be saved")
                return False
            if self.current_doc_id:
                self.snapshot()
            self.output_dataset_id.set(draft["dataset_id"].get().strip())
            self.output_display_name.set(draft["display_name"].get().strip())
            self.curve_monotonicity.set(ordering["monotonicity"])
            self.point_order_source.set(ordering["source"])
            self.assist_output_points.set(str(output_count))
            order_project(self.project, ordering)
            self.refresh_curve_tree()
            self.update_selected()
            self._appearance_loading=True
            try:
                self.opacity_var.set(display_opacity)
                self.canvas_bg_var.set(display_bg.lower())
                self._apply_canvas_appearance()
            finally:self._appearance_loading=False
            self.redraw()
            if self.current_doc_id and self.persist() is not True:
                apply_status.set("Session configuration save failed")
                return False
            apply_status.set("Applied and saved to the selected configuration")
            return True

        # Buttons always visible, independent of active tab height. Apply is
        # deliberately NON-CLOSING to let the user verify the result on screen.
        ttk.Button(footer, text="Cancel", command=window.destroy).pack(side="right", padx=(6, 0))
        def apply_and_close():
            if apply():
                window.destroy()
        ttk.Button(footer, text="OK", command=apply_and_close).pack(side="right", padx=(6, 0))
        ttk.Button(footer, text="Apply", command=apply).pack(side="right", padx=(6, 0))
        def dirty(*_):
            if window.winfo_exists():
                apply_status.set("Changes not applied")
        for value in draft.values():
            value.trace_add("write", dirty)
        window.protocol("WM_DELETE_WINDOW", window.destroy)
        window.focus_set()

    def open_help(self):
        """Ask the GX-TXT host to display MANUAL.md using its GX-Markup renderer.

        Tcl owns Documentation API / Tk rendering. The Python viewer must not
        substitute a partial Markdown implementation for the CORE renderer.
        The nonblocking request also keeps the Curve Digitalizer GUI responsive.
        """
        if self.help_request_id is not None:
            return  # Ignore repeated F1 clicks while the host is opening Help.
        try:
            request_id = self.rpc.begin("HELP_OPEN")
        except RpcError as exc:
            messagebox.showerror("Curve Digitalizer Help", str(exc), parent=self.root)
            return
        self.help_request_id = request_id
        deadline = time.monotonic() + min(20, RPC_TIMEOUT_SECONDS)

        def finish_help():
            if self.help_request_id != request_id:
                return
            try:
                result = self.rpc.poll_response(request_id)
            except RpcError as exc:
                self.help_request_id = None
                messagebox.showerror("Curve Digitalizer Help", str(exc), parent=self.root)
                return
            if result is not None:
                self.help_request_id = None
                return
            if time.monotonic() >= deadline:
                self.help_request_id = None
                messagebox.showerror("Curve Digitalizer Help",
                                     "GX-TXT did not confirm opening the rendered manual. "
                                     "Check the host log before trying again.", parent=self.root)
                return
            if self.root.winfo_exists():
                self.root.after(80, finish_help)
        self.root.after(80, finish_help)

    def _apply_canvas_appearance(self):
        if not hasattr(self,"canvas"): return
        for widget in (self.canvas,self.compare_original_canvas,self.compare_processed_canvas):
            try:widget.set_appearance(self.canvas_bg_var.get(),self.opacity_var.get())
            except (ValueError,tk.TclError):return
        self.redraw()

    def _commit_canvas_appearance(self):
        self._appearance_after=None
        if self._appearance_loading or not self.current_doc_id:return
        try:
            color=str(self.canvas_bg_var.get())
            if not re.fullmatch(r"#[0-9a-fA-F]{6}",color):
                self.status.set("Canvas background must be #RRGGBB.")
                return
            self.config.setdefault("display",{}).update({
                "image_opacity":max(0,min(100,int(self.opacity_var.get()))),
                "canvas_background":color.lower()})
            self.persist_later()
        except (ValueError,tk.TclError) as exc:
            self.status.set(f"Invalid canvas appearance: {exc}")

    def canvas_appearance_changed(self):
        if self._appearance_loading or self.loading_ui:return
        self._apply_canvas_appearance()
        if self._appearance_after is not None: self.root.after_cancel(self._appearance_after)
        self._appearance_after=self.root.after(350,self._commit_canvas_appearance)

    def _update_color_swatch(self):
        if not hasattr(self,"canvas_color_swatch"):return
        color=self.canvas_bg_var.get()
        if re.fullmatch(r"#[0-9a-fA-F]{6}",color):
            self.canvas_color_swatch.configure(bg=color,activebackground=color)

    def _background_color_changed(self):
        self._update_color_swatch()
        if hasattr(self,"canvas"):self.canvas_appearance_changed()

    def choose_canvas_color(self):
        color=colorchooser.askcolor(color=self.canvas_bg_var.get(),parent=self.root,title="Canvas background")[1]
        if color:
            self.canvas_bg_var.set(color)
            self.canvas_appearance_changed()

    def build_ui(self):
        # Only the active selectors remain in the top toolbar. Actions live in menus.
        top = ttk.Frame(self.root, padding=(8, 5))
        top.pack(fill="x")
        ttk.Label(top, text="Configuration", font=("TkDefaultFont", 10, "bold")).pack(side="left")
        self.config_combo = ttk.Combobox(top, textvariable=self.config_var, state="readonly", width=33)
        self.config_combo.pack(side="left", padx=(7, 22))
        self.config_combo.bind("<<ComboboxSelected>>", self.on_configuration_selected)
        ttk.Label(top, text="Image Dataset", font=("TkDefaultFont", 10, "bold")).pack(side="left")
        self.source_combo = ttk.Combobox(top, textvariable=self.source_var, state="readonly",
                                         values=list(self.datasets), width=44)
        self.source_combo.pack(side="left", padx=(7, 0), fill="x", expand=True)
        self.source_combo.bind("<<ComboboxSelected>>", self.on_source_selected)
        # Catalog status, refresh and browsing controls live under Configuration/Dataset
        # instead of consuming a second full toolbar row.

        # A bottom-anchored status bar does not get clipped by a tall Calibration tab.
        self.status_label = ttk.Label(self.root, textvariable=self.status, anchor="w",
                                      relief="sunken", padding=(5, 3))
        self.status_label.pack(side="bottom", fill="x", padx=8, pady=(3, 4))
        self.source_diag.trace_add("write", self._show_source_warning_in_status)

        pane = ttk.Panedwindow(self.root, orient="horizontal")
        pane.pack(fill="both", expand=True, padx=8)
        controls = ttk.Frame(pane, width=545)
        viewer = ttk.Frame(pane)
        pane.add(controls, weight=0)
        pane.add(viewer, weight=1)
        self.controls_pane = pane
        # Give the traditional full-width Curves controls a comfortable width.
        # Only the assisted tracing frame contains two functional subcolumns.
        self.root.after_idle(lambda: pane.sashpos(0, min(555, max(455, self.root.winfo_width() - 480))))

        self.notebook = ttk.Notebook(controls)
        self.notebook.pack(fill="both", expand=True)
        self.build_source_tab()
        self.build_image_processing_tab()
        self.build_calibration_tab()
        self.build_curves_tab()
        self.build_publish_tab()
        self.build_notes_tab()

        viewer.grid_rowconfigure(0, weight=1)
        viewer.grid_columnconfigure(0, weight=1)
        self.normal_view = ttk.Frame(viewer)
        self.normal_view.grid(row=0, column=0, sticky="nsew")
        self.canvas = ImageCanvas(self.normal_view, on_cursor=self.on_cursor, on_left_press=self.canvas_press,
                                  on_left_drag=self.canvas_drag, on_left_release=self.canvas_release,
                                  on_right_click=self.canvas_right_click,
                                  on_view_changed=self.view_changed)
        self.canvas.pack(fill="both", expand=True)
        self.comparison_view = ttk.Panedwindow(viewer, orient="horizontal")
        self.comparison_view.grid(row=0, column=0, sticky="nsew")
        self.compare_left_frame = ttk.Frame(self.comparison_view)
        self.compare_right_frame = ttk.Frame(self.comparison_view)
        self.comparison_view.add(self.compare_left_frame, weight=1)
        self.comparison_view.add(self.compare_right_frame, weight=1)
        self.compare_original_canvas = ImageCanvas(self.compare_left_frame,
                        on_cursor=self.on_cursor, on_view_changed=lambda: self._compare_view_changed("original"))
        self.compare_processed_canvas = ImageCanvas(self.compare_right_frame,
                        on_cursor=self.on_cursor, on_view_changed=lambda: self._compare_view_changed("processed"))
        for frame, label, canvas in ((self.compare_left_frame, "Original", self.compare_original_canvas),
                                    (self.compare_right_frame, "Processed", self.compare_processed_canvas)):
            ttk.Label(frame, text=label, anchor="center").pack(side="top", fill="x")
            canvas.pack(side="top", fill="both", expand=True)
        self.normal_view.tkraise()
        self.notebook.bind("<<NotebookTabChanged>>", self._on_tab_changed)
        self.build_menus()
        self._apply_canvas_appearance()

    def build_source_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Source")
        self.source_tab = tab
        ttk.Label(tab, text="Source information", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        self.source_info = tk.Text(tab, height=20, width=48, wrap="word", state="disabled")
        self.source_info.pack(fill="both", expand=True, pady=(6, 0))

    def build_image_processing_tab(self):
        outer = ttk.Frame(self.notebook)
        self.notebook.add(outer, text="Image Processing")
        self.processing_tab = outer
        viewport = tk.Canvas(outer, highlightthickness=0, borderwidth=0, width=400)
        scroll = ttk.Scrollbar(outer, orient="vertical", command=viewport.yview)
        viewport.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        viewport.pack(side="left", fill="both", expand=True)
        tab = ttk.Frame(viewport, padding=7)
        window_id = viewport.create_window(0, 0, anchor="nw", window=tab)
        viewport.bind("<Configure>", lambda event: viewport.itemconfigure(window_id, width=event.width))
        tab.bind("<Configure>", lambda _event: viewport.configure(scrollregion=viewport.bbox("all")))
        ttk.Label(tab, text="Non-geometric image enhancement", font=("TkDefaultFont", 10, "bold")).pack(anchor="w")
        ttk.Label(tab, text="Contrast, channels and filters only. Original pixels and calibration remain unchanged.",
                  wraplength=370).pack(anchor="w", pady=(2, 6))
        ttk.Label(tab, textvariable=self.processing_status, wraplength=375,
                  foreground="#1b638a").pack(fill="x", pady=(0, 7))
        compare_box = ttk.LabelFrame(tab, text="View and processing controls", padding=6)
        compare_box.pack(fill="x", pady=(1, 7))
        ttk.Checkbutton(compare_box, text="Compare original and processed images (split view)",
                        variable=self.processing_compare, command=lambda: self._processing_pref_changed("processing_compare",
                            self.processing_compare.get())).pack(anchor="w", pady=2)
        ttk.Checkbutton(compare_box, text="Synchronize pan and zoom", variable=self.processing_sync_views,
                        command=lambda: self._processing_pref_changed("processing_sync_views",
                            self.processing_sync_views.get())).pack(anchor="w", pady=2)
        ttk.Checkbutton(compare_box, text="Show digitized curve overlays in comparison", variable=self.processing_overlay,
                        command=lambda: self._processing_pref_changed("processing_show_curve_overlays",
                            self.processing_overlay.get())).pack(anchor="w", pady=2)
        ttk.Checkbutton(compare_box, text="Live preview after changing a control", variable=self.processing_live,
                        command=lambda: self._processing_pref_changed("processing_live_preview",
                            self.processing_live.get())).pack(anchor="w", pady=2)
        modes = ttk.Frame(tab); modes.pack(fill="x", pady=(4, 3))
        ttk.Label(modes, text="Filter order:").pack(side="left")
        ttk.Radiobutton(modes, text="Standard", variable=self.processing_filter_mode,
                        value="standard", command=self._processing_mode_changed).pack(side="left", padx=(7, 3))
        ttk.Radiobutton(modes, text="Advanced", variable=self.processing_filter_mode,
                        value="advanced", command=self._processing_mode_changed).pack(side="left", padx=3)
        ttk.Label(tab, text="Enable individual filters and adjust their parameters. The source raster is unchanged.",
                  wraplength=375).pack(anchor="w", pady=(0, 4))
        self.processing_filter_controls = FilterControls(tab, self._filter_controls_changed)
        self.processing_filter_controls.pack(fill="x", pady=(0, 7))
        self.processing_advanced_box = ttk.LabelFrame(tab, text="Advanced · exact processing order", padding=6)
        ttk.Label(self.processing_advanced_box, text="Select a step to change its position. Repeated operations are preserved.",
                  wraplength=350).pack(anchor="w")
        items = ttk.Frame(self.processing_advanced_box); items.pack(fill="x", expand=True, pady=3)
        self.processing_list = tk.Listbox(items, exportselection=False, height=6, activestyle="none")
        self.processing_list.pack(side="left", fill="both", expand=True)
        sy = ttk.Scrollbar(items, orient="vertical", command=self.processing_list.yview)
        sy.pack(side="right", fill="y"); self.processing_list.configure(yscrollcommand=sy.set)
        actions = ttk.Frame(self.processing_advanced_box); actions.pack(fill="x", pady=(2, 3))
        for caption, command in (("Remove", self.remove_processing_operation),
                                 ("Move up", lambda: self.move_processing_operation(-1)),
                                 ("Move down", lambda: self.move_processing_operation(1))):
            ttk.Button(actions, text=caption, command=command).pack(side="left", padx=(0, 5))
        actions = ttk.Frame(tab); actions.pack(fill="x", pady=(4, 6))
        ttk.Button(actions, text="Reset filters", command=self.reset_processing).pack(side="left")
        ttk.Button(tab,text="Try automatic enhancement",command=self.try_auto_enhancement).pack(fill="x",pady=(2,3))
        ttk.Button(tab,text="Restore filters before auto enhancement",command=self.restore_auto_enhancement).pack(fill="x",pady=(0,5))
        ttk.Checkbutton(actions, text="Show processed preview", variable=self.processing_show_result,
                        command=self._switch_processing_preview).pack(side="left", padx=8)
        ttk.Button(tab, text="Apply processing / Preview", command=self.process_image_preview).pack(
            fill="x", pady=(2, 8))
        self._processing_mode_visibility()
        output = ttk.LabelFrame(tab, text="Publish processed Image Dataset", padding=7)
        output.pack(fill="x")
        ttk.Label(output, text="Image Dataset ID").grid(row=0, column=0, sticky="w")
        ttk.Entry(output, textvariable=self.processing_dataset_id, width=23).grid(
            row=0, column=1, sticky="ew", padx=(4, 0))
        ttk.Label(output, text="Image description").grid(row=1, column=0, sticky="w")
        ttk.Entry(output, textvariable=self.processing_display_name, width=23).grid(
            row=1, column=1, sticky="ew", padx=(4, 0))
        output.columnconfigure(1, weight=1)
        ttk.Button(output, text="Publish image.raster Dataset...", command=self.publish_processed_image).grid(
            row=2, column=0, columnspan=2, sticky="ew", pady=(6, 0))
        ttk.Label(tab, text="Publishing is optional. The source image remains unchanged; "
                            "output is an independent canonical image.raster Dataset.",
                  wraplength=365).pack(anchor="w", pady=(7, 0))
        self._refresh_processing_list()

    def _processing_pref_changed(self, key, value):
        try:
            self._commit_pref_values({key: value})
        except RpcError as exc:
            self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
            messagebox.showerror("GX-TXT Configuration", str(exc), parent=self.root)
        self._update_processing_view_layout()
        if self.processing_sync_views.get() and hasattr(self, "compare_original_canvas"):
            self._compare_view_changed("original")
        self.redraw()

    def _processing_mode_visibility(self):
        if not hasattr(self, "processing_advanced_box"): return
        if self.processing_filter_mode.get() == "advanced":
            self.processing_advanced_box.pack(fill="x", pady=(2, 6), before=self.processing_filter_controls)
        else:
            self.processing_advanced_box.pack_forget()

    def _processing_mode_changed(self):
        mode = self.processing_filter_mode.get()
        if mode == "standard":
            # Explicit Standard selection restores the documented processing order.
            self.processing_operations = sorted(self.processing_operations,
                key=lambda op: STANDARD_ORDER.index(op["kind"]))
            self._processing_invalidate()
            self._refresh_processing_list()
        self._processing_mode_visibility()
        self._processing_pref_changed("processing_filter_mode", mode)

    def _refresh_processing_list(self):
        if hasattr(self, "processing_filter_controls") and self.processing_filter_controls:
            self.processing_filter_controls.load_operations(self.processing_operations)
        if not hasattr(self, "processing_list"): return
        selected = self.processing_list.curselection()
        self.processing_list.delete(0, "end")
        for i, op in enumerate(self.processing_operations, 1):
            self.processing_list.insert("end", f"{i:02d}  {op['kind']}  {op['value']}")
        if selected and selected[0] < len(self.processing_operations):
            self.processing_list.selection_set(selected[0])

    def _filter_controls_changed(self, kind, enabled, value):
        try:
            updated = merge_filter_operations(self.processing_operations, kind, enabled, value,
                advanced=(self.processing_filter_mode.get() == "advanced"))
            if updated == self.processing_operations: return
        except ProcessingError as exc:
            self.processing_status.set(f"Invalid filter setting: {exc}")
            return
        self.processing_operations = updated
        self._refresh_processing_list()
        self._processing_invalidate()

    def _on_tab_changed(self, _event=None):
        self._assist_move_target=None
        if self._assist_drag is not None:
            self._assist_drag=None;self._assist_preview_cursor=None
        if self.dragging:
            # Cancel an in-progress drag rather than keeping an uncommitted point.
            previous = self.drag_snapshot
            self.dragging = False
            self.drag_snapshot = None
            if previous is not None:
                self.restore_snapshot(previous, persist=False)
        self._update_processing_view_layout()
        self.redraw()

    def _is_curves_tab(self):
        return hasattr(self, "curves_tab") and self.notebook.select() == str(self.curves_tab)

    def _is_calibration_tab(self):
        return hasattr(self, "calibration_tab") and self.notebook.select() == str(self.calibration_tab)

    def _is_processing_tab(self):
        return hasattr(self, "processing_tab") and self.notebook.select() == str(self.processing_tab)

    def _update_processing_view_layout(self):
        if not hasattr(self, "comparison_view"): return
        if self._is_processing_tab() and self.processing_compare.get():
            self._refresh_comparison_images()
            self.comparison_view.tkraise()
        else:
            self.normal_view.tkraise()
        self._switch_processing_preview(persist=False)

    def _refresh_comparison_images(self, *, reset_views=False):
        if not hasattr(self, "compare_original_canvas") or self.image is None: return
        for canvas, image in ((self.compare_original_canvas, self.image),
                              (self.compare_processed_canvas, self.processed_image or self.image)):
            if (reset_views or canvas.original_image is None
                    or canvas.original_image.size != image.size):
                # ImageCanvas will fit exactly once when Tk reports usable pane
                # dimensions. No reset occurs on filter or tab changes.
                canvas.set_image(image)
            else:
                canvas.original_image = image
                canvas._update_display_image()
                canvas.request_render()
        self.redraw()

    def _compare_view_changed(self, source):
        if self._compare_view_guard or not hasattr(self, "compare_original_canvas"): return
        if self.processing_sync_views.get() and self._is_processing_tab():
            self._compare_view_guard = True
            try:
                a, b = self.compare_original_canvas, self.compare_processed_canvas
                (b if source == "original" else a).copy_view_from(a if source == "original" else b)
            finally:
                self._compare_view_guard = False
        self.redraw()

    def _schedule_processing_preview(self):
        if self._processing_update_after is not None:
            self.root.after_cancel(self._processing_update_after)
        self._processing_update_after = None
        if (self.processing_live.get() and self.processing_operations and self.image is not None
                and self.processing_executable and not self.stale_source):
            self._processing_update_after = self.root.after(550, self._debounced_processing_preview)

    def _debounced_processing_preview(self):
        self._processing_update_after = None
        if self.processing_active:
            self._processing_resubmit = True
            return
        self.process_image_preview()

    def _processing_invalidate(self, *, save=True):
        self.processed_image = None
        self.processed_fingerprint = None
        if self.image is not None and hasattr(self, "canvas"):
            self.canvas.original_image = self.image
            self.canvas._update_display_image()
            self.gray_image = self.image.convert("L")
            self.canvas.request_render(); self.redraw()
        self._refresh_comparison_images()
        self.processing_status.set("Pipeline changed; processed preview is not yet updated.")
        if save:
            self.persist_later()
            self._schedule_processing_preview()

    def remove_processing_operation(self):
        indices = self.processing_list.curselection()
        if not indices: return
        self.processing_operations.pop(indices[0]); self._refresh_processing_list(); self._processing_invalidate()

    def move_processing_operation(self, direction):
        indices = self.processing_list.curselection()
        if not indices: return
        i = indices[0]; j = i + direction
        if j < 0 or j >= len(self.processing_operations): return
        self.processing_operations[i], self.processing_operations[j] = (
            self.processing_operations[j], self.processing_operations[i])
        self._refresh_processing_list(); self.processing_list.selection_clear(0, "end")
        self.processing_list.selection_set(j); self._processing_invalidate()

    def reset_processing(self):
        if not self.processing_operations and self.processed_image is None: return
        self.processing_operations = []
        self._refresh_processing_list(); self._processing_invalidate()
        self.processing_status.set("Original image shown. Processing pipeline cleared.")

    def try_auto_enhancement(self):
        """Suggest and preview a validated ImageMagick pipeline; never publish."""
        if not self.require_working_source():return
        if self.processing_active:
            self.processing_status.set("Image Processing is busy; retry automatic enhancement shortly.")
            return
        try:
            suggested,reason=recommend_enhancement(self.image)
            if not suggested:return
            self._auto_previous_pipeline=(self.current_doc_id,
                (self.config.get("source") or {}).get("sha256"),copy.deepcopy(self.processing_operations))
            self.processing_operations=suggested
            self.processing_filter_mode.set("standard")
            self._processing_mode_visibility()
            self._refresh_processing_list()
            self._processing_invalidate()
            self.processing_status.set("Automatic suggestion: "+reason+" Review before publishing.")
            if self.processing_executable:
                self.process_image_preview()
            else:
                self.processing_status.set("Automatic filters suggested, but ImageMagick is unavailable: "+reason)
        except (ProcessingError,ValueError,OSError) as exc:
            self.processing_status.set("Unable to suggest automatic enhancement: "+str(exc))

    def restore_auto_enhancement(self):
        state=self._auto_previous_pipeline
        if not state:return
        doc,sha,operations=state
        if (doc!=self.current_doc_id or sha!=(self.config.get("source") or {}).get("sha256")):
            self._auto_previous_pipeline=None
            self.processing_status.set("Previous filter settings belong to another source or configuration.")
            return
        self.processing_operations=copy.deepcopy(operations)
        self._auto_previous_pipeline=None
        self._refresh_processing_list();self._processing_invalidate()
        self.processing_status.set("Previous filter operations restored.")

    def _resolve_image_processing_tool(self):
        try:
            response = self.rpc.call("IMAGE_TOOL")
            tool, sep, detail = response.partition("\t")
            if tool != "unavailable" and tool and sep:
                self.processing_executable = tool
                self.processing_engine_version = detail
                self.processing_status.set("ImageMagick available: " + detail[:140])
                if self.image is not None and self.processing_operations and not self.stale_source:
                    self.process_image_preview()
            else:
                self.processing_status.set("ImageMagick unavailable. Configure it in GX-TXT Configuration > Runtime.")
        except RpcError as exc:
            self.processing_status.set(f"ImageMagick discovery failed: {exc}")

    def _switch_processing_preview(self, *, persist=True):
        if self.image is None or not hasattr(self, "canvas"): return
        display = (self.processed_image if (self.processing_show_result.get()
                   and self.processed_image is not None) else self.image)
        # Keep the processed preview usable for tracing from Curves too.
        self.canvas.original_image = display
        self.canvas._update_display_image()
        self.gray_image = display.convert("L")
        self.canvas.request_render()
        self._refresh_comparison_images()
        self.redraw()
        if persist: self.persist_later()

    def process_image_preview(self):
        if not self.require_working_source(): return
        if self.processing_active:
            self._processing_resubmit = True
            self.processing_status.set("Image processing is already running. Latest settings queued.")
            return
        try: operations = normalize_operations(self.processing_operations)
        except ProcessingError as exc:
            messagebox.showerror("Image Processing", str(exc), parent=self.root);return
        if not operations:
            self._processing_invalidate();self.processing_status.set("No processing operations selected.")
            return
        if not self.processing_executable:
            messagebox.showerror("Image Processing", "ImageMagick is not available from GX-TXT Runtime configuration.", parent=self.root)
            return
        self.processing_active = True
        source_id = self.config["source"]["dataset_id"]
        source_sha = self.config["source"]["sha256"]
        fingerprint = image_fingerprint(source_id, source_sha, operations, self.processing_engine_version)
        self.processing_status.set("Processing image with ImageMagick...")
        input_image = self.image.copy()
        # Bind worker output to the originating Session queue. After a Session
        # switch, the new viewer gets a fresh queue; old workers cannot inject
        # results into it even if Dataset IDs and image fingerprints coincide.
        target_queue = self.processing_result_queue
        def worker():
            try:
                processed = apply_processing(input_image, self.processing_executable, operations)
                target_queue.put((True, processed, fingerprint))
            except Exception as exc:
                target_queue.put((False, str(exc), fingerprint))
        threading.Thread(target=worker, name="GXCurveImageProcessing", daemon=True).start()

    def _poll_image_processing(self):
        try:
            while True:
                success, result, fingerprint = self.processing_result_queue.get_nowait()
                self.processing_active = False
                current_source = self.config.get("source", {}) if self.config else {}
                current_fingerprint = image_fingerprint(current_source.get("dataset_id", ""),
                    current_source.get("sha256", ""), self.processing_operations,
                    self.processing_engine_version)
                if fingerprint != current_fingerprint:
                    self.processing_status.set("Discarded obsolete processing result.")
                    if self.processing_live.get(): self._processing_resubmit = True
                    continue
                if success:
                    self.processed_image = result
                    self.processed_fingerprint = fingerprint
                    self.processing_status.set(f"Ready: {result.width} × {result.height} px; raster geometry unchanged.")
                    self._switch_processing_preview()
                else:
                    self.processing_status.set("Processing failed: " + result[:300])
                    messagebox.showerror("Image Processing", result, parent=self.root)
        except queue.Empty:
            pass
        if not self.processing_active and self._processing_resubmit and self.processing_live.get():
            self._processing_resubmit = False
            self._schedule_processing_preview()
        if self.root.winfo_exists():self.root.after(150, self._poll_image_processing)

    def publish_processed_image(self):
        if not self.require_working_source():return
        if self.processing_active:
            messagebox.showwarning("Image Processing", "Image processing is still running.", parent=self.root);return
        source = self.config.get("source", {})
        expected = image_fingerprint(source.get("dataset_id", ""), source.get("sha256", ""),
                                     self.processing_operations, self.processing_engine_version)
        if self.processed_image is None or self.processed_fingerprint != expected:
            messagebox.showerror("Image Processing", "Apply the current processing pipeline before publishing.", parent=self.root);return
        out_id = self.processing_dataset_id.get().strip()
        if not out_id:
            out_id = source.get("dataset_id", "image") + ".processed"
            self.processing_dataset_id.set(out_id)
        if out_id == source.get("dataset_id"):
            messagebox.showerror("Image Processing", "The output Dataset ID must differ from its source.", parent=self.root);return
        label = self.processing_display_name.get().strip() or f"Processed {source['dataset_id']}"
        if not messagebox.askyesno("Image Processing", f"Publish the current processed image as a new image.raster Dataset?\n\n{out_id}\nSource: {source['dataset_id']}\n\nThe original image is preserved.", parent=self.root):
            return
        stage = None
        try:
            fields = processing_metadata(source["dataset_id"], source["sha256"],
                source["dataset_id"], self.processed_image,
                self.processing_operations, self.processing_engine_version)
            records = "\n".join(b64e(k) + "\t" + b64e(str(v)) for k, v in sorted(fields.items()))
            stage = self.rpc.call("IMAGE_STAGE", self.session_token)
            self.processed_image.save(stage, format="PNG")
            response = self.rpc.call("IMAGE_PUBLISH", self.session_token, self.current_doc_id,
                source["dataset_id"], source["sha256"], out_id, label, stage, records,
                self.notes.get("1.0", "end-1c"))
            stage = None
            parts = response.split("\t", 2)
            if len(parts) not in (2, 3):
                raise ValueError("Invalid image publication receipt from GX-TXT.")
            registered, sha = parts[:2]
            self.processing_status.set(f"Published image Dataset '{registered}', SHA-256 {sha[:18]}...")
            if len(parts) == 3 and parts[2].startswith("failed:"):
                messagebox.showwarning("Image Processing", f"Image Dataset '{registered}' was published, but its Markdown notes could not be saved:\n{parts[2][7:]}", parent=self.root)
            self.check_dataset_catalog(force=True)
        except (OSError, RpcError, ProcessingError, ValueError) as exc:
            messagebox.showerror("Image Processing", f"Image Dataset publication failed:\n{exc}", parent=self.root)
        finally:
            if stage:
                try:self.rpc.call("IMAGE_STAGE_CANCEL", self.session_token, stage)
                except RpcError:pass

    def build_calibration_tab(self):
        tab = ttk.Frame(self.notebook, padding=6)
        self.notebook.add(tab, text="Calibration")
        self.calibration_tab = tab
        # Scientific axes: retain complete variable-schema UI.
        for col, text in enumerate(("", "X axis", "Y axis")):
            ttk.Label(tab, text=text, font=("TkDefaultFont", 9, "bold")).grid(
                row=0, column=col, sticky="w", padx=2, pady=(0, 3))
        rows = [("Label", self.x_name, self.y_name, "entry"),
                ("Unit", self.x_unit, self.y_unit, "unit"),
                ("Semantic role", self.x_role, self.y_role, "role"),
                ("Minimum", self.x_min, self.y_min, "entry"),
                ("Maximum", self.x_max, self.y_max, "entry"),
                ("Scale", self.x_scale, self.y_scale, "scale")]
        for row, (label, xv, yv, kind) in enumerate(rows, 1):
            ttk.Label(tab, text=label).grid(row=row, column=0, sticky="w", padx=2, pady=2)
            for col, variable in ((1, xv), (2, yv)):
                if kind in ("unit", "role", "scale"):
                    values = self.units if kind == "unit" else self.roles if kind == "role" else ("linear", "log")
                    widget = ttk.Combobox(tab, textvariable=variable, values=values,
                                          state="readonly" if kind == "scale" else "normal", width=15)
                else:
                    widget = ttk.Entry(tab, textvariable=variable, width=15)
                widget.grid(row=row, column=col, sticky="ew", padx=2, pady=2)
        ttk.Button(tab, text="Apply axis settings", command=lambda: self.commit_axes(True)).grid(
            row=7, column=0, columnspan=3, sticky="ew", pady=(4, 6))
        for col in (1, 2):
            tab.columnconfigure(col, weight=1)

        # A / B share one row; vertical space is reserved for the measurement manager.
        alternatives = ttk.Frame(tab)
        alternatives.grid(row=8, column=0, columnspan=3, sticky="ew", pady=(0, 5))
        alternatives.columnconfigure(0, weight=1, uniform="cal")
        alternatives.columnconfigure(1, weight=1, uniform="cal")
        automatic = ttk.LabelFrame(alternatives, text="A · Full image", padding=4)
        automatic.grid(row=0, column=0, sticky="nsew", padx=(0, 3))
        ttk.Label(automatic, text="Y direction:").pack(anchor="w")
        ttk.Combobox(automatic, textvariable=self.auto_y_direction, state="readonly", width=20,
                     values=("Upward (Cartesian)", "Downward (image pixels)")).pack(fill="x", pady=3)
        ttk.Button(automatic, text="Auto-calibrate full image",
                   command=self.auto_calibrate_full_image).pack(fill="x", pady=(3, 0))

        scaling = ttk.LabelFrame(alternatives, text="B · Scale bar", padding=4)
        scaling.grid(row=0, column=1, sticky="nsew", padx=(3, 0))
        ttk.Label(scaling, text="Tick reference:").pack(anchor="w")
        self.scale_edge_combo = ttk.Combobox(scaling, textvariable=self.scale_edge_convention,
                                             values=tuple(EDGE_MODES), state="readonly", width=20)
        self.scale_edge_combo.pack(fill="x", pady=(0, 2))
        self.scale_edge_combo.bind("<<ComboboxSelected>>", self.scale_convention_changed)
        select = ttk.Frame(scaling); select.pack(fill="x")
        ttk.Button(select, text="Detect", command=self.start_scale_detection).pack(side="left", fill="x", expand=True)
        ttk.Button(select, text="Endpoints", command=self.start_scale_manual).pack(side="left", fill="x", expand=True)
        length = ttk.Frame(scaling); length.pack(fill="x", pady=2)
        ttk.Entry(length, textvariable=self.scale_length, width=8).pack(side="left", fill="x", expand=True)
        ttk.Combobox(length, textvariable=self.scale_unit,
                     values=["µm", "nm", "mm", "cm", "m", "pm", "Å", "um", "μm", "in", "ft"],
                     width=6).pack(side="left", padx=(3, 0))
        ttk.Button(scaling, text="Apply scale", command=self.apply_image_scale).pack(fill="x")
        ttk.Button(scaling, text="Clear selection overlay",
                   command=self.cancel_scale_selection).pack(fill="x", pady=(3, 0))
        ttk.Label(tab, textvariable=self.scale_status, wraplength=490).grid(
            row=9, column=0, columnspan=3, sticky="ew", pady=(0, 3))

        calibration = ttk.LabelFrame(tab, text="Projective calibration and verification", padding=4)
        calibration.grid(row=10, column=0, columnspan=3, sticky="ew")
        calibration.columnconfigure(0, weight=1)
        calibration.columnconfigure(1, weight=2)
        corners = ttk.Frame(calibration); corners.grid(row=0, column=0, sticky="nsew", padx=(0, 5))
        for i, corner in enumerate(CORNER_ORDER):
            ttk.Button(corners, text=f"Set {CORNER_LABELS[corner]}",
                       command=lambda c=corner: self.start_corner(c)).grid(
                           row=i // 2, column=i % 2, sticky="ew", padx=1, pady=2)
        for i in (0, 1): corners.columnconfigure(i, weight=1)
        ttk.Button(corners, text="Clear corners", command=self.clear_calibration).grid(
            row=2, column=0, columnspan=2, sticky="ew", pady=2)
        ttk.Label(corners, textvariable=self.cal_status, wraplength=175, justify="left").grid(
            row=3, column=0, columnspan=2, sticky="w", pady=(3, 0))
        verification = ttk.LabelFrame(calibration, text="Calibration verification", padding=4)
        verification.grid(row=0, column=1, sticky="nsew", padx=(3, 0))
        ttk.Button(verification, text="Verify calibration...",
                   command=self.start_verification).pack(anchor="w", fill="x")
        self.verification_details = ttk.Frame(verification)
        expected = ttk.Frame(self.verification_details); expected.pack(fill="x", pady=(3, 0))
        ttk.Label(expected, text="Expected X").pack(side="left")
        ttk.Entry(expected, textvariable=self.exp_x, width=9).pack(side="left", padx=3)
        ttk.Label(expected, text="Expected Y").pack(side="left")
        ttk.Entry(expected, textvariable=self.exp_y, width=9).pack(side="left", padx=3)
        ttk.Button(self.verification_details, text="Clear verification",
                   command=self.clear_verification).pack(anchor="w", pady=2)
        ttk.Label(self.verification_details, textvariable=self.verify_result,
                  justify="left", wraplength=300).pack(anchor="w")

        manager = ttk.LabelFrame(tab, text="Calibration measurements", padding=4)
        manager.grid(row=11, column=0, columnspan=3, sticky="nsew", pady=(5, 0))
        manager.columnconfigure(0, weight=1); manager.rowconfigure(0, weight=1)
        self.measurement_table = ttk.Treeview(manager, columns=("label", "status"),
                                              show="headings", height=5, selectmode="browse")
        self.measurement_table.heading("label", text="Measurement")
        self.measurement_table.heading("status", text="State")
        self.measurement_table.column("label", width=225, minwidth=115)
        self.measurement_table.column("status", width=125, minwidth=70)
        self.measurement_table.grid(row=0, column=0, sticky="nsew")
        sy = ttk.Scrollbar(manager, orient="vertical", command=self.measurement_table.yview)
        sy.grid(row=0, column=1, sticky="ns")
        self.measurement_table.configure(yscrollcommand=sy.set)
        self.measurement_table.bind("<<TreeviewSelect>>", self.on_measurement_selected)
        buttons = ttk.Frame(manager); buttons.grid(row=1, column=0, columnspan=2, sticky="ew", pady=2)
        for label, command in (("New", self.new_measurement), ("Activate", self.activate_measurement),
                               ("Accept", self.accept_measurement), ("Reject", self.reject_measurement),
                               ("Cancel draft", self.cancel_measurement), ("Rename", self.rename_measurement),
                               ("Delete", self.delete_measurement)):
            ttk.Button(buttons, text=label, command=command).pack(side="left", padx=1)
        tab.rowconfigure(11, weight=1)
        self.refresh_measurements()


    def _verification_mode_changed(self):
        if self.mode.get() != "verify" and self.verify_point is not None:
            self.verify_point = None
            self.verify_result.set("")
            self.redraw()

    def start_verification(self):
        if not self.require_working_source():
            return
        self.verify_panel_open = True
        self.verification_details.pack(fill="x", pady=3)
        self.mode.set("verify")
        self.status.set("Verification mode: select a reference point on the image. Esc closes.")
        self.redraw()

    def clear_verification(self):
        self.mode.set("add")
        self.verify_point = None
        self.verify_result.set("")
        self.verify_panel_open = False
        self.verification_details.pack_forget()
        self.redraw()

    def update_verification(self):
        if self.verify_point is not None:
            self.verify(*self.verify_point, draw=False)

    def _verification_escape(self, _event=None):
        if self.mode.get() == "verify":
            self.clear_verification()
            return "break"

    def _measurements(self):
        group = self.config.get("calibration_measurements")
        if not isinstance(group, dict) or not group.get("items"):
            group = {"group_id": "calgrp_" + uuid.uuid4().hex,
                     "active_id": "meas_" + uuid.uuid4().hex,
                     "items": []}
            group["items"].append({"id": group["active_id"], "label": "Measurement 1",
                                   "state": "accepted" if self.project.calibration_ready() else "draft",
                                   "axes": {"x": self.project.x_axis.to_dict(), "y": self.project.y_axis.to_dict()},
                                   "calibration": self.project.calibration.to_dict(),
                                   "scale_reference": copy.deepcopy(self.config.get("scale_reference"))})
            self.config["calibration_measurements"] = group
        return group

    def _sync_active_measurement(self):
        group = self._measurements()
        for item in group["items"]:
            if item["id"] == group["active_id"]:
                item["axes"] = {"x": self.project.x_axis.to_dict(), "y": self.project.y_axis.to_dict()}
                item["calibration"] = self.project.calibration.to_dict()
                item["scale_reference"] = copy.deepcopy(self.config.get("scale_reference"))
                # Preserve user rejection; a finished draft can be explicitly accepted.
                break

    def refresh_measurements(self):
        if self.measurement_table is None:
            return
        group = self._measurements()
        tree = self.measurement_table
        selected = self.measurement_selected_id or group["active_id"]
        for key in tree.get_children(): tree.delete(key)
        for item in group["items"]:
            status = item["state"]
            if item["id"] == group["active_id"]: status = "Active · " + status
            tree.insert("", "end", iid=item["id"], values=(item["label"], status))
        if tree.exists(selected):
            tree.selection_set(selected)
        elif tree.exists(group["active_id"]):
            tree.selection_set(group["active_id"])
        self.refresh_publish_measurements()

    def on_measurement_selected(self, _event=None):
        selected = self.measurement_table.selection()
        if selected: self.measurement_selected_id = selected[0]

    def _selected_measurement(self):
        group = self._measurements()
        mid = self.measurement_selected_id or group["active_id"]
        return next((item for item in group["items"] if item["id"] == mid), None)

    def new_measurement(self):
        if not self.require_working_source(): return
        self.snapshot()
        group = self._measurements()
        self._sync_active_measurement()
        mid = "meas_" + uuid.uuid4().hex
        self.project.calibration.clear()
        self.project.recalculate_all_points()
        self.config["scale_reference"] = None
        group["active_id"] = mid
        group["items"].append({"id": mid, "label": f"Measurement {len(group['items'])+1}",
                               "state": "draft", "axes": {"x": self.project.x_axis.to_dict(),
                               "y": self.project.y_axis.to_dict()}, "calibration": self.project.calibration.to_dict(),
                               "scale_reference": None})
        self.measurement_selected_id = mid
        self.scale_candidate = None
        self.hide_saved_scale_overlay = False
        self.verify_point = None
        self.mode.set("add")
        self.update_cal_status(); self.refresh_measurements(); self.redraw(); self.persist()
        self.status.set("New calibration measurement: select four corners, or calibrate the full image.")

    def activate_measurement(self):
        item = self._selected_measurement()
        if item is None: return
        group = self._measurements()
        if item["id"] == group["active_id"]: return
        self.snapshot()
        self._sync_active_measurement()
        group["active_id"] = item["id"]
        selected = next(m for m in group["items"] if m["id"] == item["id"])
        self.project.calibration = Calibration.from_dict(selected["calibration"])
        self.project.x_axis = AxisConfig.from_dict(selected["axes"]["x"])
        self.project.y_axis = AxisConfig.from_dict(selected["axes"]["y"])
        self.project.recalculate_all_points()
        self.config["scale_reference"] = copy.deepcopy(selected.get("scale_reference"))
        self.hide_saved_scale_overlay = False
        self.verify_point = None
        self.mode.set("add")
        self.config["axes"] = {"x": self.project.x_axis.to_dict(), "y": self.project.y_axis.to_dict()}
        self.config["calibration"] = self.project.calibration.to_dict()
        self.sync_controls_from_config(reload_source=False)
        self.refresh_measurements(); self.redraw(); self.persist()

    def accept_measurement(self):
        item = self._selected_measurement()
        if item is None: return
        self._sync_active_measurement()
        if not Calibration.from_dict(item["calibration"]).is_complete():
            messagebox.showwarning(APP_NAME, "A complete four-corner calibration is required.", parent=self.root)
            return
        try:
            trial = Project.from_dict({"axes": item["axes"], "calibration": item["calibration"]})
            if not trial.calibration_ready(): raise CalibrationError("Invalid calibration")
        except (CalibrationError, ValueError) as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            return
        self.snapshot()
        item["state"] = "accepted"
        self.refresh_measurements(); self.persist()

    def reject_measurement(self):
        item = self._selected_measurement()
        if item is None: return
        self.snapshot()
        item["state"] = "rejected"
        self.refresh_measurements(); self.persist()

    def rename_measurement(self):
        item = self._selected_measurement()
        if item is None: return
        label = simpledialog.askstring("Rename calibration", "Measurement name:",
                                      initialvalue=item["label"], parent=self.root)
        if label is None: return
        label = label.strip()
        if not label or len(label) > 90 or any(ch in label for ch in "\r\n"):
            messagebox.showerror(APP_NAME, "Choose a single-line measurement name of 1..90 characters.", parent=self.root)
            return
        self.snapshot(); item["label"] = label
        self.refresh_measurements(); self.refresh_publish_measurements(); self.persist()

    def cancel_measurement(self):
        """Discard only a draft realization; accepted measurements are never silently erased."""
        group = self._measurements()
        item = self._selected_measurement()
        if not item: return
        if item["state"] != "draft":
            messagebox.showinfo(APP_NAME, "Only draft measurements can be cancelled. Use Delete for an accepted measurement.", parent=self.root)
            return
        if len(group["items"]) <= 1:
            messagebox.showinfo(APP_NAME, "At least one measurement must remain.", parent=self.root)
            return
        if not messagebox.askyesno(APP_NAME, f"Discard draft '{item['label']}'?", parent=self.root): return
        self.snapshot()
        if item["id"] == group["active_id"]:
            replacement = next((m for m in group["items"] if m["id"] != item["id"] and m["state"] == "accepted"),
                               next(m for m in group["items"] if m["id"] != item["id"]))
            self.measurement_selected_id = replacement["id"]
            self.activate_measurement()
            group = self._measurements()  # activate persists a new config snapshot
        group["items"] = [m for m in group["items"] if m["id"] != item["id"]]
        self.measurement_selected_id = group["active_id"]
        self.refresh_measurements(); self.refresh_publish_measurements(); self.persist()

    def delete_measurement(self):
        group = self._measurements()
        item = self._selected_measurement()
        if item is None or len(group["items"]) < 2:
            messagebox.showinfo(APP_NAME, "At least one calibration measurement must remain.", parent=self.root)
            return
        if not messagebox.askyesno(APP_NAME, f"Delete {item['label']} permanently?", parent=self.root): return
        self.snapshot()
        mid = item["id"]
        if mid == group["active_id"]:
            replacement = next(m for m in group["items"] if m["id"] != mid)
            self.measurement_selected_id = replacement["id"]
            self.activate_measurement()
            group = self._measurements()  # activation persisted a replacement config
        group["items"] = [m for m in group["items"] if m["id"] != mid]
        self.measurement_selected_id = group["active_id"]
        self.refresh_measurements(); self.persist()

    def show_all_namespaces(self):
        self.namespace_var.set("All namespaces")
        self.refresh_dataset_choices()
        self.persist()

    def _curves_scroll_region(self, _event=None):
        """Enable the *page* scroll only when Curves controls actually overflow.

        Tk Canvas has a scrollregion even when the entire content is already
        visible. An unconditional yview handler can move that outer page while
        the user is scrolling the separate Treeview. On layout changes we
        explicitly reset an obsolete offset and hide an unnecessary page bar.
        The curve table has its own independent scrollbar (1.2.27).
        """
        if not hasattr(self, "curves_scroll_canvas"):
            return
        canvas = self.curves_scroll_canvas
        if not canvas.winfo_exists():
            return
        bbox = canvas.bbox("all")
        if bbox is None:
            return
        canvas.configure(scrollregion=bbox)
        height = canvas.winfo_height()
        if height <= 1:
            return  # First layout pass: geometry is not resolved yet.
        needed = (bbox[3] - bbox[1]) > height + 1
        self._curves_page_scrollable = needed
        scrollbar = self.curves_scrollbar
        if needed:
            if not scrollbar.winfo_manager():
                scrollbar.pack(side="right", fill="y")
        else:
            # A former scrolling offset must not survive once all content fits.
            if canvas.yview()[0] > 0:
                canvas.yview_moveto(0)
            if scrollbar.winfo_manager():
                scrollbar.pack_forget()

    def _curves_scroll_resize(self, event):
        """Match the scrolling page width to the pane, never split the Curves tab.

        Only Assisted tracing adapts between two subcolumns and a vertical
        layout if the user explicitly makes the control pane unusually narrow.
        """
        canvas = self.curves_scroll_canvas
        canvas.itemconfigure(self.curves_scroll_window, width=max(1, event.width))
        if hasattr(self, "assist_trace_settings"):
            is_wide = event.width >= 410
            if getattr(self, "_assist_layout_wide", None) != is_wide:
                self._assist_layout_wide = is_wide
                self.assist_trace_settings.grid_forget()
                self.assist_trace_actions.grid_forget()
                self.assist_layout.grid_columnconfigure(0, weight=1)
                self.assist_layout.grid_columnconfigure(1, weight=1 if is_wide else 0)
                if is_wide:
                    self.assist_trace_settings.grid(row=0, column=0, sticky="nsew", padx=(0, 6))
                    self.assist_trace_actions.grid(row=0, column=1, sticky="nsew", padx=(6, 0))
                else:
                    self.assist_trace_settings.grid(row=0, column=0, sticky="ew")
                    self.assist_trace_actions.grid(row=1, column=0, sticky="ew", pady=(6, 0))
        for label in getattr(self, "assist_help_labels", ()):
            label.configure(wraplength=max(225, event.width - 44))
        self._curves_scroll_region()
        # Reflow of the assistant's subcolumns can change the content height
        # AFTER the canvas Configure event. Re-evaluate after geometry settles.
        canvas.after_idle(self._curves_scroll_region)

    def _curves_pointer_over_list(self, px, py):
        """The table and its scrollbar own wheel events within these bounds.

        Use screen coordinates rather than event.widget: on some Windows/Tk
        combinations a nested Treeview wheel is also delivered at the root.
        """
        frame = getattr(self, "curve_list_frame", None)
        if frame is None or not frame.winfo_ismapped():
            return False
        x, y = frame.winfo_rootx(), frame.winfo_rooty()
        return x <= px < x + frame.winfo_width() and y <= py < y + frame.winfo_height()

    def _curves_mousewheel(self, event):
        """Scroll only when the pointer is over the active Curves controls.

        Never steal a wheel event from ImageCanvas: that widget uses it for
        image zoom. This also accommodates Win/macOS wheel and Linux X11 4/5.
        """
        if not hasattr(self, "curves_scroll_canvas") or not self._is_curves_tab():
            return None
        canvas = self.curves_scroll_canvas
        if not canvas.winfo_ismapped():
            return None
        px, py = canvas.winfo_pointerxy()
        # The curve list owns its scroll independently. The page MUST NOT move
        # even when the wheel is mistakenly routed to the root window.
        if self._curves_pointer_over_list(px, py):
            return "break"
        x, y = canvas.winfo_rootx(), canvas.winfo_rooty()
        if not (x <= px < x + canvas.winfo_width() and
                y <= py < y + canvas.winfo_height()):
            return None  # ImageCanvas is responsible for raster zoom.
        if not getattr(self, "_curves_page_scrollable", False):
            return "break"  # Nothing to scroll; never move a fitted page.
        if getattr(event, "num", None) == 4:
            amount = -1
        elif getattr(event, "num", None) == 5:
            amount = 1
        elif getattr(event, "delta", 0):
            amount = -1 if event.delta > 0 else 1
        else:
            return None
        canvas.yview_scroll(amount, "units")
        return "break"

    def _curve_tree_mousewheel(self, event):
        """Scroll the curve list, not the Curves page or the image viewport.

        The enclosing page has a separate vertical scrollbar. Without this
        widget-level binding its bind_all handler runs *after* Tk's Treeview
        class binding, so one wheel movement scrolls both surfaces. Returning
        'break' here suppresses both the class and page handlers. Support
        Windows/macOS delta events and X11 Button-4/5 explicitly.
        """
        if getattr(event, "num", None) == 4:
            delta = -1
        elif getattr(event, "num", None) == 5:
            delta = 1
        elif getattr(event, "delta", 0):
            delta = -1 if event.delta > 0 else 1
        else:
            return None
        self.curve_tree.yview_scroll(delta, "units")
        return "break"

    def build_curves_tab(self):
        # Restore the original *single column* arrangement of Curves.
        # The proposal assistant alone has two columns for its settings/actions.
        # Keep the 1.2.20 vertical scrollbar so low-height windows remain usable.
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Curves")
        self.curves_tab = tab
        scroll = tk.Canvas(tab, borderwidth=0, highlightthickness=0,
                           background=ttk.Style().lookup("TFrame", "background") or "#f0f0f0")
        scroll.pack(side="left", fill="both", expand=True)
        scrollbar = ttk.Scrollbar(tab, orient="vertical", command=scroll.yview)
        scrollbar.pack(side="right", fill="y")
        scroll.configure(yscrollcommand=scrollbar.set)
        self._curves_page_scrollable = False
        self.curves_scroll_canvas = scroll
        self.curves_scrollbar = scrollbar
        body = ttk.Frame(scroll, padding=8)
        self.curves_scroll_window = scroll.create_window((0, 0), anchor="nw", window=body)
        self.curves_body = body
        body.bind("<Configure>", self._curves_scroll_region)
        scroll.bind("<Configure>", self._curves_scroll_resize)
        # Toplevel-only binding: unlike bind_all, this does not capture wheel
        # events from dialogs or other Tk windows. Pointer dispatch above
        # strictly separates the curve list, outer controls, and raster image.
        self.root.bind("<MouseWheel>", self._curves_mousewheel, add="+")
        self.root.bind("<Button-4>", self._curves_mousewheel, add="+")
        self.root.bind("<Button-5>", self._curves_mousewheel, add="+")

        family = ttk.LabelFrame(body, text="Curve family", padding=6)
        family.pack(fill="x")
        ttk.Checkbutton(family, text="This configuration is a numerical curve family",
                        variable=self.family_enabled, command=self.family_changed).grid(
                            row=0, column=0, columnspan=2, sticky="w")
        fields = (("Family quantity", self.family_label), ("Family unit", self.family_unit),
                  ("Semantic role", self.family_role))
        for row_number, (label, var) in enumerate(fields, 1):
            ttk.Label(family, text=label).grid(row=row_number, column=0, sticky="w", padx=(0, 6), pady=2)
            values = (self.units if label == "Family unit" else self.roles
                      if label == "Semantic role" else ())
            widget = (ttk.Combobox(family, textvariable=var, values=values,
                                   state="normal", width=24) if values else
                      ttk.Entry(family, textvariable=var, width=27))
            widget.grid(row=row_number, column=1, sticky="ew", pady=2)
            widget.bind("<FocusOut>", lambda _e: self.persist())
        family.columnconfigure(1, weight=1)

        # This is a fixed-height, independently scrollable curve list. Its
        # scrollbar must not move the outer Curves controls when many traces
        # have been created in the same configuration.
        curve_list = ttk.Frame(body)
        curve_list.pack(fill="x", pady=(8, 4))
        self.curve_list_frame = curve_list
        self.curve_tree = ttk.Treeview(curve_list, columns=("label", "family", "points"),
                                       show="headings", height=9, selectmode="browse")
        self.curve_tree.heading("label", text="Curve")
        self.curve_tree.heading("family", text="Family value")
        self.curve_tree.heading("points", text="Points")
        self.curve_tree.column("label", width=170, minwidth=90, stretch=True)
        self.curve_tree.column("family", width=95, minwidth=65, stretch=True)
        self.curve_tree.column("points", width=55, minwidth=45, stretch=False, anchor="e")
        curve_list_scroll = ttk.Scrollbar(curve_list, orient="vertical",
                                          command=self.curve_tree.yview)
        # Reserve the scrollbar column first: in a narrow paned window the
        # expanding Treeview must never conceal its dedicated scrollbar.
        curve_list_scroll.pack(side="right", fill="y")
        self.curve_tree.pack(side="left", fill="both", expand=True)
        self.curve_tree.configure(yscrollcommand=curve_list_scroll.set)
        self.curve_tree_scrollbar = curve_list_scroll
        self.curve_tree.bind("<<TreeviewSelect>>", self.on_curve_selected)
        for control in (self.curve_tree, curve_list_scroll):
            control.bind("<MouseWheel>", self._curve_tree_mousewheel)
            control.bind("<Button-4>", self._curve_tree_mousewheel)
            control.bind("<Button-5>", self._curve_tree_mousewheel)
        buttons = ttk.Frame(body)
        buttons.pack(fill="x")
        for text, command in (("New curve", self.new_series), ("Edit", self.edit_series),
                              ("Delete", self.delete_series), ("Show/Hide", self.toggle_visible)):
            ttk.Button(buttons, text=text, command=command).pack(side="left", padx=(0, 4))

        modes = ttk.LabelFrame(body, text="Point interaction", padding=6)
        modes.pack(fill="x", pady=(8, 0))
        # Six modes, compact two rows. Delete is a click mode, not a separate
        # button requiring a currently selected point.
        for index,(label,value) in enumerate((("Add","add"),("Move","edit"),
                ("Delete","delete"),("Add guide","guide"),
                ("Edit proposal","proposal_edit"),("Add correction point","correction"))):
            ttk.Radiobutton(modes,text=label,value=value,variable=self.mode,
                            command=self.mode_changed).grid(row=index//3,column=index%3,
                            sticky="w",padx=(2,9),pady=1)
        self.selected_hint = ttk.Label(body, textvariable=self.selected_label, justify="left")
        # The selected-point details occupy no vertical space until selected.

        # ONLY THIS ASSISTANT is laid out in two columns. This avoids the
        # long former controls stack, while leaving every other section full width.
        assist = ttk.LabelFrame(body, text="Assisted tracing (proposal only)", padding=6)
        assist.pack(fill="x", pady=(7, 0))
        self.assist_frame = assist
        layout = ttk.Frame(assist)
        layout.pack(fill="x")
        layout.columnconfigure(0, weight=1)
        layout.columnconfigure(1, weight=1)
        settings = ttk.Frame(layout)
        settings.grid(row=0, column=0, sticky="nsew", padx=(0, 6))
        actions = ttk.Frame(layout)
        actions.grid(row=0, column=1, sticky="nsew", padx=(6, 0))
        self.assist_layout = layout
        self.assist_trace_settings = settings
        self.assist_trace_actions = actions
        self._assist_layout_wide = True

        ttk.Label(settings, text="Trace settings", font=("TkDefaultFont", 9, "bold")).pack(anchor="w")
        row = ttk.Frame(settings)
        row.pack(fill="x", pady=(5, 0))
        ttk.Label(row, text="Corridor (px)").pack(side="left")
        ttk.Spinbox(row, from_=1, to=40, textvariable=self.assist_radius, width=5).pack(side="right")
        row = ttk.Frame(settings)
        row.pack(fill="x", pady=(4, 0))
        ttk.Label(row, text="Step (px)").pack(side="left")
        ttk.Spinbox(row, from_=.5, to=10, increment=.5, textvariable=self.assist_step,
                    width=5).pack(side="right")
        ttk.Label(settings, text="Trace image").pack(anchor="w", pady=(8, 2))
        ttk.Combobox(settings, textvariable=self.assist_source, state="readonly",
                     values=("auto", "original", "processed"), width=13).pack(fill="x")

        ttk.Label(actions, text="Proposal", font=("TkDefaultFont", 9, "bold")).pack(anchor="w")
        action_grid = ttk.Frame(actions)
        action_grid.pack(fill="x", pady=(4, 0))
        action_grid.columnconfigure(0, weight=1)
        action_grid.columnconfigure(1, weight=1)
        for index, (label, fn) in enumerate((
                ("Propose", self.propose_guided_trace), ("Accept", self.accept_guided_trace),
                ("Reject", self.reject_guided_trace), ("Clear guides", self.clear_guides))):
            ttk.Button(action_grid, text=label, command=fn).grid(
                row=index // 2, column=index % 2, sticky="ew", padx=2, pady=2)
        density = ttk.Frame(actions)
        density.pack(fill="x", pady=(5, 2))
        ttk.Label(density, text="Output points (Accept)").pack(side="left")
        self.assist_output_spin = ttk.Spinbox(
            density, from_=0, to=10000, increment=10,
            textvariable=self.assist_output_points, width=6,
            command=self.assist_density_changed)
        self.assist_output_spin.pack(side="right")
        self.assist_output_spin.bind("<FocusOut>", self.assist_density_changed)
        self.assist_output_spin.bind("<Return>", self.assist_density_changed)
        segment = ttk.Frame(actions)
        segment.pack(fill="x", pady=(5, 2))
        ttk.Label(segment, text="Segment #").pack(side="left")
        self.assist_segment_spin = ttk.Spinbox(
            segment, from_=1, to=1, textvariable=self.assist_segment, width=5)
        self.assist_segment_spin.pack(side="right")
        ttk.Button(actions, text="Accept segment", command=self.accept_guided_segment).pack(fill="x")
        ttk.Button(actions, text="Resample accepted", command=self.resample_accepted_trace).pack(fill="x",pady=(3,0))

        status = ttk.Label(assist, textvariable=self.assist_status, justify="left", wraplength=480)
        status.pack(fill="x", pady=(4, 0))

        display = ttk.LabelFrame(body, text="Display and snapping", padding=6)
        display.pack(fill="x", pady=(6, 0))
        row = ttk.Frame(display);row.pack(fill="x")
        ttk.Checkbutton(row,text="Show point numbers",variable=self.show_numbers,
                        command=self.display_changed).pack(side="left")
        ttk.Checkbutton(row,text="Snap to dark",variable=self.snap_enabled,
                        command=self.snap_changed).pack(side="left",padx=(10,3))
        ttk.Label(row,text="Radius").pack(side="left")
        spin=ttk.Spinbox(row,from_=0,to=25,textvariable=self.snap_radius,
                         width=4,command=self.snap_changed)
        spin.pack(side="left",padx=3)
        spin.bind("<FocusOut>",lambda _e:self.snap_changed())

        appearance = ttk.LabelFrame(body, text="Appearance (per configuration)", padding=6)
        appearance.pack(fill="x", pady=(6, 0))
        row=ttk.Frame(appearance);row.pack(fill="x")
        ttk.Label(row,text="Image opacity").pack(side="left")
        ttk.Scale(row,from_=0,to=100,variable=self.opacity_var,
                  command=lambda _value:self.canvas_appearance_changed(),length=130).pack(side="left",padx=4)
        ttk.Label(row,textvariable=self.opacity_var,width=4).pack(side="left")
        ttk.Label(row,text="Background").pack(side="left",padx=(12,5))
        self.canvas_color_swatch=tk.Button(row,width=3,height=1,relief="solid",bd=1,
                            command=self.choose_canvas_color,cursor="hand2")
        self.canvas_color_swatch.pack(side="left")
        self.canvas_bg_var.trace_add("write",lambda *_:self._background_color_changed())
        self._update_color_swatch()

    def build_publish_tab(self):
        tab = ttk.Frame(self.notebook, padding=6)
        self.notebook.add(tab, text="Publish")
        self.publish_tab = tab
        ttk.Label(tab, text="Publication base Dataset ID").grid(row=0, column=0, sticky="w", pady=3)
        ttk.Entry(tab, textvariable=self.output_dataset_id, width=30).grid(row=0, column=1, sticky="ew", pady=3)
        ttk.Label(tab, text="Display name").grid(row=1, column=0, sticky="w", pady=3)
        ttk.Entry(tab, textvariable=self.output_display_name, width=30).grid(row=1, column=1, sticky="ew", pady=3)
        self.publish_contract = tk.StringVar(value="table.generic")
        ttk.Label(tab, text="Curve contract").grid(row=2, column=0, sticky="w")
        ttk.Label(tab, textvariable=self.publish_contract).grid(row=2, column=1, sticky="w")
        ttk.Label(tab, text="Publication layout").grid(row=3, column=0, sticky="w", pady=(5, 2))
        ttk.Combobox(tab, textvariable=self.publish_layout, state="readonly",
                     values=PUBLICATION_LAYOUTS).grid(row=3, column=1, sticky="ew", pady=(5, 2))
        ttk.Label(tab, text="Separate: one Dataset per selected calibration. Combined: a single Dataset with a calibration key column.",
                  wraplength=345, justify="left").grid(row=4, column=0, columnspan=2, sticky="w")
        ttk.Label(tab, text="Select accepted calibration measurements", font=("TkDefaultFont", 10, "bold")).grid(row=5, column=0, columnspan=2, sticky="w", pady=(10, 3))
        selection = ttk.Frame(tab); selection.grid(row=6, column=0, columnspan=2, sticky="nsew")
        selection.columnconfigure(0, weight=1); selection.rowconfigure(0, weight=1)
        self.publish_measurements = tk.Listbox(selection, selectmode="extended", exportselection=False,
                                              height=6, activestyle="none")
        self.publish_measurements.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(selection, orient="vertical", command=self.publish_measurements.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.publish_measurements.configure(yscrollcommand=scrollbar.set)
        ttk.Button(selection, text="Select all accepted", command=self.select_all_publish_measurements).grid(
                   row=1, column=0, sticky="w", pady=2)
        ttk.Label(tab, text="Effective naming template (Configuration → Viewer settings → Axes & output)").grid(
                  row=7, column=0, columnspan=2, sticky="w", pady=(7, 1))
        ttk.Label(tab, textvariable=self.publish_name_template, wraplength=360).grid(
                  row=8, column=0, columnspan=2, sticky="w")
        self.publish_plan_preview = tk.StringVar(value="")
        ttk.Label(tab, textvariable=self.publish_plan_preview, wraplength=370,
                  justify="left").grid(row=9, column=0, columnspan=2, sticky="w", pady=(3, 6))
        ttk.Button(tab, text="Uncertainty...",
                   command=lambda: UncertaintyDialog(self) if self.current_doc_id else None).grid(
                   row=10, column=0, sticky="ew", padx=(0,4))
        ttk.Button(tab, text="Publish selected calibrations", command=self.publish_dataset).grid(
                   row=10, column=1, sticky="ew")
        self.publish_result = tk.StringVar()
        ttk.Label(tab, textvariable=self.publish_result, wraplength=370,
                  justify="left").grid(row=11, column=0, columnspan=2, sticky="w", pady=(7, 0))
        tab.columnconfigure(1, weight=1); tab.rowconfigure(6, weight=1)
        self.publish_measurements.bind("<<ListboxSelect>>", lambda _e: self.preview_publication())
        self.publish_layout.trace_add("write", lambda *_: self.preview_publication())
        for var in (self.output_dataset_id, self.output_display_name):
            var.trace_add("write", lambda *_: (self.persist_later(), self.preview_publication()))
        self.refresh_publish_measurements()

    def refresh_publish_measurements(self):
        if self.publish_measurements is None or not self.config:
            return
        group = self._measurements()
        previous = (set(self.publish_selection) if self.loading_ui else
                    set(self.selected_publication_ids()))
        if not previous and self.publish_selection:
            previous = set(self.publish_selection)
        self.publish_measurements.delete(0, "end")
        self.publish_measurement_ids = []
        for item in group["items"]:
            if item["state"] != "accepted": continue
            self.publish_measurement_ids.append(item["id"])
            self.publish_measurements.insert("end", f"{item['label']}  ({item['id'][-8:]})")
        if not previous:
            previous = {item["id"] for item in group["items"] if item["id"] == group["active_id"] and item["state"] == "accepted"}
        for idx, mid in enumerate(self.publish_measurement_ids):
            if mid in previous: self.publish_measurements.selection_set(idx)
        self.preview_publication()

    def select_all_publish_measurements(self):
        if self.publish_measurements is not None:
            self.publish_measurements.selection_set(0, "end")
            self.preview_publication()

    def selected_publication_ids(self):
        if self.publish_measurements is None: return []
        ids = getattr(self, "publish_measurement_ids", [])
        return [ids[i] for i in self.publish_measurements.curselection() if i < len(ids)]

    def preview_publication(self):
        if not hasattr(self, "publish_plan_preview"): return
        ids = self.selected_publication_ids()
        self.publish_selection = ids
        if not ids:
            self.publish_plan_preview.set("Select one or more accepted measurements.")
            return
        try:
            name = self.output_dataset_id.get().strip() or slug_id(self.config.get("name", "digitized.curves"))
            plan = plan_datasets(self._measurements()["items"], ids,
                    layout=self.publish_layout.get(), template=self.publish_name_template.get(),
                    name=name, configuration=self.config.get("name", "digitizer"))
            self.publish_plan_preview.set("Output:\n" + "\n".join(x["dataset_id"] for x in plan[:5]) +
                        (f"\n… and {len(plan)-5} more" if len(plan) > 5 else ""))
        except (ValueError, KeyError) as exc:
            self.publish_plan_preview.set(str(exc))

    def build_notes_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Notes")
        self.notes_tab = tab
        ttk.Label(tab, text="Configuration notes (plain UTF-8 text)").pack(anchor="w")
        self.notes = tk.Text(tab, wrap="word", height=24)
        self.notes.pack(fill="both", expand=True, pady=(6, 0))
        self.notes.bind("<FocusOut>", lambda _e: self.persist())

    def bind_keys(self):
        self.root.bind_all("<Control-z>", lambda _e: self.undo())
        self.root.bind_all("<Control-y>", lambda _e: self.redo())
        self.root.bind_all("<Delete>", lambda _e: self.delete_selected_point())
        self.root.bind_all("<F1>", lambda _e: self.open_help())
        self.root.bind_all("<Escape>", self._verification_escape)

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
        # CORE Configuration defines defaults; each created Interactive
        # Document immediately owns an independent editable copy.
        cfg["display"]["canvas_background"] = self.shared_settings.get("canvas_background", "#303030")
        cfg["display"]["image_opacity"] = int(self.shared_settings.get("image_opacity", "100"))
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
        # A duplicated document starts an independent measurement group.
        # Keep the numerical transformations, but not the identities of the
        # original operator's individual calibration realizations.
        if isinstance(cfg.get("calibration_measurements"), dict):
            group = cfg["calibration_measurements"]
            old_active = group.get("active_id", "")
            group["group_id"] = "calgrp_" + uuid.uuid4().hex
            for item in group.get("items", []):
                old = item["id"]
                item["id"] = "meas_" + uuid.uuid4().hex
                if old == old_active:
                    group["active_id"] = item["id"]
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
        self._proposal_history.clear();self._proposal_last_insert=None;self._assist_move_target=None
        self.guide_points=[];self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
        cfg = copy.deepcopy(self.documents[doc_id])
        self.current_doc_id = doc_id
        self.config = cfg
        self.project = self.config_to_project(cfg)
        self.active_series_id = self.project.series[0].id if self.project.series else None
        self.selected_point_id = None
        self.measurement_selected_id = None
        self.verify_point = None
        self.undo_stack.clear()
        self.redo_stack.clear()
        self.sync_controls_from_config(reload_source=True)
        self.refresh_measurements()
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
                (self.x_min, format(float(x.get("minimum", 0)), ".17g")), (self.x_max, format(float(x.get("maximum", 1)), ".17g")), (self.x_scale, x.get("scale", "linear")),
                (self.y_name, y.get("name", "Y")), (self.y_unit, y.get("unit", "")), (self.y_role, y.get("semantic_role", "measured")),
                (self.y_min, format(float(y.get("minimum", 0)), ".17g")), (self.y_max, format(float(y.get("maximum", 1)), ".17g")), (self.y_scale, y.get("scale", "linear")),
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
            requested_mode = pub.get("layout", self.shared_settings["publication_layout"])
            self.publish_layout.set(requested_mode if requested_mode in PUBLICATION_LAYOUTS else "separate")
            self.publish_selection = list(pub.get("selected_measurement_ids", []))
            display = self.config.get("display", {})
            self.show_numbers.set(bool(display.get("show_point_numbers", False)))
            self.show_scale_overlay.set(bool(display.get("show_scale_overlay", True)))
            self.show_calibration_corners.set(bool(display.get("show_calibration_corners", True)))
            # Presentation is owned by this Interactive Document. CORE values
            # are defaults only for sessions created before these fields existed.
            self._appearance_loading=True
            try:
                color=display.get("canvas_background",self.shared_settings.get("canvas_background","#303030"))
                if not re.fullmatch(r"#[0-9a-fA-F]{6}",str(color)):color="#303030"
                self.canvas_bg_var.set(color)
                try:self.opacity_var.set(max(0,min(100,int(display.get("image_opacity",self.shared_settings.get("image_opacity",100))))) )
                except (ValueError,TypeError):self.opacity_var.set(100)
            finally:self._appearance_loading=False
            try:ordering=normalize_ordering(self.config.get("curve_ordering",{}))
            except ValueError:ordering={"monotonicity":"none","source":"insertion"}
            self.curve_monotonicity.set(ordering["monotonicity"])
            self.point_order_source.set(ordering["source"])
            saved_output=(self.config.get("assisted_tracing") or {}).get("output_points",0)
            try:
                value=int(saved_output)
                if value==1 or value<0 or value>10000:raise ValueError
                self.assist_output_points.set(value)
            except (TypeError,ValueError):
                self.assist_output_points.set(0)
            self.snap_enabled.set(bool(self.config.get("snap", {}).get("enabled", False)))
            self.snap_radius.set(max(0, int(self.config.get("snap", {}).get("radius", 3))))
            self.notes.delete("1.0", "end")
            self.notes.insert("1.0", self.config.get("notes", ""))
            source_id = self.config.get("source", {}).get("dataset_id", "")
            preferences_catalog = self.config.get("catalog_preferences", {})
            self.namespace_var.set(preferences_catalog.get("selected_namespace", "All namespaces"))
            self.auto_catalog_watch.set(bool(preferences_catalog.get("automatic", True)))
            self.processed_image = None
            self.processed_fingerprint = None
            saved_processing = self.config.get("image_processing") or {}
            try: self.processing_operations = normalize_operations(saved_processing.get("operations", []))
            except ProcessingError: self.processing_operations = []
            self.processing_show_result.set(bool(saved_processing.get("show_processed", True)))
            # Pre-existing custom/repeated pipelines must not be silently sorted.
            ordered = [op["kind"] for op in self.processing_operations]
            if ordered != sorted(ordered, key=STANDARD_ORDER.index) or len(ordered) != len(set(ordered)):
                self.processing_filter_mode.set("advanced")
            self._refresh_processing_list()
            self._processing_mode_visibility()
            self.processing_dataset_id.set((source_id + ".processed") if source_id else "")
            self.processing_display_name.set(("Processed " + source_id) if source_id else "")
            self.source_var.set(source_id)
            self.refresh_dataset_choices()
            if reload_source:
                self.load_current_source()
            preferences = self.config.get("scale_preferences", {})
            direction = preferences.get("y_direction", "Downward (image pixels)" if
                self.project.y_axis.minimum > self.project.y_axis.maximum else "Upward (Cartesian)")
            self.auto_y_direction.set(direction)
            edge = preferences.get("edge_convention", "center")
            self.scale_edge_convention.set(EDGE_LABELS.get(edge, EDGE_LABELS["center"]))
            self.scale_length.set(str(preferences.get("length", "10")))
            self.scale_unit.set(str(preferences.get("unit", "µm")))
            reference = self.config.get("scale_reference") or {}
            self.scale_candidate = None
            self.scale_first_endpoint = None
            self.hide_saved_scale_overlay = False
            if self.mode.get() in ("scale_detect", "scale_manual"):
                self.mode.set("add")
            if reference:
                self.scale_length.set(str(reference.get("physical_length", "")))
                self.scale_unit.set(str(reference.get("unit", "µm")))
                self.scale_status.set(
                    f"Saved scale: {fmt(float(reference['pixel_length']))} px = "
                    f"{fmt(float(reference['physical_length']))} {reference['unit']}; "
                    f"reference: {reference.get('edge_convention', 'unspecified')}.")
            else:
                self.scale_status.set("Auto-calibrate full image, then select a scale bar.")
            # Legacy per-Document presentation keys are retained for old
            # Sessions, but CORE Configuration is the effective authority.
            self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
            if requested_mode in PUBLICATION_LAYOUTS:
                self.publish_layout.set(requested_mode)
            self.update_cal_status()
            self.update_selected()
            self.refresh_publish_measurements()
        finally:
            self.loading_ui = False

    def dataset_choices(self):
        """Namespace is a browser filter, never a Dataset identity or path."""
        namespace = self.namespace_var.get()
        if namespace == "All namespaces":
            return sorted(self.datasets, key=str.casefold)
        return sorted((did for did, info in self.datasets.items()
                       if info.get("namespace") == namespace or
                       info.get("namespace", "").startswith(namespace + "/")), key=str.casefold)

    def refresh_dataset_choices(self):
        if not hasattr(self, "source_combo"):
            return
        current = self.source_var.get()
        self.source_combo.configure(values=self.dataset_choices())
        # A historical source must not disappear from the current configuration
        # just because its workspace is not the selected search filter.
        self.source_var.set(current)

    def on_namespace_selected(self, _event=None):
        self.refresh_dataset_choices()
        self.catalog_diag.set(f"Browsing {self.namespace_var.get()} — {len(self.dataset_choices())} image(s)")
        self.persist_later()

    def _show_source_warning_in_status(self, *_args):
        """Do not conceal source warnings after compacting the toolbar."""
        message = self.source_diag.get()
        if any(message.startswith(prefix) for prefix in
               ("STALE SOURCE", "SOURCE MISSING", "SOURCE ERROR", "SESSION CHANGED")):
            self.status.set(message)

    def open_namespace_picker(self):
        """Canvas namespace browser: a view/filter only, never a dataset move."""
        if getattr(self, "namespace_dialog", None) and self.namespace_dialog.winfo_exists():
            self.namespace_dialog.lift()
            return
        dlg = tk.Toplevel(self.root)
        self.namespace_dialog = dlg
        dlg.title("Select Dataset namespace")
        dlg.transient(self.root)
        dlg.geometry("475x475")
        dlg.minsize(340, 285)
        selected = tk.StringVar(dlg, value=self.namespace_var.get())
        ttk.Label(dlg, text="Source Image Dataset namespace", font=("TkDefaultFont", 11, "bold")).pack(anchor="w", padx=14, pady=(12, 4))
        ttk.Label(dlg, text="Select a namespace to filter the image list. Source data is not moved.",
                  wraplength=440).pack(anchor="w", padx=14, pady=(0, 9))
        content = ttk.Frame(dlg)
        content.pack(fill="both", expand=True, padx=14)
        surface = tk.Canvas(content, highlightthickness=1, highlightbackground="#888888", background="#ffffff")
        bar = ttk.Scrollbar(content, orient="vertical", command=surface.yview)
        surface.configure(yscrollcommand=bar.set)
        surface.pack(side="left", fill="both", expand=True)
        bar.pack(side="right", fill="y")
        choices = ["All namespaces"] + sorted(set(self.dataset_namespaces), key=str.casefold)
        counts = {ns: 0 for ns in choices}
        counts["All namespaces"] = len(self.datasets)
        for info in self.datasets.values():
            ns = info.get("namespace", "")
            for parent in choices[1:]:
                if ns == parent or ns.startswith(parent + "/"):
                    counts[parent] += 1
        row_height = 34
        surface.configure(scrollregion=(0, 0, 465, len(choices)*row_height+6))
        def render_rows():
            surface.delete("all")
            # Explicit redrawing avoids relying on Canvas item IDs after theme changes.
            for i, ns in enumerate(choices):
                y0, y1 = i * row_height + 2, (i + 1) * row_height
                active = ns == selected.get()
                tag = f"item_{i}"
                surface.create_rectangle(2, y0, 900, y1,
                    fill="#deefff" if active else "#ffffff", outline="", tags=(tag,))
                label = "All namespaces" if i == 0 else ("  " * min(ns.count("/"), 4)) + ns
                surface.create_text(11, (y0+y1)/2, text=label, anchor="w", fill="#173c65" if active else "#202020",
                    font=("TkDefaultFont", 10, "bold" if active else "normal"), tags=(tag,))
                surface.create_text(440, (y0+y1)/2, text=str(counts[ns]), anchor="e", fill="#636363", tags=(tag,))
                surface.tag_bind(tag, "<Button-1>", lambda e, value=ns: (selected.set(value), render_rows()))
        render_rows()
        surface.bind("<MouseWheel>", lambda e: surface.yview_scroll(-1 if e.delta > 0 else 1, "units"))
        actions = ttk.Frame(dlg, padding=(14, 10))
        actions.pack(fill="x")
        def apply():
            if selected.get() not in choices:
                return
            self.namespace_var.set(selected.get())
            self.on_namespace_selected()
            dlg.destroy()
        ttk.Button(actions, text="Cancel", command=dlg.destroy).pack(side="right", padx=(6, 0))
        ttk.Button(actions, text="Use namespace", command=apply).pack(side="right")
        dlg.bind("<Return>", lambda e: apply())
        dlg.bind("<Escape>", lambda e: dlg.destroy())
        surface.focus_set()

    def _scheduled_session_check(self):
        """Read CORE's authoritative Session token even with catalog watch off.

        RPC is asynchronous so an open viewer remains responsive. A new Session
        must be re-bootstrapped; mutating the old document would be unsafe.
        """
        if not self.root.winfo_exists():
            return
        if not self.session_refreshing and self.session_probe_id is None:
            try:
                self.session_probe_id = self.rpc.begin("SESSION_TOKEN")
                self.root.after(80, self._poll_session_probe)
            except RpcError as exc:
                self.status.set(f"Session check failed: {exc}")
        self.root.after(self.session_check_ms, self._scheduled_session_check)

    def _poll_session_probe(self):
        request_id = self.session_probe_id
        if request_id is None or self.session_refreshing:
            return
        try:
            payload = self.rpc.poll_response(request_id)
            if payload is None:
                self.root.after(100, self._poll_session_probe)
                return
            self.session_probe_id = None
            token = next((values[0] for kind, values in parse_records(payload)
                          if kind == "SESSION" and len(values) == 1), None)
            if token is None:
                raise ValueError("CORE did not return its Session identity")
            if token != self.session_token:
                self._begin_session_rebootstrap()
        except (RpcError, ValueError, IndexError) as exc:
            self.session_probe_id = None
            self.status.set(f"Session check failed: {exc}")

    def _begin_session_rebootstrap(self):
        if self.session_refreshing:
            return
        self.session_refreshing = True
        self.catalog_session_invalid = True
        self.stale_source = True
        pending = getattr(self, "_persist_after", None)
        if pending is not None:
            try:self.root.after_cancel(pending)
            except tk.TclError:pass
            self._persist_after = None
        self.source_diag.set("SESSION CHANGED — loading the new GX-TXT Session...")
        self.status.set("Session changed; resetting Curve Digitalizer from GX-TXT.")
        try:
            self.session_bootstrap_id = self.rpc.begin("BOOTSTRAP")
            self.root.after(80, self._poll_session_bootstrap)
        except RpcError as exc:
            self.session_refreshing = False
            self.status.set(f"Session reset failed: {exc}; edits remain disabled.")

    def _poll_session_bootstrap(self):
        request_id = self.session_bootstrap_id
        if request_id is None:
            return
        try:
            payload = self.rpc.poll_response(request_id)
            if payload is None:
                self.root.after(100, self._poll_session_bootstrap)
                return
            self.session_bootstrap_id = None
            self._adopt_session_bootstrap(payload)
        except (RpcError, ValueError, TypeError, tk.TclError) as exc:
            self.session_bootstrap_id = None
            self.status.set(f"Unable to reload GX-TXT Session: {exc}. Edits remain disabled.")
            self.session_refreshing = False

    def _adopt_session_bootstrap(self, payload):
        """Discard transient OLD-Session state, then bind only new CORE data.

        No DOC_UPDATE or publication is performed against a stale Session.
        Old Sessions are not modified or deleted. A temporary tracing proposal,
        undo history and settings dialog belong exclusively to their Session.
        """
        records = parse_records(payload)
        token = next((f[0] for k,f in records if k == "SESSION" and len(f) == 1), None)
        if not token:
            raise ValueError("Missing Session token in new bootstrap")
        if token == self.session_token:
            # A transient catalog/token discrepancy: no reset is necessary.
            self.catalog_session_invalid = False
            self.session_refreshing = False
            return
        for name in ("settings_dialog", "namespace_dialog"):
            dialog = getattr(self, name, None)
            if dialog is not None:
                try:
                    if dialog.winfo_exists(): dialog.destroy()
                except tk.TclError:
                    pass
                setattr(self, name, None)
        # Cancel edits queued by the old Session before binding new documents.
        # Otherwise a delayed persist() could write stale state into the new
        # Session if document IDs happen to be reused.
        pending = getattr(self, "_persist_after", None)
        if pending is not None:
            try:self.root.after_cancel(pending)
            except tk.TclError:pass
            self._persist_after = None
        if self._processing_update_after is not None:
            try:self.root.after_cancel(self._processing_update_after)
            except tk.TclError:pass
            self._processing_update_after = None
        self._processing_resubmit = False
        self.processing_active = False
        self.processing_result_queue = queue.Queue()
        self.processed_image = None
        self.processed_fingerprint = None
        self.gray_image = None
        self.image = None
        self.processing_operations = []
        self.guide_points = []
        self.assisted_proposal = None
        self._assist_drag = None
        self._assist_context = None
        self._proposal_history.clear();self._proposal_last_insert=None;self._assist_move_target=None
        self.assist_accepted_segments = set()
        self.assist_accepted_point_ids = {}
        self._assist_sampling_spec = None
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.verify_point = None
        self.undo_stack.clear()
        self.redo_stack.clear()
        self.selected_point_id = None
        self.active_series_id = None
        self.documents.clear()
        self.document_sha.clear()
        self.datasets.clear()
        self.dataset_namespaces.clear()
        self.units.clear()
        self.roles.clear()
        self.catalog_revision = None
        self.catalog_session_token = ""
        self.catalog_request_id = None
        self.settings_request_id = None
        self.current_doc_id = None
        self.config = self.new_configuration("Untitled")
        self.project = Project()
        if hasattr(self, "canvas"):
            for surface in (self.canvas,
                            getattr(self, "compare_original_canvas", None),
                            getattr(self, "compare_processed_canvas", None)):
                if surface is not None:
                    surface.set_image(None)
                    surface.delete("all")
        self.source_var.set("")
        self.assist_status.set("")
        self.mode.set("add")
        self.shared_settings = dict(CORE_PREFS)
        self.shared_settings_origin = {}
        self.bootstrap(payload)
        self.catalog_session_invalid = False
        self.stale_source = False
        self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
        self.refresh_configuration_selector()
        self.refresh_dataset_choices()
        if self.documents:
            self.open_document(next(iter(self.documents)))
        else:
            self.sync_controls_from_config(reload_source=False)
            self.clear_ui_no_config()
            self.redraw()
        self.catalog_diag.set("Checking new Session Dataset catalog...")
        self.session_refreshing = False
        self.status.set("GX-TXT Session changed: new Session loaded; old proposals and undo history cleared.")
        self.root.after(100, lambda:self.check_dataset_catalog(force=True))

    def check_dataset_catalog(self, *, force=False):
        """Non-blocking, read-only revision check on the GUI event loop."""
        if not self.root.winfo_exists():
            return
        if self.catalog_request_id is None and (force or self.auto_catalog_watch.get()):
            try:
                kind = "CATALOG" if force or self.catalog_revision is None else "CATALOG_REV"
                self.catalog_request_id = self.rpc.begin(kind)
                self.catalog_request_kind = kind
                self.root.after(80, self._poll_catalog_reply)
            except RpcError as exc:
                self.catalog_diag.set(f"Catalog check failed: {exc}")

    def _scheduled_catalog_check(self):
        if self.root.winfo_exists():
            self.check_dataset_catalog()
            self.root.after(self.catalog_check_ms, self._scheduled_catalog_check)

    def _poll_catalog_reply(self):
        if self.session_refreshing:
            return
        request_id = self.catalog_request_id
        if request_id is None:
            return
        try:
            payload = self.rpc.poll_response(request_id)
        except RpcError as exc:
            self.catalog_request_id = None
            self.catalog_diag.set(f"Catalog check failed: {exc}")
            return
        if payload is None:
            self.root.after(100, self._poll_catalog_reply)
            return
        kind = self.catalog_request_kind
        self.catalog_request_id = None
        try:
            records = parse_records(payload)
            state = next((f for k, f in records if k == "STATE"), None)
            if state is None or len(state) != 4:
                raise ValueError("Missing Dataset catalog revision and Session identity")
            session_token, catalog_token, revision_text, current_ns = state
            if session_token != self.session_token:
                self._begin_session_rebootstrap()
                return
            revision = int(revision_text)
            changed = catalog_token != self.catalog_session_token or revision != self.catalog_revision
            if kind == "CATALOG_REV" and changed:
                # Ask CORE for a complete authoritative snapshot only on change.
                self.catalog_request_kind = "CATALOG"
                self.catalog_request_id = self.rpc.begin("CATALOG")
                self.root.after(80, self._poll_catalog_reply)
                return
            if kind == "CATALOG":
                new_namespaces = [f[0] for k, f in records if k == "NAMESPACE" and len(f) == 1]
                new_datasets = {}
                for record_kind, f in records:
                    if record_kind == "IMAGE" and len(f) == 6:
                        did, ns, contract, fmt_, media, sha = f
                        new_datasets[did] = {"namespace": ns, "contract": contract,
                                             "format": fmt_, "media_type": media,
                                             "registered_sha256": sha}
                previous = self.datasets
                self.datasets = new_datasets
                self.dataset_namespaces = new_namespaces
                selected = self.namespace_var.get()
                values = ["All namespaces"] + new_namespaces
                if selected not in values:
                    self.namespace_var.set("All namespaces")
                self.refresh_dataset_choices()
                self._on_catalog_update(previous, new_datasets)
                self.catalog_session_token = catalog_token
                self.catalog_revision = revision
                self.catalog_diag.set(f"Dataset catalog r{revision} · {len(new_datasets)} image(s)")
            elif kind == "CATALOG_REV":
                self.catalog_diag.set(f"Dataset catalog r{revision} · up to date")
        except (ValueError, RpcError, TypeError, IndexError) as exc:
            self.catalog_diag.set(f"Catalog refresh failed: {exc}")

    def _on_catalog_update(self, previous, latest):
        source = self.config.get("source", {}) if self.config else {}
        did = source.get("dataset_id", "")
        if not did:
            if self.current_doc_id:
                self.source_diag.set("Choose an Image Dataset in the selected workspace.")
            return
        if did not in latest:
            self.stale_source = True
            self.source_diag.set("SOURCE MISSING — source Dataset deleted or renamed; saved points retained.")
            return
        # Re-resolve after a catalog change (not on every timer tick). A source
        # change is never accepted silently; only identical verified SHA is safe.
        try:
            info = self.fetch_source(did)
        except Exception as exc:
            self.stale_source = True
            self.source_diag.set(f"SOURCE ERROR — {exc}")
            return
        expected = source.get("sha256", "").lower()
        actual = info.get("sha256", "").lower()
        if not expected or not actual or expected != actual:
            self.stale_source = True
            self.source_diag.set("STALE SOURCE — image content changed; points and calibration preserved.")
            return
        self.stale_source = False
        self.source_metadata = info.get("metadata", {})
        # BOOTSTRAP returns Interactive Documents before the new Session's
        # Dataset catalog arrives. open_document -> load_current_source refuses
        # to open a source absent from that still-empty catalog. Once the
        # authoritative catalog and SHA agree, restore the *actual raster*.
        # Merely updating SOURCE_STATUS leaves the canvas permanently blank.
        if self.image is None:
            try:
                restored = self.open_dataset_image(info["path"])
                self.set_image(restored, restore_view=True)
                self.status.set("Session source image restored from the verified Dataset.")
            except Exception as exc:
                self.stale_source = True
                self.source_diag.set(f"SOURCE ERROR — could not restore raster: {exc}")
                return
        self.refresh_source_info()
        self.source_diag.set("Source Dataset verified by SHA-256; catalog is current.")

    def on_source_selected(self, _event=None):
        if self.loading_ui or not self.current_doc_id:
            return
        selected = self.source_var.get().strip()
        current = self.config.get("source", {}).get("dataset_id", "")
        if selected not in self.dataset_choices():
            self.source_var.set(current)
            messagebox.showwarning(APP_NAME, "Choose an image in the selected Dataset workspace.")
            return
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
        self.processing_operations = []
        self.processed_image = None
        self.processed_fingerprint = None
        self.config["image_processing"] = {"operations": [], "show_processed": True}
        self._refresh_processing_list()
        self.processing_dataset_id.set(selected + ".processed")
        self.processing_display_name.set("Processed " + selected)
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
        if self.catalog_session_invalid or dataset_id not in self.datasets:
            self.image = None
            if hasattr(self, "canvas"):
                self.canvas.set_image(None)
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
        self._proposal_history.clear();self._proposal_last_insert=None;self._assist_move_target=None
        self.guide_points=[];self.assisted_proposal=None;self._assist_context=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
        self.scale_candidate = None
        self.scale_first_endpoint = None
        if self.mode.get() in ("scale_detect", "scale_manual"):
            self.mode.set("add")
        self.image = image
        self.gray_image = image.convert("L")
        self.canvas.set_image(image)
        # A new source raster begins a new independent comparison view, even
        # when its dimensions equal those of the previous source.
        self._refresh_comparison_images(reset_views=True)
        if restore_view:
            view = self.config.get("view", {})
            if all(k in view for k in ("scale", "offset_x", "offset_y")):
                def restore():
                    try:
                        # The saved view is authoritative; don't let a late Tk
                        # Configure event override it with an automatic fit.
                        self.canvas._pending_initial_fit = False
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
        # Editing a display label is safe; changing physical bounds, units or
        # axis mapping invalidates the recorded scale bar measurement.
        old_x, old_y = self.project.x_axis, self.project.y_axis
        _scientific_changed = any(
            (new.unit, new.minimum, new.maximum, new.scale) !=
            (old.unit, old.minimum, old.maximum, old.scale)
            for new, old in ((x, old_x), (y, old_y))
        )
        if _scientific_changed and self.config.get("scale_reference"):
            self.config["scale_reference"] = None
            self.scale_status.set("Scale reference cleared after changing units, limits or axis mapping.")
        self.project.x_axis, self.project.y_axis = x, y
        self.project.recalculate_all_points()
        self.update_cal_status()
        self.redraw()
        if changed or push:
            self.persist()
        return True

    def auto_calibrate_full_image(self):
        """Automatically use all image pixels; retain Session undo/redo."""
        if not self.require_working_source():
            return
        width, height = self.image.size
        if width < 2 or height < 2:
            messagebox.showerror(APP_NAME, "Full-image calibration requires an image at least 2 x 2 pixels.")
            return
        current_axes = (self.project.x_axis.to_dict(), self.project.y_axis.to_dict())
        fresh_axes = (AxisConfig(name="X").to_dict(), AxisConfig(name="Y").to_dict())
        has_data = any(series.points for series in self.project.series)
        if (self.project.calibration.pixels or current_axes != fresh_axes or has_data) and not messagebox.askyesno(
                APP_NAME,
                "Replace the existing calibration and axis limits with full-image pixel coordinates?\n\n"
                "Existing digitized points will be recalculated, not deleted.", parent=self.root):
            return
        y_down = self.auto_y_direction.get() == "Downward (image pixels)"
        self.snapshot()
        try:
            self.project.auto_calibrate_full_image(width, height, y_down=y_down)
        except CalibrationError as exc:
            # A failed action must not strand an undo entry or partial calibration.
            previous = self.undo_stack.pop()
            self.restore_snapshot(previous, persist=False)
            messagebox.showerror(APP_NAME, f"Full-image calibration failed:\n{exc}")
            return
        self.config["scale_reference"] = None
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.scale_status.set("Select the image scale bar to convert pixels into physical units.")
        self.pending_corner = None
        self.mode.set("add")
        for var, value in (
            (self.x_min, "0"), (self.x_max, str(width - 1)),
            (self.y_min, str(height - 1) if y_down else "0"),
            (self.y_max, "0" if y_down else str(height - 1)),
            (self.x_unit, "px"), (self.y_unit, "px"),
            (self.x_scale, "linear"), (self.y_scale, "linear"),
        ):
            var.set(value)
        self.verify_result.set("")
        self.update_cal_status()
        self.update_selected()
        self.redraw()
        self.persist()
        self.status.set(f"Full image calibrated: {width} x {height} pixels; Y increases {'downward' if y_down else 'upward'}.")

    def _require_full_image_for_scale(self):
        if not self.require_working_source():
            return False
        if not self.project.is_full_image_calibration(*self.image.size):
            messagebox.showerror(APP_NAME,
                "Use Auto-calibrate full image before scaling from a scale bar. "
                "Do not use a manually perspective-calibrated graph.", parent=self.root)
            return False
        return True

    def start_scale_detection(self):
        self.clear_verification() if self.mode.get() == "verify" else None
        if not self._require_full_image_for_scale():
            return
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.mode.set("scale_detect")
        self.scale_status.set("Click the shaft of the scale bar. The selected tick reference will be highlighted for review.")
        self.redraw()

    def start_scale_manual(self):
        self.clear_verification() if self.mode.get() == "verify" else None
        if not self._require_full_image_for_scale():
            return
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.mode.set("scale_manual")
        self.scale_status.set("Click the first scale bar endpoint, then the second endpoint.")
        self.redraw()

    def cancel_scale_selection(self):
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.hide_saved_scale_overlay = True
        if self.mode.get() in ("scale_detect", "scale_manual"):
            self.mode.set("add")
        self.scale_status.set("Scale overlay cleared. The applied calibration is preserved.")
        self.redraw()

    def select_scale_point(self, x, y):
        """Preview only; never change scientific state until explicit Apply."""
        mode = self.mode.get()
        if mode == "scale_detect":
            try:
                detection = detect_scale_bar(self.image, x, y,
                    edge_mode=EDGE_MODES.get(self.scale_edge_convention.get(), "center"))
            except ScaleDetectionError as exc:
                self.scale_candidate = None
                self.scale_status.set(str(exc))
                self.redraw()
                return
            self.scale_candidate = (detection.start, detection.end, "detected")
        elif mode == "scale_manual":
            if self.scale_first_endpoint is None:
                self.scale_first_endpoint = (x, y)
                self.scale_status.set("First endpoint selected. Click the opposite end of the bar.")
                self.redraw()
                return
            if math.dist(self.scale_first_endpoint, (x, y)) < 3:
                self.scale_status.set("Select two distinct endpoints, at least 3 pixels apart.")
                return
            self.scale_candidate = (self.scale_first_endpoint, (x, y), "manual")
            self.scale_first_endpoint = None
        else:
            return
        a, b, method = self.scale_candidate
        px = math.dist(a, b)
        self.scale_status.set(f"{method.title()} line: {fmt(px)} source pixels. Check the colored overlay; enter the actual length and unit, then Apply physical scale.")
        self.mode.set("add")
        self.redraw()

    def apply_image_scale(self):
        if not self._require_full_image_for_scale():
            return
        if not self.scale_candidate:
            messagebox.showwarning(APP_NAME, "Select a scale bar on the image before applying.", parent=self.root)
            return
        a, b, method = self.scale_candidate
        px = math.dist(a, b)
        try:
            real_length = float(self.scale_length.get().strip().replace(",", "."))
            unit = self.scale_unit.get().strip()
            if unit not in ("pm", "nm", "µm", "μm", "um", "mm", "cm", "dm", "m", "km", "Å", "A", "in", "ft"):
                raise CalibrationError("Choose a recognized physical length unit (for example µm, nm, mm, cm or m).")
            if not math.isfinite(real_length) or real_length <= 0:
                raise CalibrationError("Actual scale bar length must be positive and finite.")
            if px < 3:
                raise CalibrationError("The selected line is too short.")
            # Validate without modifying current scientific state.
            trial = copy.deepcopy(self.project)
            factor = trial.scale_full_image(*self.image.size, px, real_length, unit)
        except (ValueError, CalibrationError) as exc:
            messagebox.showerror(APP_NAME, f"Cannot apply scale:\n{exc}", parent=self.root)
            return
        self.snapshot()
        self.project = trial
        self.hide_saved_scale_overlay = False
        self.config["scale_reference"] = {
            "start": [float(a[0]), float(a[1])], "end": [float(b[0]), float(b[1])],
            "pixel_length": px, "physical_length": real_length,
            "unit": unit, "method": method,
            "edge_convention": EDGE_MODES.get(self.scale_edge_convention.get(), "center"),
        }
        self.scale_candidate = None
        self.scale_first_endpoint = None
        self.mode.set("add")
        for var, value in ((self.x_min, "0"), (self.x_max, format(self.project.x_axis.maximum, ".17g")),
                           (self.y_min, format(self.project.y_axis.minimum, ".17g")),
                           (self.y_max, format(self.project.y_axis.maximum, ".17g")),
                           (self.x_unit, unit), (self.y_unit, unit),
                           (self.x_scale, "linear"), (self.y_scale, "linear")):
            var.set(value)
        self.scale_status.set(f"Applied: {fmt(px)} px = {fmt(real_length)} {unit}; "
                              f"1 px = {fmt(factor)} {unit}. Saved in Session.")
        self.verify_result.set("")
        self.update_cal_status()
        self.update_selected()
        self.redraw()
        self.persist()

    def start_corner(self, corner):
        if not self.require_working_source():
            return
        self.pending_corner = corner
        self.mode.set("calibrate")
        self.status.set(f"Click the image at calibration corner {CORNER_LABELS[corner]}.")

    def reset_scale_calibration(self):
        if not self.config.get("scale_reference"):
            return
        if not messagebox.askyesno(APP_NAME,
                "Reset the physical scale to full-image pixels? Original raster points remain unchanged.",
                parent=self.root):
            return
        self.auto_calibrate_full_image()

    def clear_calibration(self):
        if not self.project.calibration.pixels:
            return
        self.snapshot()
        self.config["scale_reference"] = None
        self.scale_candidate = None
        self.scale_first_endpoint = None
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
        # Update rows in place: destroying/reinserting all items reset the
        # internal Treeview yview after every point acceptance, which made a
        # long curve list jump to its top. Preserve the user's scroll position.
        existing = set(self.curve_tree.get_children())
        wanted = {series.id for series in self.project.series}
        for obsolete in existing - wanted:
            self.curve_tree.delete(obsolete)
        for index, series in enumerate(self.project.series):
            family = series.parameter_value
            if family and series.parameter_unit:
                family += f" {series.parameter_unit}"
            label = series.name + (" (hidden)" if not series.visible else "")
            values = (label, family, len(series.points))
            if self.curve_tree.exists(series.id):
                self.curve_tree.item(series.id, values=values)
                self.curve_tree.move(series.id, "", index)
            else:
                self.curve_tree.insert("", index, iid=series.id, values=values)
        if selected and self.curve_tree.exists(selected):
            if self.curve_tree.selection() != (selected,):
                self.curve_tree.selection_set(selected)

    def on_curve_selected(self, _event=None):
        selected = self.curve_tree.selection()
        if selected:
            # Tree refreshes reselect the active row and may emit an event.
            # Only a genuine curve change invalidates transient proposals;
            # otherwise accepting the first segment would erase all others.
            if selected[0] != self.active_series_id:
                self.guide_points=[];self.assisted_proposal=None
                self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
                self._assist_drag=None;self._assist_preview_cursor=None
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
        self.guide_points=[];self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
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
        self.guide_points=[];self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
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
        if self.stale_source or self.catalog_session_invalid:
            messagebox.showerror(APP_NAME, "The source Image Dataset changed or is missing. Existing calibration cannot be reused silently.")
            return False
        return True

    def canvas_press(self, x, y):
        # Point edits are exclusively owned by the Curves tab. Other tabs cannot
        # accidentally insert, drag, or remove a scientific measurement.
        mode = self.mode.get()
        if mode in ("add", "edit", "delete", "guide", "proposal_edit", "correction") and not self._is_curves_tab(): return
        if mode in ("scale_detect", "scale_manual", "calibrate", "verify") and not self._is_calibration_tab(): return
        if not self.require_working_source(): return
        if mode in ("scale_detect", "scale_manual"):
            self.select_scale_point(x, y)
        elif mode == "calibrate":
            if self.pending_corner:
                self.snapshot()
                self.config["scale_reference"] = None
                self.scale_candidate = None
                self.scale_first_endpoint = None
                self.project.calibration.set_corner(self.pending_corner, x, y)
                self.project.recalculate_all_points()
                self.pending_corner = None
                self.mode.set("add")
                self.update_cal_status(); self.redraw(); self.persist()
        elif mode == "verify":
            self.verify(x, y)
        elif mode == "add":
            self.add_point(x, y)
        elif mode == "guide":
            if self.assisted_proposal is not None:
                self._proposal_history.clear();self._proposal_last_insert=None
                self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
            self.guide_points.append((float(x),float(y)))
            # For monotonic curves the operator may place guides in any click
            # order; scientific X/Y determines the segment order automatically.
            axis = self._proposal_guide_axis()
            if axis is not None:
                def guide_key(pt):
                    try:
                        sx,sy=self.project.pixel_to_calibrated(*pt)
                        return sx if axis=="x" else sy
                    except CalibrationError:
                        return pt[0] if axis=="x" else -pt[1]
                self.guide_points.sort(key=guide_key)
            self.assist_status.set(f"{len(self.guide_points)} guide(s) placed; proposal not yet accepted.")
            self.redraw()
        elif mode == "proposal_edit":
            if self._assist_move_target is not None:
                hit=self._assist_move_target
                self._assist_move_target=None
                if hit[0]=="guide":
                    i=hit[1]
                    if ((i>0 and i-1 in self.assist_accepted_segments) or
                        i in self.assist_accepted_segments):
                        self.assist_status.set("Cannot move a guide next to an accepted segment.")
                        return
                    self._assist_drag=("guide",i)
                elif hit[1] not in self.assist_accepted_segments:
                    self._assist_drag=("insert",hit[1],hit[2])
                else:
                    self.assist_status.set("Cannot edit an accepted segment.")
                    return
                self._assist_preview_cursor=(float(x),float(y))
                self.redraw()
            else:
                self._begin_proposal_edit(x,y)
        elif mode == "correction":
            self.add_correction_point(x,y)
        elif mode == "delete":
            hit=self._proposal_hit(x,y)
            if hit is not None:
                self._delete_proposal_point(hit)
                return
            self.begin_drag(x,y)
            if self.selected_point() is not None:
                # Delete works by clicking a point directly, with Undo support.
                self.dragging=False;self.drag_snapshot=None
                self.delete_selected_point()
        elif mode == "edit":
            hit=self._proposal_hit(x,y)
            if hit is not None:
                self._begin_proposal_edit(x,y)
            else:
                self.begin_drag(x, y)

    def canvas_drag(self, x, y):
        if not self._is_curves_tab(): return
        if self.mode.get() in ("proposal_edit", "edit") and self._assist_drag is not None:
            self._assist_preview_cursor=(float(x),float(y))
            self.redraw();return
        if not self.dragging:
            return
        point = self.selected_point()
        if not point:
            return
        sx, sy = self.snap(x, y)
        point.manual_pixel_x, point.manual_pixel_y = x, y
        point.pixel_x, point.pixel_y = sx, sy
        self.project.update_point_calibration(point)
        self._sort_series(self.active_series())
        self.update_selected(); self.redraw()

    def canvas_release(self, _x, _y):
        if not self._is_curves_tab(): return
        if self.mode.get() in ("proposal_edit", "edit") and self._assist_drag is not None:
            self._finish_proposal_edit(float(_x),float(_y));return
        if self.dragging and self.drag_snapshot is not None:
            self.undo_stack.append(self.drag_snapshot)
            self.undo_stack = self.undo_stack[-100:]
            self.redo_stack.clear()
            self.drag_snapshot = None
            self.dragging = False
            self._sort_series(self.active_series())
            self.refresh_curve_tree(); self.persist()

    def verify(self, x, y, *, draw=True):
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
        if draw:
            self.verify_point = (x, y)
            self.redraw()

    def clear_guides(self):
        self._proposal_history.clear();self._proposal_last_insert=None;self._assist_move_target=None
        self.guide_points=[];self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
        self.assist_status.set("Guide points cleared. No curve points changed.")
        self.redraw()

    def reject_guided_trace(self):
        self._proposal_history.clear();self._proposal_last_insert=None;self._assist_move_target=None
        self.assisted_proposal=None;self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
        self.assist_status.set("Proposal rejected. Guide points kept for refinement.")
        self.redraw()

    def propose_guided_trace(self):
        if self.assist_baseline_request is not None:
            self.assist_status.set("The previous numerical guide request is still running.")
            return
        if not self._is_curves_tab() or not self.require_working_source(): return
        if not self.active_series():
            messagebox.showinfo(APP_NAME,"Select an existing curve first.",parent=self.root);return
        if len(self.guide_points)<2:
            messagebox.showinfo(APP_NAME,"Place at least two guide points on the image.",parent=self.root);return
        try:
            self._assist_context=(self.current_doc_id,self.active_series_id,
                                  (self.config.get("source") or {}).get("sha256"),tuple(self.guide_points))
            self._assist_pending_points=samples_from_guides(self.guide_points,step=float(self.assist_step.get()))
            knots=[0.]
            for a,b in zip(self.guide_points,self.guide_points[1:]):knots.append(knots[-1]+math.dist(a,b))
            queries=[0.]
            for a,b in zip(self._assist_pending_points,self._assist_pending_points[1:]):
                queries.append(queries[-1]+math.dist(a,b))
            payloads=[" ".join(format(v,".16g") for v in arr) for arr in
                      (knots,[p[0] for p in self.guide_points],[p[1] for p in self.guide_points],queries)]
            # Non-blocking host call: NUMERIC_API_v1 is a separate CORE-owned
            # service; the fit may initialize an Octave worker. This call is
            # advisory only, never a commitment of user-created points.
            self.assist_baseline_request=self.rpc.begin("ASSIST_FIT",*payloads)
            self.assist_status.set("Generating optional GX-TXT numeric guide fit...")
            self.root.after(80,self._poll_assisted_fit)
        except (RpcError,ValueError) as exc:
            self._finish_guided_proposal(None,f"CORE fitting unavailable: {exc}")

    def _poll_assisted_fit(self):
        rid=self.assist_baseline_request
        if rid is None:return
        try: value=self.rpc.poll_response(rid)
        except RpcError as exc:
            self.assist_baseline_request=None
            self._finish_guided_proposal(None,f"CORE fitting unavailable: {exc}")
            return
        if value is None:
            self.root.after(80,self._poll_assisted_fit);return
        self.assist_baseline_request=None
        reference=None
        try:
            parsed=json.loads(value)
            if len(parsed)==len(self._assist_pending_points):
                reference=[tuple(map(float,v)) for v in parsed]
        except (ValueError,TypeError):pass
        self._finish_guided_proposal(reference,"CORE interpolation" if reference else "Local guide interpolation")

    def _finish_guided_proposal(self,reference,note):
        if self._assist_context is not None:
            current=(self.current_doc_id,self.active_series_id,
                     (self.config.get("source") or {}).get("sha256"),tuple(self.guide_points))
            if current!=self._assist_context or not self._is_curves_tab():
                self.assisted_proposal=None
                self.assist_status.set("The source, curve or guides changed; the proposal was discarded.")
                self._assist_context=None
                return
        self._assist_context=None
        try:
            use_image=self._trace_input_image()
            result=propose(use_image,self.guide_points,radius=int(self.assist_radius.get()),
                           step=float(self.assist_step.get()),reference=reference)
            self.assisted_proposal=result
            self._proposal_history.clear();self._proposal_last_insert=None
            self.assist_accepted_segments=set();self.assist_accepted_point_ids={};self._assist_sampling_spec=None
            self._sync_assist_segment_control()
            self.assist_status.set(f"Proposal: {len(result.points)} points / {result.segment_count} segments; "
                f"{len(result.ambiguous_segments)} possible ambiguous segment(s). {note}. "
                "Edit or accept explicitly.")
            self.redraw()
        except (ValueError,TypeError) as exc:
            self.assisted_proposal=None
            self.assist_status.set(str(exc))

    def _sync_assist_segment_control(self, preferred=None):
        """Keep Segment # bounded by the ACTUAL proposal segment count.

        Previously the spinbox admitted 1..500 with no relationship to the
        generated proposal; an out-of-range value rejected all corrections.
        This operation does not modify scientific data or stored guide points.
        """
        count = len(self.assisted_proposal.segments) if self.assisted_proposal else 0
        if hasattr(self, "assist_segment_spin"):
            self.assist_segment_spin.configure(to=max(1, count))
        try:
            current = int(self.assist_segment.get()) if preferred is None else int(preferred)
        except (ValueError, TypeError, tk.TclError):
            current = 1
        current = min(max(1, current), max(1, count))
        self.assist_segment.set(current)
        return current

    def _proposal_guide_axis(self):
        """Scientific ordering axis for assistant guide topology, if set.

        Ordering by X/Y is an explicit configuration choice even if the
        operator did not declare monotonicity. Never sort an insertion-order
        free-form trace behind the operator's back.
        """
        mono = self.curve_monotonicity.get()
        if mono in ("x", "y"):
            return mono
        source = self.point_order_source.get()
        return source if source in ("x", "y") else None

    def _correction_segment(self, x, y):
        """Choose a correction interval from the guides, not from bad pixels.

        For declared X/Y monotonicity, the clicked scientific coordinate
        determines the unique interval. The bad proposal can be arbitrarily
        far from this click. For a free-form curve we respect a valid manual
        Segment #, and recover invalid stale numbers using guide chords.
        """
        proposal = self.assisted_proposal
        if proposal is None or not proposal.segments:
            raise ValueError("Generate a proposal before adding a correction point.")
        count = len(proposal.segments)
        axis = self._proposal_guide_axis()
        if axis in ("x", "y"):
            def coord(pt):
                try:
                    xx, yy = self.project.pixel_to_calibrated(*pt)
                    return xx if axis == "x" else yy
                except CalibrationError:
                    return pt[0] if axis == "x" else -pt[1]
            selected = coord((x, y))
            vals = [coord(p) for p in self.guide_points]
            span = max(vals) - min(vals)
            tol = max(1e-10, span * 1e-9)
            if any(abs(selected - val) <= tol for val in vals):
                raise ValueError("Correction lies on an existing guide; move that guide with Edit proposal.")
            matches = [i for i, (a, b) in enumerate(zip(vals, vals[1:]))
                       if min(a, b) + tol < selected < max(a, b) - tol]
            if len(matches) != 1:
                raise ValueError("Correction is outside or overlaps the guided monotonic interval; use Add guide or adjust guides.")
            seg = matches[0]
            self._sync_assist_segment_control(seg+1)
            return seg
        try:
            idx = int(self.assist_segment.get())-1
        except (ValueError, tk.TclError):
            idx = -1
        if 0 <= idx < count:
            return idx
        # Invalid stale segment numbers should never silently discard a click.
        # The nearest operator-guide chord is a fallback, with no proximity
        # threshold. Nonmonotonic loops still require an explicit valid choice.
        def chord_distance(a,b,pt):
            vx,vy = b[0]-a[0],b[1]-a[1]
            norm = vx*vx+vy*vy
            t = max(0.,min(1.,((pt[0]-a[0])*vx+(pt[1]-a[1])*vy)/norm)) if norm else 0.
            return math.dist((a[0]+t*vx,a[1]+t*vy),pt)
        idx = min(range(count), key=lambda i: chord_distance(
            self.guide_points[i],self.guide_points[i+1],(x,y)))
        self._sync_assist_segment_control(idx+1)
        return idx

    def _trace_input_image(self):
        """Return unmodified RGB image data, never opacity-composited display.

        Processed results are allowed only when their source+pipeline checksum
        matches the current configuration. Source image always remains canonical.
        """
        if self.image is None:raise ValueError("Source image is unavailable.")
        choice=self.assist_source.get()
        source=self.config.get("source",{}) if self.config else {}
        fingerprint=image_fingerprint(source.get("dataset_id",""),source.get("sha256",""),
                                     self.processing_operations,self.processing_engine_version)
        ready=self.processed_image is not None and self.processed_fingerprint==fingerprint
        if choice=="processed" and not ready:
            raise ValueError("Processed image is not ready for the current pipeline. Use Image Processing / Preview first.")
        if choice=="processed" or (choice=="auto" and ready):return self.processed_image
        return self.image

    def _proposal_state(self):
        """Reversible, local editing state; accepted scientific points stay outside."""
        try:segment=int(self.assist_segment.get())
        except (ValueError,tk.TclError):segment=1
        return (copy.deepcopy(self.guide_points),copy.deepcopy(self.assisted_proposal),
                self.assist_accepted_segments.copy(),copy.deepcopy(self.assist_accepted_point_ids),
                self._assist_sampling_spec,segment)

    def _restore_proposal_state(self,state):
        (self.guide_points,self.assisted_proposal,self.assist_accepted_segments,
         self.assist_accepted_point_ids,self._assist_sampling_spec,segment)=copy.deepcopy(state)
        self._sync_assist_segment_control(segment)
        self._assist_drag=None;self._assist_preview_cursor=None;self._assist_move_target=None
        self.redraw()

    def _checkpoint_proposal(self,before,inserted=None):
        self._proposal_history.append((before,inserted))
        self._proposal_history=self._proposal_history[-100:]
        self._proposal_last_insert=inserted

    def undo_proposal_edit(self):
        """Undo only a transient proposal edit, not persisted Session points."""
        if not self._proposal_history:
            self.assist_status.set("No proposal edit to undo.")
            return
        state,_inserted=self._proposal_history.pop()
        self._restore_proposal_state(state)
        self._proposal_last_insert=self._proposal_history[-1][1] if self._proposal_history else None
        self.assist_status.set("Last proposal edit undone. Scientific points unchanged.")

    def _proposal_hit(self,x,y,threshold=12):
        """Select real raster guides or generated points in *screen pixels*.

        The source image can be zoomed; a constant image-pixel tolerance would
        become unusable or overly aggressive at different zoom levels.
        """
        if self.assisted_proposal is None:return None
        cx,cy=self.canvas.image_to_canvas(x,y)
        best=None;distance=threshold
        for i,pt in enumerate(self.guide_points):
            px,py=self.canvas.image_to_canvas(*pt)
            d=math.hypot(px-cx,py-cy)
            if d<=distance:
                best=("guide",i);distance=d
        if best and distance<=threshold:return best
        for i,seg in enumerate(self.assisted_proposal.segments):
            if i in self.assist_accepted_segments:continue
            for j,pt in enumerate(seg[1:-1],1):
                px,py=self.canvas.image_to_canvas(*pt)
                d=math.hypot(px-cx,py-cy)
                if d<distance:
                    best=("generated",i,j);distance=d
        return best

    def _scientific_hit(self,x,y,threshold=10):
        series=self.active_series()
        if not series:return None
        cx,cy=self.canvas.image_to_canvas(x,y)
        best=None;distance=threshold
        for point in series.points:
            px,py=self.canvas.image_to_canvas(point.pixel_x,point.pixel_y)
            d=math.hypot(px-cx,py-cy)
            if d<=distance:
                best=point;distance=d
        return best

    def canvas_right_click(self,x,y,root_x,root_y):
        """Context menu on a guide, generated proposal point or saved point.

        Right-button dragging still pans everywhere else on the canvas.
        The action uses the true hit target rather than the active radio mode.
        """
        if not self._is_curves_tab() or self.image is None:return False
        hit=self._proposal_hit(x,y)
        scientific=self._scientific_hit(x,y)
        if hit is None and scientific is None:return False
        menu=tk.Menu(self.root,tearoff=False)
        if hit is not None:
            title="Guide point" if hit[0]=="guide" else "Proposed point"
            menu.add_command(label=title,state="disabled")
            menu.add_separator()
            menu.add_command(label="Move point",command=lambda:self._prepare_proposal_move(hit))
            menu.add_command(label="Delete point",command=lambda:self._delete_proposal_point(hit))
            if self._proposal_history:
                menu.add_separator()
                menu.add_command(label="Undo last proposal edit",command=self.undo_proposal_edit)
        elif scientific is not None:
            pid=scientific.id
            menu.add_command(label="Move scientific point",command=lambda:self._prepare_scientific_move(pid))
            menu.add_command(label="Delete scientific point",command=lambda:self._delete_scientific_by_id(pid))
        try:menu.tk_popup(root_x,root_y)
        finally:menu.grab_release()
        return True

    def _prepare_proposal_move(self,hit):
        self.mode.set("proposal_edit")
        self._assist_move_target=hit
        self.assist_status.set("Move point: click its new position, or drag from the current position.")

    def _prepare_scientific_move(self,pid):
        self.mode.set("edit")
        self.selected_point_id=pid
        self.update_selected()
        self.status.set("Move scientific point: left-click and drag it.")

    def _delete_scientific_by_id(self,pid):
        series=self.active_series()
        point=next((p for p in series.points if p.id==pid),None) if series else None
        if point is None:return
        self.selected_point_id=pid
        self.delete_selected_point()

    def _delete_proposal_point(self,hit):
        """Delete generated vertex, or remove a correction guide and rejoin.

        Deleting the last inserted correction restores the exact previous
        proposal (not an approximate recalculation). Earlier edits are restored
        with Undo proposal edit or rejoined by the image-guided engine.
        """
        if self.assisted_proposal is None:return
        try:
            before=self._proposal_state()
            typ=hit[0]
            if typ=="guide":
                index=hit[1]
                if ((index>0 and index-1 in self.assist_accepted_segments) or
                    index in self.assist_accepted_segments):
                    raise ValueError("This guide borders accepted segments and cannot be deleted from the proposal.")
                # Removing the most recent correction is an exact rollback.
                if (self._proposal_history and self._proposal_history[-1][1] is not None and
                        self._proposal_history[-1][1][0]==index and
                        tuple(self._proposal_history[-1][1][1])==tuple(self.guide_points[index]) and
                        len(self._proposal_history[-1][0][0])+1==len(self.guide_points)):
                    self.undo_proposal_edit()
                    self.assist_status.set("Correction point deleted; exact previous proposal restored.")
                    return
                if len(self.guide_points)<=2:
                    raise ValueError("At least two guides are required; use Clear guides to start again.")
                if index in (0,len(self.guide_points)-1):
                    raise ValueError("An endpoint guide cannot be deleted here; use Clear guides or move it.")
                from assisted_tracing import remove_guide
                guides,result=remove_guide(self.assisted_proposal,self._trace_input_image(),
                   self.guide_points,index,radius=int(self.assist_radius.get()),
                   step=float(self.assist_step.get()))
                self.guide_points,self.assisted_proposal=guides,result
                self.assist_accepted_segments={j if j<index-1 else j-1 for j in self.assist_accepted_segments}
                self.assist_accepted_point_ids={j if j<index-1 else j-1:ids for j,ids in self.assist_accepted_point_ids.items()}
            else:
                _type,seg,j=hit
                if seg in self.assist_accepted_segments:
                    raise ValueError("This segment is accepted; use Undo for scientific points.")
                curve=self.assisted_proposal.segments[seg]
                if j<=0 or j>=len(curve)-1:
                    raise ValueError("Guide endpoints cannot be deleted as generated points.")
                curve.pop(j)
                from assisted_tracing import compose_segments
                self.assisted_proposal.points=compose_segments(self.assisted_proposal.segments)
            self._checkpoint_proposal(before)
            self._sync_assist_segment_control()
            self.assist_status.set("Proposal point deleted; use Undo proposal edit to restore it.")
            self.redraw()
        except (ValueError,IndexError,RuntimeError) as exc:
            self.assist_status.set("Delete rejected: "+str(exc))

    def add_correction_point(self,x,y):
        """Insert a mandatory guide anywhere inside the source raster.

        Neither the distance to the proposed path nor Corridor limits this
        operation. For monotonic X/Y, the point selects its interval itself.
        Scientific points are untouched until explicit Accept.
        """
        if not self._is_curves_tab():
            self.assist_status.set("Switch to Curves before editing the proposal.")
            return
        if self.assisted_proposal is None:
            self.assist_status.set("Generate a proposal before adding a correction point.")
            return
        try:
            result=self.assisted_proposal
            image=self._trace_input_image()
            w,h=image.size
            if not (0<=x<w and 0<=y<h):
                raise ValueError("Click inside the source image.")
            seg=self._correction_segment(x,y)
            if seg in self.assist_accepted_segments:
                raise ValueError(f"Segment {seg+1} is already accepted; edit an unaccepted segment.")
            curve=result.segments[seg]
            # Even two-point paths must accept a new operator correction.
            index=(min(range(1,len(curve)-1),key=lambda j:math.dist(curve[j],(x,y)))
                   if len(curve)>2 else 0)
            before=self._proposal_state()
            guides,candidate=insert_correction(result,image,self.guide_points,seg,index,(x,y),
                                radius=int(self.assist_radius.get()),step=float(self.assist_step.get()))
            self._checkpoint_proposal(before, inserted=(seg+1,(float(x),float(y))))
            self.guide_points,self.assisted_proposal=guides,candidate
            self.assist_accepted_segments={i if i<seg else i+1 for i in self.assist_accepted_segments}
            self.assist_accepted_point_ids={i if i<seg else i+1: ids
                                               for i,ids in self.assist_accepted_point_ids.items()}
            self._sync_assist_segment_control(seg+1)
            msg=(f"Correction guide inserted into segment {seg+1}; "
                 "two adjacent spans recalculated. Accept explicitly.")
            self.assist_status.set(msg)
            self.status.set(msg)
        except (ValueError,TypeError,IndexError,RuntimeError) as exc:
            msg="Correction rejected: "+str(exc)
            self.assist_status.set(msg)
            self.status.set(msg)
        self.redraw()

    def _begin_proposal_edit(self,x,y):
        result=self.assisted_proposal
        if result is None:
            self.assist_status.set("Generate a proposal before editing it.");return
        cx,cy=self.canvas.image_to_canvas(x,y)
        for k,p in enumerate(self.guide_points):
            px,py=self.canvas.image_to_canvas(*p)
            if math.hypot(px-cx,py-cy)<=12:
                if (k and k-1 in self.assist_accepted_segments) or k in self.assist_accepted_segments:
                    self.assist_status.set("This guide borders an already accepted segment; accepted points cannot be moved here.")
                    return
                self._assist_drag=("guide",k)
                self._assist_preview_cursor=(float(x),float(y))
                return
        best=(float('inf'),None,None)
        for k,seg in enumerate(result.segments):
            if k in self.assist_accepted_segments:continue
            for j,p in enumerate(seg[1:-1],1):
                px,py=self.canvas.image_to_canvas(*p)
                d=math.hypot(px-cx,py-cy)
                if d<best[0]:best=(d,k,j)
        if best[1] is None or best[0]>60:
            self.assist_status.set("Click close to the proposed path to add a correction point.")
            return
        self._assist_drag=("insert",best[1],best[2])
        self._assist_preview_cursor=(float(x),float(y))
        self.redraw()

    def _finish_proposal_edit(self,x,y):
        selection=self._assist_drag
        self._assist_drag=None;self._assist_preview_cursor=None
        if selection is None or self.assisted_proposal is None:return
        if not self.require_working_source():return
        try:
            image=self._trace_input_image()
            w,h=image.size
            x=max(0,min(w-1,x));y=max(0,min(h-1,y))
            radius=int(self.assist_radius.get());step=float(self.assist_step.get())
            before=self._proposal_state()
            if selection[0]=="guide":
                index=selection[1];old=self.guide_points[index]
                axis = self._proposal_guide_axis()
                if axis is not None:
                    def axis_val(pt):
                        try:
                            cx,cy=self.project.pixel_to_calibrated(*pt)
                            return cx if axis=="x" else cy
                        except CalibrationError:
                            return pt[0] if axis=="x" else -pt[1]
                    value=axis_val((x,y))
                    if ((index>0 and value<axis_val(self.guide_points[index-1])) or
                        (index+1<len(self.guide_points) and value>axis_val(self.guide_points[index+1]))):
                        raise ValueError("Guide would reverse the monotonic axis order; add a new guide in the desired interval.")
                previous_proposal=copy.deepcopy(self.assisted_proposal)
                self.guide_points[index]=(x,y)
                try:
                    for changed in (index-1,index):
                        if 0<=changed<len(self.guide_points)-1:
                            self.assisted_proposal=repair(self.assisted_proposal,image,self.guide_points,changed,
                                                         radius=radius,step=step)
                except Exception:
                    # An error in the second interval must not leave half of a
                    # two-sided guide edit applied. This is one atomic proposal edit.
                    self.guide_points[index]=old
                    self.assisted_proposal=previous_proposal
                    raise
            else:
                _,seg,point=selection
                if self._proposal_guide_axis() is not None:
                    # The mouse was pressed on a generated vertex of segment
                    # N, but the operator may drag it much farther, into an
                    # entirely different X/Y interval. Insert it where the
                    # RELEASE coordinate belongs, not in the initial segment.
                    # This maintains G1..GN order and segment numbering.
                    seg=self._correction_segment(x,y)
                    target=self.assisted_proposal.segments[seg]
                    point=(min(range(1,len(target)-1),
                               key=lambda j:math.dist(target[j],(x,y)))
                           if len(target)>2 else 0)
                if seg in self.assist_accepted_segments:
                    raise ValueError("The corrected position falls into an already accepted segment.")
                guides, candidate = insert_correction(self.assisted_proposal,image,
                    self.guide_points,seg,point,(x,y),radius=radius,step=step)
                # Apply only after all validation and computation succeeds.
                self.guide_points,self.assisted_proposal=guides,candidate
                self._sync_assist_segment_control(seg+1)
                self.assist_accepted_segments={i if i<seg else i+1 for i in self.assist_accepted_segments}
                self.assist_accepted_point_ids={i if i<seg else i+1:ids
                                               for i,ids in self.assist_accepted_point_ids.items()}
            self._checkpoint_proposal(before, inserted=(seg+1,(float(x),float(y))) if selection[0]!="guide" else None)
            self.assist_status.set("Correction applied. Only affected intervals recalculated; "
                                   "remaining proposal preserved. Accept or reject explicitly.")
        except (ValueError,IndexError,RuntimeError) as exc:
            self.assist_status.set("Correction rejected: "+str(exc))
        self.redraw()

    def _accept_assisted_segments(self, indices):
        if not self._is_curves_tab() or not self.require_working_source():return
        series=self.active_series();proposal=self.assisted_proposal
        if series is None or proposal is None:return
        indices=[i for i in indices if 0<=i<len(proposal.segments) and i not in self.assist_accepted_segments]
        if not indices:
            self.assist_status.set("The selected segment has already been accepted.");return
        try:
            density=self._valid_assist_output_points()
            if self.assist_accepted_segments and self._assist_sampling_spec is not None and density != self._assist_sampling_spec:
                raise ValueError("Output points changed. Use Resample accepted before accepting another segment.")
            samples=self._sample_assisted_segments(indices=indices, accepting=True)
        except (ValueError, TypeError, tk.TclError) as exc:
            self.assist_status.set(str(exc));return
        count=sum(len(samples[i]) - (1 if i>0 and (i-1 in indices or i-1 in self.assist_accepted_segments) else 0)
                  - (1 if i+1 in self.assist_accepted_segments and i+1 not in indices else 0) for i in indices)
        if not messagebox.askyesno(APP_NAME,
            f"Accept {len(indices)} segment(s), {count} proposed points into '{series.name}'? "
            "Existing manually placed scientific points remain unchanged.",parent=self.root):return
        self.snapshot()
        for i in indices:
            seg=samples[i]
            start=1 if i>0 and (i-1 in indices or i-1 in self.assist_accepted_segments) else 0
            end=len(seg)-1 if i+1 in self.assist_accepted_segments and i+1 not in indices else len(seg)
            stored=[]
            for x,y in seg[start:end]:
                p=DigitizedPoint(manual_pixel_x=x,manual_pixel_y=y,pixel_x=x,pixel_y=y,origin="assisted")
                self.project.update_point_calibration(p)
                series.points.append(p)
                stored.append(p.id)
            self.assist_accepted_point_ids[i]=stored
        self._sort_series(series)
        # Accepted scientific points may no longer be rolled back by a
        # transient *proposal* checkpoint from before acceptance.
        self._proposal_history.clear();self._proposal_last_insert=None
        self.assist_accepted_segments.update(indices)
        self._assist_sampling_spec=density
        self.assist_status.set(
            f"Accepted {len(self.assist_accepted_segments)}/{len(proposal.segments)} segments. "
            f"{count} assisted points added; output density can be changed using Resample accepted.")
        self.refresh_curve_tree();self.redraw();self.persist()

    def resample_accepted_trace(self):
        """Change the density of THIS proposal's accepted points, not prior work.

        Existing manually placed points and unrelated assisted batches are left
        untouched. Source proposal remains a transient candidate, and shared
        guide endpoints are included exactly once after reconstruction.
        """
        if not self._is_curves_tab() or not self.require_working_source():return
        if not self.assist_accepted_segments or not self.assisted_proposal:
            self.assist_status.set("Accept at least one segment before resampling.");return
        series=self.active_series()
        if series is None:return
        try:samples=self._sample_assisted_segments(indices=sorted(self.assist_accepted_segments))
        except (ValueError,TypeError,tk.TclError) as exc:
            self.assist_status.set(str(exc));return
        oldids={pid for ids in self.assist_accepted_point_ids.values() for pid in ids}
        if not oldids or not oldids.issubset({p.id for p in series.points}):
            self.assist_status.set("Accepted points changed or were undone; regenerate a proposal before resampling.")
            return
        indices=sorted(self.assist_accepted_segments)
        n=sum(len(samples[i])-(1 if i-1 in self.assist_accepted_segments else 0) for i in indices)
        if not messagebox.askyesno(APP_NAME,
              f"Replace {len(oldids)} assisted points from this proposal with {n} resampled points? "
              "All other curve points are preserved. Previously edited points from this proposal "
              "will be replaced; Undo can restore them.",parent=self.root):return
        self.snapshot()
        series.points=[p for p in series.points if p.id not in oldids]
        replacement={}
        for i in indices:
            fragment=samples[i][1:] if i-1 in self.assist_accepted_segments else samples[i]
            ids=[]
            for x,y in fragment:
                p=DigitizedPoint(manual_pixel_x=x,manual_pixel_y=y,pixel_x=x,pixel_y=y,origin="assisted")
                self.project.update_point_calibration(p);series.points.append(p);ids.append(p.id)
            replacement[i]=ids
        self.assist_accepted_point_ids=replacement
        self._assist_sampling_spec=self._valid_assist_output_points()
        self._sort_series(series)
        self.assist_status.set(f"Resampled accepted part to {n} points. Manual and unrelated points unchanged.")
        self.refresh_curve_tree();self.redraw();self.persist()

    def accept_guided_segment(self):
        try:index=int(self.assist_segment.get())-1
        except (ValueError,tk.TclError):self.assist_status.set("Select a valid segment number.");return
        self._accept_assisted_segments([index])

    def accept_guided_trace(self):
        if self.assisted_proposal is not None:
            self._accept_assisted_segments(range(len(self.assisted_proposal.segments)))

    def _valid_assist_output_points(self):
        """0 means keep native proposal density; nonzero is exact final count.

        This value belongs to the selected Session configuration, never the
        unrelated CORE User/Session defaults of another profile.
        """
        value = int(self.assist_output_points.get())
        if not 0 <= value <= 10000 or value == 1:
            raise ValueError('Output points must be 0 (original density) or 2..10000.')
        return value

    def _sample_assisted_segments(self, indices=None, *, accepting=False):
        """Sample N points for the actual acceptance, never divide them across
        other segments that are NOT being accepted.

        In <=1.2.24, Output points=100 allocated e.g. eight points to one
        segment if the proposal had many segments. For Accept segment N is now
        the requested number of NEW scientific points for that click; for Accept
        across all segments N is the total of that acceptance. Resample accepted
        distributes N across precisely the already accepted segments.
        """
        proposal = self.assisted_proposal
        if proposal is None:
            raise ValueError('Generate a proposal before accepting points.')
        target = self._valid_assist_output_points()
        original = [list(segment) for segment in proposal.segments]
        if target == 0:
            return original
        selected = sorted(set(range(len(original)) if indices is None else indices))
        if not selected:
            return original
        selected_set = set(selected)
        already = self.assist_accepted_segments if accepting else set()
        # The writer removes a shared guide once: whenever adjacent intervals
        # are selected together or already accepted outside this selection.
        duplicates = 0
        for i in selected:
            if i > 0 and (i-1 in selected_set or i-1 in already):
                duplicates += 1
            if accepting and i+1 in already and i+1 not in selected_set:
                duplicates += 1
        # sample_proposal_segments reserves one coincident junction per pair
        # of supplied segments. Rebalance for disjoint selections and for
        # junctions already stored by previous segment accepts.
        required = target - (len(selected) - 1) + duplicates
        if required < len(selected) + 1:
            raise ValueError(f'Output points {target} too small for {len(selected)} selected segment(s).')
        sampled = sample_proposal_segments([original[i] for i in selected],required)
        for i, part in zip(selected, sampled):
            original[i] = part
        return original

    def assist_density_changed(self, _event=None):
        """Persist a valid requested density; do not change accepted points."""
        try:
            self._valid_assist_output_points()
        except (ValueError, tk.TclError):
            return
        self.persist()

    def _ordering_policy(self):
        return normalize_ordering({"monotonicity":self.curve_monotonicity.get(),
                                   "source":self.point_order_source.get()})

    def _sort_series(self,series):
        order_series(series,self._ordering_policy())

    def add_point(self, x, y):
        if not self._is_curves_tab(): return
        series = self.active_series()
        if not series:
            messagebox.showinfo(APP_NAME, "Create or select an active curve first.")
            return
        self.snapshot()
        sx, sy = self.snap(x, y)
        point = DigitizedPoint(manual_pixel_x=x, manual_pixel_y=y, pixel_x=sx, pixel_y=sy)
        self.project.update_point_calibration(point)
        series.points.append(point)
        self._sort_series(series)
        self.selected_point_id = point.id
        self.refresh_curve_tree(); self.update_selected(); self.redraw(); self.persist()

    def begin_drag(self, x, y):
        if not self._is_curves_tab(): return
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
        self.dragging = bool(best) and self.mode.get()=="edit"
        self.drag_snapshot = self.serialize_configuration() if best else None
        self.update_selected(); self.redraw()

    def selected_point(self):
        series = self.active_series()
        return next((p for p in series.points if p.id == self.selected_point_id), None) if series else None

    def delete_selected_point(self):
        if not self._is_curves_tab(): return
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
        if not hasattr(self, "canvas"): return
        self._redraw_one(self.canvas)
        if hasattr(self, "compare_original_canvas"):
            self._redraw_one(self.compare_original_canvas)
            self._redraw_one(self.compare_processed_canvas)

    def _redraw_one(self, canvas):
        canvas.delete("overlay")
        if not self.image: return
        # Persistent and preview reference markings are image-space overlays.
        reference = self.config.get("scale_reference") or {}
        overlay_ref = self.scale_candidate
        if overlay_ref:
            # A tentative reference must always be visible for validation,
            # even if a saved reference overlay is hidden in Viewer settings.
            a, b, _method = overlay_ref
            color = "#ff33ff"  # magenta preview against bright/dark scale bars
            text = f"Preview: {fmt(math.dist(a, b))} px"
        elif self.show_scale_overlay.get() and not self.hide_saved_scale_overlay and reference:
            a, b = reference.get("start"), reference.get("end")
            color = "#39ff14"  # lime green for an applied reference
            text = f"{fmt(float(reference.get('physical_length', 0)))} {reference.get('unit', '')}"
        else:
            a = b = None
        if a is not None and b is not None:
            ax, ay = canvas.image_to_canvas(*a)
            bx, by = canvas.image_to_canvas(*b)
            canvas.create_line(ax, ay, bx, by, fill="black", width=7, tags=("overlay",))
            canvas.create_line(ax, ay, bx, by, fill=color, width=3, tags=("overlay",))
            for xx, yy in ((ax, ay), (bx, by)):
                canvas.create_oval(xx-5, yy-5, xx+5, yy+5, fill="black", outline=color,
                                        width=2, tags=("overlay",))
            tx, ty = (ax+bx)/2, (ay+by)/2-15
            canvas.create_text(tx+1, ty+1, text=text, fill="black", font=("TkDefaultFont", 10, "bold"),
                                    tags=("overlay",))
            canvas.create_text(tx, ty, text=text, fill=color, font=("TkDefaultFont", 10, "bold"),
                                    tags=("overlay",))
        if self.scale_first_endpoint is not None:
            xx, yy = canvas.image_to_canvas(*self.scale_first_endpoint)
            canvas.create_oval(xx-6, yy-6, xx+6, yy+6, outline="#ff33ff", width=3, tags=("overlay",))
        for corner, point in (self.project.calibration.pixels.items()
                              if self.show_calibration_corners.get() else ()):
            x, y = canvas.image_to_canvas(*point)
            radius = 6
            canvas.create_rectangle(x-radius, y-radius, x+radius, y+radius, outline="cyan", width=2, tags=("overlay",))
            canvas.create_text(x+9, y-9, text=CORNER_LABELS[corner], fill="cyan", anchor="sw", tags=("overlay",))
        if self._is_curves_tab() and canvas is self.canvas:
            for index,(gx,gy) in enumerate(self.guide_points,1):
                u,v=canvas.image_to_canvas(gx,gy)
                canvas.create_oval(u-5,v-5,u+5,v+5,outline="#ffad31",width=2,tags=("overlay",))
                canvas.create_text(u+8,v-8,text=f"G{index}",fill="#ffad31",anchor="sw",tags=("overlay",))
            if self.assisted_proposal is not None:
                for i,segment in enumerate(self.assisted_proposal.segments):
                    coords=[]
                    for gx,gy in segment:
                        u,v=canvas.image_to_canvas(gx,gy);coords.extend((u,v))
                    if len(coords)>=4:
                        color="#7be05b" if i in self.assist_accepted_segments else (
                              "#ff70da" if i in self.assisted_proposal.ambiguous_segments else "#33e8df")
                        canvas.create_line(*coords,fill=color,width=2,dash=(4,3),tags=("overlay",))
                    if self.mode.get() in ("edit", "delete", "proposal_edit") and i not in self.assist_accepted_segments:
                        # Sparse handles avoid turning dense scientific curves
                        # into an opaque row of selectable circles.
                        stride=max(1,len(segment)//55)
                        for q in range(1,len(segment)-1,stride):
                            u,v=canvas.image_to_canvas(*segment[q])
                            canvas.create_oval(u-2,v-2,u+2,v+2,fill=color,outline="",tags=("overlay",))
            if self._assist_preview_cursor is not None:
                u,v=canvas.image_to_canvas(*self._assist_preview_cursor)
                canvas.create_oval(u-7,v-7,u+7,v+7,outline="#ff65ef",width=3,tags=("overlay",))
        if self.mode.get() == "verify" and self.verify_point is not None:
            cx, cy = canvas.image_to_canvas(*self.verify_point)
            half = self.verification_marker_size / 2
            for ax, ay, bx, by in ((cx-half, cy-half, cx+half, cy+half),
                                   (cx-half, cy+half, cx+half, cy-half)):
                canvas.create_line(ax, ay, bx, by, fill=self.verification_marker_color,
                                        width=self.verification_marker_width, tags=("overlay",))
        if canvas is not self.canvas and not self.processing_overlay.get(): return
        for series in self.project.series:
            if not series.visible:
                continue
            for index, point in enumerate(series.points, 1):
                x, y = canvas.image_to_canvas(point.pixel_x, point.pixel_y)
                selected = series.id == self.active_series_id and point.id == self.selected_point_id
                radius = 6 if selected else 4
                width = 3 if selected else 2
                canvas.create_oval(x-radius, y-radius, x+radius, y+radius, outline=series.color, width=width, tags=("overlay",))
                if self.show_numbers.get():
                    canvas.create_text(x+radius+3, y-radius-2, text=str(index), fill=series.color, anchor="sw", tags=("overlay",))

    def on_cursor(self, x, y):
        # Source-integrity warnings must remain visible even while moving the
        # mouse across the image after catalog refresh.
        diagnostic = self.source_diag.get()
        if any(diagnostic.startswith(prefix) for prefix in
               ("STALE SOURCE", "SOURCE MISSING", "SOURCE ERROR", "SESSION CHANGED")):
            self.status.set(diagnostic)
            return
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
            self.selected_label.set("")
            if hasattr(self,"selected_hint"):self.selected_hint.pack_forget()
            return
        lines = [f"Manual click: {point.manual_pixel_x:.3f}, {point.manual_pixel_y:.3f} px", f"Stored pixel: {point.pixel_x:.3f}, {point.pixel_y:.3f} px"]
        if point.calibrated_x is not None:
            lines += [f"X = {fmt(point.calibrated_x)} {self.project.x_axis.unit}", f"Y = {fmt(point.calibrated_y)} {self.project.y_axis.unit}"]
        self.selected_label.set("\n".join(lines))
        if hasattr(self,"selected_hint") and not self.selected_hint.winfo_manager():
            self.selected_hint.pack(before=self.assist_frame,anchor="w",pady=(2,0))

    def mode_changed(self):
        if self.mode.get() != "proposal_edit":
            self._assist_move_target=None
        if self.mode.get() != "verify":
            self.verify_point = None
        self.pending_corner = None
        self.selected_point_id = None
        self.dragging = False
        self.drag_snapshot = None
        self.update_selected(); self.redraw()

    def catalog_watch_changed(self):
        try:
            self._commit_pref_values({"auto_catalog_check": self.auto_catalog_watch.get()})
        except RpcError as exc:
            self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
            messagebox.showerror("GX-TXT Configuration", str(exc), parent=self.root)

    def display_changed(self):
        if self.loading_ui:
            return
        try:
            self._commit_pref_values({
                "show_point_numbers": self.show_numbers.get(),
                "show_scale_overlay": self.show_scale_overlay.get(),
                "show_calibration_corners": self.show_calibration_corners.get()})
        except RpcError as exc:
            self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
            messagebox.showerror("GX-TXT Configuration", str(exc), parent=self.root)

    def snap_changed(self):
        if self.loading_ui:
            return
        try:
            radius = int(self.snap_radius.get())
            self._commit_pref_values({
                "snap_enabled": self.snap_enabled.get(), "snap_radius": radius})
        except (RpcError, ValueError) as exc:
            self._apply_shared_settings(self.shared_settings, self.shared_settings_origin, force=True)
            messagebox.showerror("GX-TXT Configuration", str(exc), parent=self.root)

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

    @staticmethod
    def _core_inline_uncertainty(linearization, spec, measurement_id):
        """Transfer explicit physical Jacobians to the Tcl host without files.

        The host calls public NUMERIC_API_v1. Column-major binary64 matrices
        are compressed for the viewer's existing base64-framed RPC. This is
        serialization only; no uncertainty/covariance is computed here.
        Ordering must agree with the exact published raster rows.
        """
        import zlib
        import numpy as np
        from uncertainty_engine import checked_spec
        spec = checked_spec(spec)
        encode = lambda x: base64.b64encode(str(x).encode('utf-8')).decode('ascii')
        def packed(v):
            v = np.asarray(v, dtype='<f8')
            if v.ndim != 2 or not np.isfinite(v).all():
                raise ValueError('The CORE linearization requires finite 2-D numerical matrices.')
            body = zlib.compress(v.tobytes(order='F'), 6)
            return f"{v.shape[0]}:{v.shape[1]}:{base64.b64encode(body).decode('ascii')}"
        fields = [
            'CORE_LINEARIZATION_V1', measurement_id, spec['mode'],
            encode(spec['rationale']), encode(spec.get('pixel_distribution', '')),
            ','.join(format(x,'.17g') for x in spec.get('pixel_scale', [])),
            ','.join(format(x,'.17g') for x in spec.get('calibration_standard_uncertainty', [])),
            ','.join(format(x,'.17g') for x in spec.get('override_standard_uncertainty', [])),
            packed(linearization['coordinates']),
            packed(linearization['point_jacobian']),
            packed(linearization['calibration_jacobian']),
            encode(';'.join(linearization['coordinate_units'])),
            encode(';'.join(linearization['calibration_ids'])),
            encode(';'.join(linearization['calibration_units'])),
            encode(linearization['mapping']), encode(linearization['jacobian_method']),
            format(linearization['condition_number'],'.17g'),
        ]
        return '\t'.join(fields)

    def publish_dataset(self):
        if not self.require_working_source(): return
        if not self.commit_axes(False): return
        if not self.project.series:
            messagebox.showerror(APP_NAME, "Create at least one curve before publication.", parent=self.root)
            return
        self._sync_active_measurement()
        group = self._measurements()
        selected = self.selected_publication_ids()
        base_id = self.output_dataset_id.get().strip() or slug_id(self.config.get("name", "digitized.curves"))
        try:
            plan = plan_datasets(group["items"], selected, layout=self.publish_layout.get(),
                                 template=self.publish_name_template.get(), name=base_id,
                                 configuration=self.config.get("name", "digitizer"))
        except ValueError as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root); return
        mode = "family" if self.family_enabled.get() else "generic"
        for series in self.project.series:
            if mode == "family":
                try: float(series.parameter_value.strip())
                except ValueError:
                    messagebox.showerror(APP_NAME, f"Curve '{series.name}' requires a numerical family parameter.", parent=self.root)
                    return
                if series.parameter_unit.strip() and series.parameter_unit.strip() != self.family_unit.get().strip():
                    messagebox.showerror(APP_NAME, "Curve family units do not match.", parent=self.root)
                    return
        if self.publish_layout.get() == "combined":
            # One Variable Schema cannot declare different units for different rows.
            specs = [next(m for m in group["items"] if m["id"] == mid)["axes"] for mid in selected]
            for axis in ("x", "y"):
                units = {spec[axis]["unit"] for spec in specs}
                if len(units) != 1:
                    messagebox.showerror(APP_NAME,
                        "Combined publication requires identical physical units for every X axis and every Y axis. Use separate Datasets instead.", parent=self.root)
                    return
        if self.publish_layout.get() == "combined" and len(selected) > 1:
            if not messagebox.askyesno(APP_NAME,
                    "The combined Dataset contains multiple X/Y realizations with a calibration_key column. "
                    "Legacy readers that ignore calibration_key may mix distinct measurements. Continue?",
                    parent=self.root):
                return
        config = self.serialize_configuration()
        saved_decl=config.get('uncertainty') or {'mode':'none'}
        if saved_decl.get('mode','none')!='none' and \
            saved_decl.get('review_fingerprint')!=review_fingerprint(config):
            messagebox.showerror(APP_NAME,
                'The scientific points, calibration or source have changed since the uncertainty declaration. '
                'Open Uncertainty... and apply a new reviewed declaration before publishing.',
                parent=self.root)
            return
        source = config.get("source", {})
        outcomes = []
        self.last_publications = []
        for job in plan:
            try:
                selected_item = next(m for m in group["items"] if m["id"] == job["primary_id"])
                trial_project = copy.deepcopy(self.project)
                trial_project.calibration = Calibration.from_dict(selected_item["calibration"])
                trial_project.x_axis = AxisConfig.from_dict(selected_item["axes"]["x"])
                trial_project.y_axis = AxisConfig.from_dict(selected_item["axes"]["y"])
                if not trial_project.calibration_ready():
                    raise ValueError(f"Calibration '{selected_item['label']}' is incomplete.")
                # The numeric rows are computed against their own calibration,
                # never against the live/active viewer state.
                rows = []
                uncertainty_spec=checked_spec(config.get('uncertainty') or {'mode':'none'},
                    scale_bar=bool(selected_item.get('scale_reference')))
                uncertainty_rows=[]
                local_factors=[]; shared_factors=[]; uncertainty_info=[]
                core_inline=''
                if uncertainty_spec['mode']!='none' and len(job['measurement_ids'])!=1:
                    raise ValueError('Reviewed uncertainty for combined multiple calibrations is not yet scientifically supported. Publish them as separate Datasets or disable uncertainty; shared source-pixel errors cannot be treated as independent calibrations.')
                for mid in job["measurement_ids"]:
                    item = next(m for m in group["items"] if m["id"] == mid)
                    p = copy.deepcopy(trial_project)
                    p.calibration = Calibration.from_dict(item["calibration"])
                    p.x_axis = AxisConfig.from_dict(item["axes"]["x"])
                    p.y_axis = AxisConfig.from_dict(item["axes"]["y"])
                    p.recalculate_all_points()
                    # Different accepted calibrations may change scientific point
                    # coordinates: establish row order on THIS calibration, not
                    # on the active viewer calibration.
                    order_project(p,self._ordering_policy())
                    if uncertainty_spec['mode']!='none':
                        points_for_measurement=[pt for series in p.series for pt in series.points]
                        result_unc=propagate(p,[(pt.pixel_x,pt.pixel_y) for pt in points_for_measurement],
                            uncertainty_spec,scale_bar=bool(item.get('scale_reference')))
                        uncertainty_info.append({'calibration_id':mid,
                            'calibration_label':item['label'],
                            'point_count':len(points_for_measurement),
                            'condition_number':result_unc['condition_number'],
                            'shared_calibration':result_unc['shared_calibration'],
                            'within_point_correlation':result_unc['within_point_correlation']})
                        local_factors.append(result_unc['local_factors'])
                        shared_factors.append(result_unc['shared_factors'])
                        core_inline=self._core_inline_uncertainty(
                            p.calibration_linearization([(pt.pixel_x,pt.pixel_y) for pt in points_for_measurement]),
                            uncertainty_spec,mid)
                        k_unc=0
                    for series in p.series:
                        for point_index, point in enumerate(series.points):
                            if point.calibrated_x is None or point.calibrated_y is None:
                                raise ValueError(f"Point {point_index} of curve '{series.name}' is outside or invalid for calibration '{item['label']}'. Publication was not performed for this Dataset.")
                            values = [b64e(series.id), b64e(series.name), str(point_index),
                                      format(point.calibrated_x, ".17g"), format(point.calibrated_y, ".17g"),
                                      series.parameter_value.strip(), format(point.pixel_x, ".17g"),
                                      format(point.pixel_y, ".17g")]
                            if self.publish_layout.get() == "combined":
                                values += [b64e(mid), b64e(item["label"])]
                            # Stable original point identity is part of the
                            # v2 row protocol even when uncertainty is disabled.
                            values.append(b64e(point.id))
                            rows.append("\t".join(values))
                            if uncertainty_spec['mode']!='none':
                                uncertainty_rows.append([series.id,point.id,mid,
                                    format(point.calibrated_x,'.17g'),format(point.calibrated_y,'.17g'),
                                    format(result_unc['sigma_x'][k_unc],'.17g'),
                                    format(result_unc['sigma_y'][k_unc],'.17g'),
                                    format(result_unc['covariance_xy'][k_unc],'.17g')])
                                k_unc+=1
                if not rows: raise ValueError("There are no calibrated points to publish.")
                publication_config = copy.deepcopy(config)
                publication_config["calibration_measurements"]["active_id"] = job["primary_id"]
                publication_config["scale_reference"] = copy.deepcopy(selected_item.get("scale_reference"))
                manifest = build_manifest(publication_config, trial_project, *self.image.size)
                manifest["publication_calibration_mode"] = self.publish_layout.get()
                manifest["publication_calibration_ids"] = list(job["measurement_ids"])
                metadata = metadata_fields(manifest)
                # Quality schema v2 is derived from the exact publication job,
                # not from a global Session counter. Combined datasets contain
                # one realization per selected calibration; raster clicks are
                # counted once, whereas publication rows count *all* copies.
                # Image evidence uses original canonical source pixels and has
                # no relation to view opacity or preview processing.
                trial_project.recalculate_all_points()
                order_project(trial_project, self._ordering_policy())
                quality = inspect_quality(config, trial_project, self.image.size,
                    measurements=[next(m for m in group["items"] if m["id"] == mid)
                                  for mid in job["measurement_ids"]],
                    publication_layout=self.publish_layout.get(),
                    published_row_count=len(rows), raster_image=self.image,
                    point_ordering=self.point_order_source.get(),
                    monotonicity=self.curve_monotonicity.get())
                metadata["curve_digitizer.point_ordering_source"] = self.point_order_source.get()
                metadata["curve_digitizer.point_monotonicity"] = self.curve_monotonicity.get()
                metadata["curve_digitizer.quality_schema_version"] = "2"
                metadata["curve_digitizer.quality_report_json"] = json.dumps(quality,ensure_ascii=False,separators=(",",":"),allow_nan=False)
                metadata["curve_digitizer.quality_status"] = quality["status"]
                metadata["curve_digitizer.quality_issue_count"] = str(quality["issues"]["total"])
                metadata["curve_digitizer.quality_source_point_count"] = str(quality["publication"]["unique_raster_point_count"])
                metadata["curve_digitizer.quality_published_row_count"] = str(quality["publication"]["published_row_count"])
                metadata["curve_digitizer.quality_curve_count"] = str(quality["publication"]["curve_count"])
                metadata["curve_digitizer.quality_calibration_realizations"] = str(quality["publication"]["calibration_realization_count"])
                metadata["curve_digitizer.quality_segment_count"] = str(quality["publication"]["source_segment_count"])
                metadata["curve_digitizer.quality_evidence_available"] = "1" if quality["image_evidence"]["available"] else "0"
                metadata["curve_digitizer.quality_accuracy_assessed"] = "0"
                metadata["curve_digitizer.publication_calibration_mode"] = self.publish_layout.get()
                metadata["curve_digitizer.publication_calibration_ids"] = json.dumps(job["measurement_ids"], separators=(",", ":"))
                metadata["curve_digitizer.publication_measurement_id"] = job["primary_id"]
                metadata["curve_digitizer.publication_measurement_label"] = selected_item["label"]
                metadata_payload = encode_metadata_records(metadata)
                uncertainty_payload=''
                if uncertainty_rows:
                    if len(uncertainty_rows)>4096:
                        raise ValueError('Uncertainty publication is limited to 4096 original rows per Dataset; select fewer calibrations or curves.')
                    if len(uncertainty_rows)!=len(rows):
                        raise ValueError('Uncertainty and scientific row counts differ.')
                    factors=compact_factors(local_factors,shared_factors)
                    report={'schema':'gxtxt.curve_digitizer.uncertainty.v2','mode':uncertainty_spec['mode'],
                        'declaration':uncertainty_spec,'row_count':len(rows),
                        'calibrations':uncertainty_info,
                        'units':[trial_project.x_axis.unit or '1',trial_project.y_axis.unit or '1'],
                        'shared_calibration':any(i['shared_calibration'] for i in uncertainty_info),
                        'within_point_correlation':any(i['within_point_correlation'] for i in uncertainty_info),
                        'interpretation':'First-order propagated physical standard uncertainties from an explicitly declared error model. Not a measured accuracy or universal quality score.',
                        'covariance_interpretation':'Correlated calibration requires full covariance for qualified GLS; diagonal sigma alone is insufficient.'}
                    header=[b64e(json.dumps(report,ensure_ascii=False,separators=(',',':'),allow_nan=False)),
                            b64e(json.dumps(factors,separators=(',',':')))]
                    uncertainty_payload='\n'.join(header+['\t'.join([
                        b64e(cell) if index in (0,1,2) else cell
                        for index,cell in enumerate(rec)]) for rec in uncertainty_rows])
                display = self.output_display_name.get().strip() or config.get("name", base_id)
                if self.publish_layout.get() == "separate": display += " — " + selected_item["label"]
                else: display += " — combined calibrations"
                result = self.rpc.call("PUBLISH", self.session_token, self.current_doc_id,
                    job["dataset_id"], display, mode,
                    trial_project.x_axis.name, trial_project.x_axis.unit, self.x_role.get().strip() or "independent",
                    trial_project.y_axis.name, trial_project.y_axis.unit, self.y_role.get().strip() or "measured",
                    self.family_label.get().strip() or "Family parameter", self.family_unit.get().strip(),
                    self.family_role.get().strip() or "family", source.get("dataset_id", ""),
                    source.get("sha256", ""),
                    "full_image_scale_bar" if selected_item.get("scale_reference") else
                    "full_image_pixels" if trial_project.is_full_image_calibration(*self.image.size) else
                    "four_point_homography", trial_project.x_axis.scale, trial_project.y_axis.scale,
                    config.get("name", "Curve Digitalizer configuration"), "\n".join(rows), metadata_payload,
                    self.publish_layout.get(), config.get("notes", ""),uncertainty_payload,core_inline)
                parts = result.split("\t", 4)
                if len(parts) not in (4, 5):
                    raise ValueError("Invalid publication receipt from GX-TXT.")
                dataset, path, sha, contract = parts[:4]
                outcomes.append(dataset)
                if len(parts) == 5 and parts[4].startswith("failed:"):
                    messagebox.showwarning(APP_NAME,
                        f"Dataset '{dataset}' was published, but its Markdown notes could not be saved:\n{parts[4][7:]}", parent=self.root)
                self.last_publications.append({"dataset_id": dataset, "path": path,
                                               "sha256": sha, "contract": contract})
            except (RpcError, ValueError, KeyError, TypeError, CalibrationError) as exc:
                self.publish_result.set("Published: " + (", ".join(outcomes) if outcomes else "none") + "\nFailed: " + job["dataset_id"])
                messagebox.showerror(APP_NAME, f"Publication failed for {job['dataset_id']}:\n{exc}\n\nCompleted: {', '.join(outcomes) or 'none'}. Subsequent outputs were not attempted.", parent=self.root)
                return
        self.publish_result.set(f"Published {len(outcomes)} Dataset(s):\n" + "\n".join(outcomes))
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
        self._sync_active_measurement()
        self.measurement_selected_id = self._measurements()["active_id"]
        self.accept_measurement()
        self.refresh_publish_measurements()
        self.persist(); self.refresh_curve_tree(); self.publish_dataset()
        if "Published" not in self.publish_result.get():
            raise RuntimeError("Generic publication did not complete")
        first_record = self.last_publications[0]
        first_path, first_sha = first_record["path"], first_record["sha256"]

        # Edit one point and republish. Dataset identity/target must remain stable
        # while the numerical artifact and its hash change.
        point = self.project.series[0].points[0]
        point.pixel_x += 3.0
        point.manual_pixel_x += 3.0
        self.project.update_point_calibration(point)
        self.persist(); self.publish_dataset()
        second_record = self.last_publications[0]
        second_path, second_sha = second_record["path"], second_record["sha256"]
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
        if not getattr(self, "last_publications", None) or self.last_publications[0]["contract"] != "curve_family.table":
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
