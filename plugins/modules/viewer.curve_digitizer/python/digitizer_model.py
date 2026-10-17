# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
import math
import uuid
import numpy as np

CORNER_ORDER = ("bottom_left", "bottom_right", "top_left", "top_right")
CORNER_DESTINATIONS = {
    "bottom_left": (0.0, 0.0),
    "bottom_right": (1.0, 0.0),
    "top_left": (0.0, 1.0),
    "top_right": (1.0, 1.0),
}


class CalibrationError(ValueError):
    pass


@dataclass
class AxisConfig:
    name: str = "X"
    unit: str = ""
    minimum: float = 0.0
    maximum: float = 1.0
    scale: str = "linear"

    def validate(self) -> None:
        if self.scale not in ("linear", "log"):
            raise CalibrationError(f"Invalid scale type: {self.scale!r}")
        if not math.isfinite(self.minimum) or not math.isfinite(self.maximum):
            raise CalibrationError("Axis limits must be finite.")
        if self.minimum == self.maximum:
            raise CalibrationError("Axis minimum and maximum must be different.")
        if self.scale == "log" and (self.minimum <= 0 or self.maximum <= 0):
            raise CalibrationError("Logarithmic axes require positive limits.")

    def from_unit(self, t: float) -> float:
        self.validate()
        if self.scale == "linear":
            return self.minimum + t * (self.maximum - self.minimum)
        lo = math.log10(self.minimum)
        hi = math.log10(self.maximum)
        return 10.0 ** (lo + t * (hi - lo))

    def to_unit(self, value: float) -> float:
        self.validate()
        if self.scale == "linear":
            return (value - self.minimum) / (self.maximum - self.minimum)
        if value <= 0:
            raise CalibrationError("Logarithmic axis values must be positive.")
        lo = math.log10(self.minimum)
        hi = math.log10(self.maximum)
        return (math.log10(value) - lo) / (hi - lo)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "unit": self.unit,
            "minimum": self.minimum,
            "maximum": self.maximum,
            "scale": self.scale,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "AxisConfig":
        return cls(
            name=str(data.get("name", "X")),
            unit=str(data.get("unit", "")),
            minimum=float(data.get("minimum", 0.0)),
            maximum=float(data.get("maximum", 1.0)),
            scale=str(data.get("scale", "linear")),
        )


@dataclass
class Calibration:
    """Four point projective calibration (homography)."""
    pixels: dict[str, tuple[float, float]] = field(default_factory=dict)

    def is_complete(self) -> bool:
        return all(key in self.pixels for key in CORNER_ORDER)

    def clear(self) -> None:
        self.pixels.clear()

    def set_corner(self, name: str, pixel_x: float, pixel_y: float) -> None:
        if name not in CORNER_ORDER:
            raise CalibrationError(f"Unknown calibration corner: {name}")
        self.pixels[name] = (float(pixel_x), float(pixel_y))

    def matrix(self) -> tuple[np.ndarray, float]:
        if not self.is_complete():
            raise CalibrationError("All four calibration points are required.")
        src = np.asarray([self.pixels[n] for n in CORNER_ORDER], dtype=float)
        dst = np.asarray([CORNER_DESTINATIONS[n] for n in CORNER_ORDER], dtype=float)
        rows, rhs = [], []
        # h33 is fixed to 1. Eight correspondences equations solve the eight
        # remaining coefficients of the homography.
        for (x, y), (u, v) in zip(src, dst):
            rows.append([x, y, 1, 0, 0, 0, -u*x, -u*y]); rhs.append(u)
            rows.append([0, 0, 0, x, y, 1, -v*x, -v*y]); rhs.append(v)
        a = np.asarray(rows, dtype=float)
        b = np.asarray(rhs, dtype=float)
        if np.linalg.matrix_rank(a) < 8:
            raise CalibrationError("Degenerate calibration points.")
        cond = float(np.linalg.cond(a))
        try:
            h = np.linalg.solve(a, b)
        except np.linalg.LinAlgError as exc:
            raise CalibrationError("Unable to calculate homography.") from exc
        H = np.asarray([
            [h[0], h[1], h[2]],
            [h[3], h[4], h[5]],
            [h[6], h[7], 1.0],
        ], dtype=float)
        return H, cond

    @staticmethod
    def transform_with_matrix(H: np.ndarray, pixel_x: float, pixel_y: float) -> tuple[float, float]:
        p = H @ np.asarray([pixel_x, pixel_y, 1.0], dtype=float)
        if abs(p[2]) < 1e-15:
            raise CalibrationError("Projective transform is singular here.")
        return float(p[0] / p[2]), float(p[1] / p[2])

    def pixel_to_unit(self, pixel_x: float, pixel_y: float) -> tuple[float, float]:
        H, _ = self.matrix()
        return self.transform_with_matrix(H, pixel_x, pixel_y)

    def corner_derivatives(self, H: np.ndarray) -> np.ndarray:
        """Differentiate A*h=b at the existing calibration (dev097 method).

        The columns are corner x,y in CORNER_ORDER. We differentiate rather
        than solving a second calibration with a different pixel convention.
        """
        src = np.asarray([self.pixels[n] for n in CORNER_ORDER],dtype=float)
        dst = np.asarray([CORNER_DESTINATIONS[n] for n in CORNER_ORDER],dtype=float)
        rows = []
        for (x,y),(u,v) in zip(src,dst):
            rows.append([x,y,1,0,0,0,-u*x,-u*y])
            rows.append([0,0,0,x,y,1,-v*x,-v*y])
        A=np.asarray(rows,dtype=float)
        rhs=np.zeros((8,8),dtype=float)
        for i, name in enumerate(CORNER_ORDER):
            u,v=CORNER_DESTINATIONS[name]
            rhs[2*i,2*i:2*i+2] = -(H[0,:2]-u*H[2,:2])
            rhs[2*i+1,2*i:2*i+2] = -(H[1,:2]-v*H[2,:2])
        return np.linalg.solve(A,rhs)

    def reprojection_rms(self) -> float:
        H, _ = self.matrix()
        errors = []
        for name in CORNER_ORDER:
            x, y = self.pixels[name]
            eu, ev = CORNER_DESTINATIONS[name]
            u, v = self.transform_with_matrix(H, x, y)
            errors.append((u-eu)**2 + (v-ev)**2)
        return math.sqrt(sum(errors) / len(errors))

    def to_dict(self) -> dict[str, Any]:
        return {"points": {n: {"pixel_x": p[0], "pixel_y": p[1]} for n, p in self.pixels.items()}}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Calibration":
        c = cls()
        for name, p in data.get("points", {}).items():
            if name in CORNER_ORDER:
                c.set_corner(name, float(p["pixel_x"]), float(p["pixel_y"]))
        return c


