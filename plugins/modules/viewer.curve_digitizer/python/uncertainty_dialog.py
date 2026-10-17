# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit uncertainty declaration and review through the host's public owners."""
import copy
import math
import tkinter as tk
from tkinter import ttk, messagebox


class UncertaintyDialog(tk.Toplevel):
    def __init__(self, app):
        super().__init__(app.root)
        self.app = app
        self.title("Pixel and calibration uncertainty")
        self.transient(app.root)
        spec = app.config.get("uncertainty", {"mode": "none"})
        self.variables = {}
        fields = [
            ("mode", "Error model", spec.get("mode", "none"), ("none", "pixel_calibration", "physical_override")),
            ("pixel_distribution", "Pixel scale meaning", spec.get("pixel_distribution", "rectangular_full_width"), ("rectangular_full_width", "normal_standard_uncertainty")),
            ("pixel_scale", "Pixel X/Y full widths or standard uncertainties", spec.get("pixel_scale", [1, 1]), None),
            ("calibration_standard_uncertainty", "Corner and axis-endpoint standard uncertainties", spec.get("calibration_standard_uncertainty", [0] * 12), None),
            ("override_standard_uncertainty", f"Independent physical X/Y sigma ({app.project.x_axis.unit or '1'}, {app.project.y_axis.unit or '1'})", spec.get("override_standard_uncertainty", [1, 1]), None),
            ("rationale", "Evidence / reason for this declaration", spec.get("rationale", ""), None),
        ]
        for row, (key, label, value, choices) in enumerate(fields):
            variable = tk.StringVar(value=" ".join(map(str, value)) if isinstance(value, list) else value)
            self.variables[key] = variable
            ttk.Label(self, text=label).grid(row=row, column=0, sticky="w", padx=8, pady=4)
            widget = ttk.Combobox(self, textvariable=variable, values=choices, state="readonly") if choices else ttk.Entry(self, textvariable=variable, width=58)
            widget.grid(row=row, column=1, sticky="ew", padx=8, pady=4)
        ttk.Label(self, wraplength=760, text="Calibration order: bottom-left X/Y, bottom-right X/Y, top-left X/Y, top-right X/Y (pixels), then X minimum/maximum and Y minimum/maximum (axis units). Zero holds a calibration input fixed. A physical override replaces the pixel/calibration error model. Pixel size alone is not a measured standard uncertainty.").grid(row=6, column=0, columnspan=2, padx=8, pady=8)
        ttk.Button(self, text="Save declaration and review", command=self.apply).grid(row=7, column=0, columnspan=2, pady=6)
        self.report = tk.Text(self, width=100, height=18, wrap="word", state="disabled")
        self.report.grid(row=8, column=0, columnspan=2, sticky="nsew", padx=8, pady=8)
        ttk.Button(self, text="Close", command=self.destroy).grid(row=9, column=0, columnspan=2, pady=6)
        actions = ttk.Frame(self)
        actions.grid(row=10, column=0, columnspan=2, pady=6)
        for axis in ("x", "y"):
            ttk.Button(actions, text=f"Publish {axis.upper()} covariance from published Dataset", command=lambda a=axis: self.publish_covariance(a)).pack(side="left", padx=5)
        self.columnconfigure(1, weight=1)
        self.rowconfigure(8, weight=1)

    def declaration(self):
        values = {key: variable.get().strip() for key, variable in self.variables.items()}
        mode = values["mode"]
        if mode == "none":
            return {"mode": "none"}
        if not values["rationale"] or len(values["rationale"]) > 2048:
            raise ValueError("Provide a reason or calibration evidence (up to 2048 characters).")
        spec = dict(mode=mode, rationale=values["rationale"])
        fields = [("override_standard_uncertainty", 2)] if mode == "physical_override" else [("pixel_scale", 2), ("calibration_standard_uncertainty", 12)]
        for key, count in fields:
            numbers = [float(x) for x in values[key].replace(",", " ").split()]
            if len(numbers) != count or any(not math.isfinite(x) or x < 0 or (key != "calibration_standard_uncertainty" and x == 0) for x in numbers):
                raise ValueError(f"{key}: supply {count} finite {'nonnegative' if key == 'calibration_standard_uncertainty' else 'positive'} values.")
            spec[key] = numbers
        if mode == "pixel_calibration":
            spec["pixel_distribution"] = values["pixel_distribution"]
        return spec

    def publish_covariance(self, axis):
        try:
            dataset = self.app.output_dataset_id.get().strip()
            result = self.app.rpc.call("PUBLISH_COVARIANCE", dataset, dataset + ".covariance_" + axis, axis)
            self.report.configure(state="normal")
            self.report.insert("end", "\n\n" + result)
            self.report.configure(state="disabled")
        except Exception as exc:
            messagebox.showerror("Covariance publication", str(exc), parent=self)

    def apply(self):
        try:
            spec = self.declaration()
            if not self.app.commit_axes(False):
                return
            self.app.snapshot()
            self.app.config["uncertainty"] = copy.deepcopy(spec)
            if not self.app.persist():
                return
            report = "Uncertainty publication is disabled." if spec["mode"] == "none" else self.app.rpc.call("UNCERTAINTY_REVIEW", self.app.current_doc_id, self.app.document_sha[self.app.current_doc_id])
            self.report.configure(state="normal")
            self.report.delete("1.0", "end")
            self.report.insert("1.0", report)
            self.report.configure(state="disabled")
        except Exception as exc:
            messagebox.showerror("Uncertainty review", str(exc), parent=self)
