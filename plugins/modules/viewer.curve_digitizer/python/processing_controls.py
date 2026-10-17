"""Tk filter controls for non-geometric ImageMagick processing.

The scientific source and the ordered operation list remain the authorities.
This is only a GUI projection over the same validated image_processing pipeline.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import tkinter as tk
from tkinter import ttk
from image_processing import DEFAULT_PARAMETERS, normalize_operations, ProcessingError

# Sensible default only: processing operations are not generally commutative.
STANDARD_ORDER = (
    "channel", "grayscale", "median", "auto_level", "contrast_stretch",
    "brightness_contrast", "gamma", "clahe", "sharpen", "negate", "threshold",
)
LABELS = {
    "channel": "Color channel", "grayscale": "Grayscale", "median": "Median denoise",
    "auto_level": "Auto levels", "contrast_stretch": "Contrast stretch",
    "brightness_contrast": "Brightness / contrast", "gamma": "Gamma",
    "clahe": "Local contrast (CLAHE)", "sharpen": "Sharpen",
    "negate": "Invert colors", "threshold": "Threshold",
}


def merge_filter_operations(operations, kind, enabled, value, *, advanced=False):
    """Change a filter without losing other steps or the advanced order."""
    if kind not in STANDARD_ORDER:
        raise ProcessingError(f"Unknown filter {kind}.")
    updated = [dict(op) for op in operations]
    matching = [i for i, op in enumerate(updated) if op["kind"] == kind]
    if enabled:
        normalized = normalize_operations([{"kind": kind, "value": value}])[0]
        if matching:
            updated[matching[0]] = normalized
        else:
            updated.append(normalized)
        # Color-channel extraction and grayscale are mutually exclusive
        # in the simple editing mode, since their original colors differ.
        if not advanced and kind in {"channel", "grayscale"}:
            other = "grayscale" if kind == "channel" else "channel"
            updated = [op for op in updated if op["kind"] != other]
    else:
        updated = [op for op in updated if op["kind"] != kind]
    if not advanced:
        updated.sort(key=lambda op: STANDARD_ORDER.index(op["kind"]))
    return normalize_operations(updated)


class FilterControls(ttk.Frame):
    """Eleven always-visible checkbox controls with native sliders/combos."""
    def __init__(self, parent, changed):
        super().__init__(parent)
        self.changed = changed
        self._loading = True
        self.enabled = {}
        self.value_vars = {}
        self.label_vars = {}
        self.widgets = {}
        for kind in STANDARD_ORDER:
            self._add_row(kind)
        self._loading = False
        for kind in STANDARD_ORDER: self._refresh_widget_state(kind)

    def _add_row(self, kind):
        box = ttk.Frame(self)
        box.pack(fill="x", pady=2)
        header = ttk.Frame(box)
        header.pack(fill="x")
        self.enabled[kind] = tk.BooleanVar(self, value=False)
        self.widgets[kind] = []
        ttk.Checkbutton(header, variable=self.enabled[kind], command=lambda k=kind: self._emit(k, force=True)).pack(side="left")
        ttk.Label(header, text=LABELS[kind], font=("TkDefaultFont", 9, "bold")).pack(side="left", padx=(3, 6))
        info = tk.StringVar(self, value="")
        self.label_vars[kind] = info
        ttk.Label(header, textvariable=info, foreground="#385b77").pack(side="right", padx=2)
        control = ttk.Frame(box)
        control.pack(fill="x", padx=(26, 8))
        if kind in {"grayscale", "auto_level", "negate"}:
            ttk.Label(control, text="On / off", foreground="#777777").pack(anchor="w")
            self.value_vars[kind] = {}
        elif kind == "channel":
            v = tk.StringVar(self, value="Red")
            combo = ttk.Combobox(control, textvariable=v, state="readonly", width=15,
                         values=("Red", "Green", "Blue", "Luminance"))
            combo.pack(side="left")
            self.widgets[kind].append(combo)
            self.value_vars[kind] = {"channel": v}
            v.trace_add("write", lambda *_args, k=kind: self._emit(k))
        elif kind == "clahe":
            self.value_vars[kind] = {}
            for name, options, initial in (("grid",("2x2","4x4","8x8","16x16","32x32"),"8x8"),
                                           ("bins",("64","128","256"),"128")):
                ttk.Label(control, text=name.capitalize()).pack(side="left", padx=(0,3))
                v=tk.StringVar(self,value=initial)
                combo = ttk.Combobox(control, textvariable=v, state="readonly", values=options,
                             width=7)
                combo.pack(side="left", padx=(0, 7))
                self.widgets[kind].append(combo)
                self.value_vars[kind][name]=v
                v.trace_add("write", lambda *_args,k=kind:self._emit(k))
            self._slider(control,kind,"clip",1,5,3,step=1,title="Clip")
        elif kind == "brightness_contrast":
            self.value_vars[kind] = {}
            self._slider(control,kind,"brightness",-100,100,0,step=1,title="Brightness")
            self._slider(control,kind,"contrast",-100,100,20,step=1,title="Contrast")
        else:
            self.value_vars[kind] = {}
            limits={"gamma":(.05,4,1,.05),"contrast_stretch":(0,20,1,.1),
                    "threshold":(0,100,50,1),"median":(1,10,1,1),
                    "sharpen":(.1,4.9,1,.1)}
            low,high,initial,step=limits[kind]
            self._slider(control,kind,"value",low,high,initial,step=step)
        ttk.Separator(self,orient="horizontal").pack(fill="x",pady=(3,1))

    def _slider(self, parent, kind, name, minimum, maximum, initial, *, step, title=None):
        group=ttk.Frame(parent)
        group.pack(fill="x", expand=True)
        if title: ttk.Label(group,text=title,width=10).pack(side="left")
        v=tk.DoubleVar(self,value=initial)
        self.value_vars[kind][name]=v
        slider=ttk.Scale(group,from_=minimum,to=maximum,variable=v)
        slider.pack(side="left",fill="x",expand=True)
        self.widgets[kind].append(slider)
        number=ttk.Spinbox(group,from_=minimum,to=maximum,increment=step,textvariable=v,width=6)
        number.pack(side="right",padx=(6,1))
        self.widgets[kind].append(number)
        v.trace_add("write", lambda *_args,k=kind:self._emit(k))

    def _operation_value(self, kind):
        p=self.value_vars[kind]
        if kind in {"grayscale","auto_level","negate"}:return ""
        if kind=="channel":return p["channel"].get()
        if kind=="clahe":return f"{p['grid'].get()}+{p['bins'].get()}+{int(round(p['clip'].get()))}"
        def n(name):
            v=p[name].get()
            if kind in ("median","threshold") or name in ("brightness","contrast"):
                return str(int(round(v)))
            return format(float(v),".3g")
        if kind=="brightness_contrast":return f"{n('brightness')},{n('contrast')}"
        if kind=="sharpen":return "0x"+format(round(p["value"].get(),1),".1f")
        return n("value")

    def _refresh_widget_state(self, kind):
        active = self.enabled[kind].get()
        for widget in self.widgets[kind]:
            # ttk widgets retain combobox readonly state on reactivation.
            widget.configure(state=("readonly" if active and isinstance(widget, ttk.Combobox)
                                    else "normal" if active else "disabled"))

    def _emit(self,kind,force=False):
        if self._loading:return
        self._refresh_widget_state(kind)
        if not self.enabled[kind].get() and not force:return
        try:
            enabled=self.enabled[kind].get()
            value=self._operation_value(kind)
            self.label_vars[kind].set(value if enabled else "")
        except (ValueError,tk.TclError):
            return
        self.changed(kind,enabled,value)

    def load_operations(self, operations):
        self._loading=True
        try:
            selected={op["kind"]:op["value"] for op in operations}
            for kind in STANDARD_ORDER:
                v=selected.get(kind)
                self.enabled[kind].set(v is not None)
                if v is None:v=DEFAULT_PARAMETERS[kind]
                p=self.value_vars[kind]
                try:
                    if kind=="channel":p["channel"].set(v)
                    elif kind=="clahe":
                        grid,bins,clip=v.split("+")
                        p["grid"].set(grid);p["bins"].set(bins);p["clip"].set(int(clip))
                    elif kind=="brightness_contrast":
                        a,b=v.split(",")
                        p["brightness"].set(float(a));p["contrast"].set(float(b))
                    elif kind=="sharpen":p["value"].set(float(v.split("x",1)[1]))
                    elif "value" in p:p["value"].set(float(v))
                    self.label_vars[kind].set(v if kind in selected else "")
                except (ValueError,tk.TclError):pass
                self._refresh_widget_state(kind)
        finally:self._loading=False