@dataclass
class DigitizedPoint:
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    manual_pixel_x: float = 0.0
    manual_pixel_y: float = 0.0
    pixel_x: float = 0.0
    pixel_y: float = 0.0
    calibrated_x: float | None = None
    calibrated_y: float | None = None
    origin: str = "manual"  # provenance of the original point selection

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "origin": self.origin,
            "manual_click_pixel": {"x": self.manual_pixel_x, "y": self.manual_pixel_y},
            "pixel": {"x": self.pixel_x, "y": self.pixel_y},
            "calibrated": {"x": self.calibrated_x, "y": self.calibrated_y},
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "DigitizedPoint":
        pixel = data.get("pixel", {})
        manual = data.get("manual_click_pixel", pixel)
        calibrated = data.get("calibrated", {})
        return cls(
            id=str(data.get("id", str(uuid.uuid4()))),
            origin=str(data.get("origin", "manual")),
            manual_pixel_x=float(manual.get("x", pixel.get("x", 0.0))),
            manual_pixel_y=float(manual.get("y", pixel.get("y", 0.0))),
            pixel_x=float(pixel.get("x", 0.0)),
            pixel_y=float(pixel.get("y", 0.0)),
            calibrated_x=None if calibrated.get("x") is None else float(calibrated["x"]),
            calibrated_y=None if calibrated.get("y") is None else float(calibrated["y"]),
        )


@dataclass
class Series:
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    name: str = "Series"
    parameter_name: str = "Parameter"
    parameter_value: str = ""
    parameter_unit: str = ""
    visible: bool = True
    color: str = "#d62728"
    points: list[DigitizedPoint] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "parameter": {"name": self.parameter_name, "value": self.parameter_value, "unit": self.parameter_unit},
            "visible": self.visible,
            "color": self.color,
            "points": [p.to_dict() for p in self.points],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Series":
        p = data.get("parameter", {})
        return cls(
            id=str(data.get("id", str(uuid.uuid4()))),
            name=str(data.get("name", "Series")),
            parameter_name=str(p.get("name", "Parameter")),
            parameter_value=str(p.get("value", "")),
            parameter_unit=str(p.get("unit", "")),
            visible=bool(data.get("visible", True)),
            color=str(data.get("color", "#d62728")),
            points=[DigitizedPoint.from_dict(x) for x in data.get("points", [])],
        )


