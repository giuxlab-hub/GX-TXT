# SPDX-License-Identifier: GPL-3.0-or-later
"""Expandable in-page calibration verification; no independent Tk window.

Scientific values and residuals are evaluated by calibration_verification.py.
This class only renders transient references and readouts.
"""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from calibration_verification import AxisVerification, display_number


class CalibrationVerificationPanel:
    """Full-width inline panel inside the scrollable Calibration tab."""

    def __init__(self, master: ttk.Frame, references: dict[str, tk.StringVar],
                 *, on_close, on_clear):
        self.window = ttk.Frame(master, padding=(2, 4, 2, 3))
        self.window.pack(fill="x", expand=False)
        self.references = references
        self.signature = ()
        self.controls = {}
        self.point_text = tk.StringVar(master=self.window,
                                       value="Click a known point on the image.")
        ttk.Label(self.window, textvariable=self.point_text,
                  font=("TkDefaultFont", 9, "bold"),
                  justify="left", wraplength=570).pack(fill="x", pady=(0, 5))
        self.table = ttk.Frame(self.window)
        self.table.pack(fill="x")
        self.errors = tk.StringVar(master=self.window, value="")
        ttk.Label(self.window, textvariable=self.errors,
                  foreground="#a52a2a", wraplength=570,
                  justify="left").pack(fill="x", pady=(4, 0))
        actions = ttk.Frame(self.window)
        actions.pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="Close verification",
                   command=on_close).pack(side="right")
        ttk.Button(actions, text="Clear expected values",
                   command=on_clear).pack(side="right", padx=(0, 6))

    def sync_axes(self, axes: list[tuple[str, object]]):
        """Rebuild only when axis names, units, scales or Y2 availability change."""
        signature = tuple((code, axis.name, axis.unit, axis.scale)
                          for code, axis in axes)
        if self.signature == signature:
            return
        self.signature = signature
        for child in self.table.winfo_children():
            child.destroy()
        self.controls = {}
        for index, (code, axis) in enumerate(axes):
            axis_code = code.upper() if len(axes) == 3 or code != "y1" else "Y"
            unit = axis.unit or "1"
            scale = "log" if axis.scale == "log" else "linear"
            block = ttk.LabelFrame(self.table,
                                   text=f"{axis_code} · {axis.name}   [{unit}, {scale}]",
                                   padding=(5, 3, 5, 5))
            block.pack(fill="x", pady=(0, 3))
            upper = ttk.Frame(block)
            upper.pack(fill="x")
            ttk.Label(upper, text="Expected").pack(side="left")
            field = ttk.Entry(upper, textvariable=self.references[code], width=19)
            field.pack(side="left", padx=(5, 0))
            ttk.Label(upper, text=f"{unit} · enter physical value",
                      foreground="#555555").pack(side="left", padx=(8, 0))
            lower = ttk.Frame(block)
            lower.pack(fill="x", pady=(4, 0))
            for col, weight in enumerate((2, 2, 3)):
                lower.columnconfigure(col, weight=weight, uniform="results")
            row_fields = {"field": field}
            labels = (
                ("calculated", "Calculated"),
                ("delta", "Δ physical"),
                ("comparison", "Relative / log"),
            )
            for col, (key, label) in enumerate(labels):
                cell = ttk.Frame(lower)
                cell.grid(row=0, column=col, sticky="ew", padx=(0, 4))
                ttk.Label(cell, text=label, foreground="#555555").pack(anchor="w")
                value = tk.StringVar(master=self.window, value="—")
                ttk.Label(cell, textvariable=value, anchor="w",
                          justify="left", wraplength=195).pack(fill="x")
                row_fields[key] = value
            self.controls[code] = row_fields
        self.show_no_point()

    def show_no_point(self):
        self.point_text.set("Click a known point on the source image.")
        self.errors.set("")
        for state in self.controls.values():
            for key in ("calculated", "delta", "comparison"):
                state[key].set("—")

    def show_result(self, caption: str, pixel_x: float, pixel_y: float,
                    readings: list[AxisVerification]):
        self.point_text.set(
            f"{caption}  ·  pixel ({display_number(pixel_x)}, "
            f"{display_number(pixel_y)})")
        errors = []
        for reading in readings:
            widgets = self.controls.get(reading.axis_id)
            if widgets is None:
                continue
            widgets["calculated"].set(
                f"{reading.measured_display} {reading.unit}")
            widgets["delta"].set(
                f"{reading.delta_display} {reading.unit}"
                if reading.delta is not None else "—")
            if reading.error:
                widgets["comparison"].set("Invalid reference")
                errors.append(f"{reading.axis_id.upper()}: {reading.error}")
            elif reading.comparison_kind == "decades" and reading.comparison is not None:
                deviation = 0.0 if reading.is_numerically_zero else reading.comparison
                ratio = (f"×{display_number(10.0 ** deviation)}"
                         if abs(deviation) < 15
                         else f"×10^{display_number(deviation)}")
                widgets["comparison"].set(
                    f"{display_number(deviation, signed=True)} decades ({ratio})")
            else:
                widgets["comparison"].set(reading.comparison_display)
        self.errors.set(" | ".join(errors))

    def lift(self):
        # An inline panel is not raised as a separate window.
        if self.window.winfo_exists():
            self.controls.get("x", {}).get("field", self.window).focus_set()

    def destroy(self):
        if self.window.winfo_exists():
            self.window.destroy()