@dataclass
class Project:
    format_version: str = "1.0"
    image_path: str = ""
    image_width: int = 0
    image_height: int = 0
    x_axis: AxisConfig = field(default_factory=lambda: AxisConfig(name="X"))
    y_axis: AxisConfig = field(default_factory=lambda: AxisConfig(name="Y"))
    calibration: Calibration = field(default_factory=Calibration)
    series: list[Series] = field(default_factory=list)
    notes: str = ""
    show_point_numbers: bool = False
    snap_enabled: bool = False
    snap_radius: int = 3

    def auto_calibrate_full_image(self, width: int, height: int, *, y_down: bool = False) -> None:
        """Calibrate every image pixel using the same four-corner homography.

        Pixel centres run from (0, 0) to (width - 1, height - 1).
        With y_down=False, increasing Y goes towards the top of the image,
        as in a Cartesian plot. With y_down=True, calibrated coordinates
        follow the native top-left-origin image pixel convention.
        """
        width, height = int(width), int(height)
        if width < 2 or height < 2:
            raise CalibrationError("Full-image calibration requires an image at least 2 x 2 pixels.")
        self.image_width, self.image_height = width, height
        self.x_axis.minimum, self.x_axis.maximum = 0.0, float(width - 1)
        self.x_axis.unit, self.x_axis.scale = "px", "linear"
        self.y_axis.minimum = float(height - 1) if y_down else 0.0
        self.y_axis.maximum = 0.0 if y_down else float(height - 1)
        self.y_axis.unit, self.y_axis.scale = "px", "linear"
        self.calibration.clear()
        for name, (x, y) in {
            "bottom_left": (0, height - 1),
            "bottom_right": (width - 1, height - 1),
            "top_left": (0, 0),
            "top_right": (width - 1, 0),
        }.items():
            self.calibration.set_corner(name, float(x), float(y))
        if not self.calibration_ready():
            raise CalibrationError("Unable to calibrate the complete image.")
        self.recalculate_all_points()

    def is_full_image_calibration(self, width: int, height: int) -> bool:
        """Reject conversion of a manually perspective-calibrated graph."""
        if not self.calibration.is_complete() or width < 2 or height < 2:
            return False
        corners = {
            "bottom_left": (0, height - 1),
            "bottom_right": (width - 1, height - 1),
            "top_left": (0, 0),
            "top_right": (width - 1, 0),
        }
        return all(math.dist(self.calibration.pixels[name], pos) < 1e-5
                   for name, pos in corners.items())

    def scale_full_image(self, width: int, height: int, pixel_length: float,
                         real_length: float, unit: str) -> float:
        """Uniform pixel-to-physical scaling using the full-frame calibration.

        Pixel origin remains (left, bottom) for Cartesian Y and (left, top)
        for image-oriented Y. Uses pixel-centre distances (W-1, H-1).
        """
        if not self.is_full_image_calibration(width, height):
            raise CalibrationError("First use Auto-calibrate full image; manual projective calibration is not suitable for uniform image scaling.")
        if not all(math.isfinite(float(v)) and float(v) > 0 for v in (pixel_length, real_length)):
            raise CalibrationError("Scale bar length and real-world length must be finite and positive.")
        if pixel_length < 3:
            raise CalibrationError("The scale bar must span at least three source pixels.")
        unit = unit.strip()
        if not unit or unit.lower() in ("px", "pixel", "pixels"):
            raise CalibrationError("Choose a physical length unit, not pixels.")
        if self.x_axis.scale != "linear" or self.y_axis.scale != "linear":
            raise CalibrationError("Image scale calibration requires linear axes.")
        factor = float(real_length) / float(pixel_length)
        if not math.isfinite((width-1)*factor) or not math.isfinite((height-1)*factor):
            raise CalibrationError("The resulting physical dimensions are not finite.")
        y_down = self.y_axis.minimum > self.y_axis.maximum
        self.x_axis.minimum, self.x_axis.maximum = 0.0, (width-1)*factor
        self.y_axis.minimum = (height-1)*factor if y_down else 0.0
        self.y_axis.maximum = 0.0 if y_down else (height-1)*factor
        self.x_axis.unit = self.y_axis.unit = unit
        self.recalculate_all_points()
        return factor

    def calibration_ready(self) -> bool:
        if not self.calibration.is_complete():
            return False
        try:
            self.x_axis.validate(); self.y_axis.validate(); self.calibration.matrix()
        except CalibrationError:
            return False
        return True

    def pixel_to_calibrated(self, pixel_x: float, pixel_y: float) -> tuple[float, float]:
        u, v = self.calibration.pixel_to_unit(pixel_x, pixel_y)
        return self.x_axis.from_unit(u), self.y_axis.from_unit(v)

    def calibration_linearization(self, pixels: Any) -> dict[str, Any]:
        """Analytic physical Jacobians; dev097 science, current 2.0 model.

        Outputs physical rows (N,2), local (2N,2) and shared (2N,12).
        Shared 12 inputs are eight raster corners and four axis end-values.
        This does not by itself estimate any uncertainty: operator supplies it.
        """
        points=np.asarray(pixels)
        if points.dtype.kind not in 'iuf' or points.ndim!=2 or points.shape[1]!=2 or not 1<=points.shape[0]<=4096:
            raise CalibrationError('Linearization requires 1..4096 numeric raster point pairs.')
        if points.dtype.kind in 'iu' and (np.any(points>2**53) or np.any(points < -2**53)):
            raise CalibrationError('Pixel integers cannot lose binary64 precision.')
        points=points.astype(float)
        if not np.isfinite(points).all():raise CalibrationError('Pixel coordinates must be finite.')
        self.x_axis.validate();self.y_axis.validate()
        H,condition=self.calibration.matrix()
        derivative=self.calibration.corner_derivatives(H)
        coord=np.empty_like(points)
        local=np.zeros((2*len(points),2))
        shared=np.zeros((2*len(points),12))
        for i,(px,py) in enumerate(points):
            uv=np.asarray(self.calibration.transform_with_matrix(H,px,py))
            denom=float(H[2]@[px,py,1.])
            xyjac=(H[:2,:2]-uv[:,None]*H[2,:2])/denom
            hjac=np.zeros((2,8))
            hjac[0,:3]=np.array([px,py,1])/denom
            hjac[1,3:6]=np.array([px,py,1])/denom
            hjac[:,6:] = -uv[:,None]*np.array([px,py])/denom
            for axis,definition in enumerate((self.x_axis,self.y_axis)):
                value=definition.from_unit(float(uv[axis]))
                coord[i,axis]=value
                if definition.scale=='linear':
                    scale=definition.maximum-definition.minimum
                    ends=(1-uv[axis],uv[axis])
                else:
                    scale=value*(math.log(definition.maximum)-math.log(definition.minimum))
                    ends=(value*(1-uv[axis])/definition.minimum,value*uv[axis]/definition.maximum)
                local[2*i+axis]=scale*xyjac[axis]
                shared[2*i+axis,:8]=scale*(hjac[axis]@derivative)
                shared[2*i+axis,8+2*axis:10+2*axis]=ends
        if not all(np.isfinite(arr).all() for arr in (coord,local,shared)):
            raise CalibrationError('Non-finite calibration Jacobians.')
        return dict(schema='gxtxt.digitization_linearization.v1',coordinates=coord,
            point_jacobian=local,calibration_jacobian=shared,
            coordinate_units=[self.x_axis.unit or '1',self.y_axis.unit or '1'],
            calibration_ids=[f'{name}_{axis}' for name in CORNER_ORDER for axis in ('x','y')]+['x_minimum','x_maximum','y_minimum','y_maximum'],
            calibration_units=['pixel']*8+[self.x_axis.unit or '1']*2+[self.y_axis.unit or '1']*2,
            mapping='four_point_homography_then_declared_axis_scale',
            jacobian_method='analytic_implicit_calibration_system',condition_number=condition)

    def update_point_calibration(self, point: DigitizedPoint) -> None:
        try:
            point.calibrated_x, point.calibrated_y = self.pixel_to_calibrated(point.pixel_x, point.pixel_y)
        except CalibrationError:
            point.calibrated_x = point.calibrated_y = None

    def recalculate_all_points(self) -> None:
        for s in self.series:
            for p in s.points:
                self.update_point_calibration(p)

    def find_series(self, series_id: str | None) -> Series | None:
        return next((s for s in self.series if s.id == series_id), None)

    def to_dict(self) -> dict[str, Any]:
        return {
            "format": "giux-curve-digitizer-project",
            "version": self.format_version,
            "image": {"path": self.image_path, "width": self.image_width, "height": self.image_height},
            "axes": {"x": self.x_axis.to_dict(), "y": self.y_axis.to_dict()},
            "calibration": self.calibration.to_dict(),
            "series": [s.to_dict() for s in self.series],
            "notes": self.notes,
            "display": {"show_point_numbers": self.show_point_numbers},
            "snap": {"enabled": self.snap_enabled, "radius": self.snap_radius},
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Project":
        image, axes = data.get("image", {}), data.get("axes", {})
        display, snap = data.get("display", {}), data.get("snap", {})
        return cls(
            format_version=str(data.get("version", "1.0")),
            image_path=str(image.get("path", "")),
            image_width=int(image.get("width", 0)),
            image_height=int(image.get("height", 0)),
            x_axis=AxisConfig.from_dict(axes.get("x", {})),
            y_axis=AxisConfig.from_dict(axes.get("y", {})),
            calibration=Calibration.from_dict(data.get("calibration", {})),
            series=[Series.from_dict(s) for s in data.get("series", [])],
            notes=str(data.get("notes", "")),
            show_point_numbers=bool(display.get("show_point_numbers", False)),
            snap_enabled=bool(snap.get("enabled", False)),
            snap_radius=max(0, int(snap.get("radius", 3))),
        )
