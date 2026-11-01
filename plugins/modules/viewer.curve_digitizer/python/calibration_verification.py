# SPDX-License-Identifier: GPL-3.0-or-later
"""Transient scientific calibration verification, including independent log axes.

This is NOT uncertainty propagation, accuracy certification, or a persisted
calibration. Reference inputs always have PHYSICAL axis units, not log10 units.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any

from digitizer_model import AxisConfig, CalibrationError, Project


class ReferenceValueError(ValueError):
    """Invalid operator-entered reference value."""


_LOG_POWER = re.compile(r"^10\s*\^\s*\(?\s*([+-]?(?:\d+(?:[.,]\d*)?|\.\d+))\s*\)?$")


def parse_reference(text: str, axis: AxisConfig) -> float | None:
    """Parse physical values: 1e3, 1000, 1,5e-3, or explicitly 10^3.

    Blank reference = deliberately not assessed; no residual is computed.
    Implicit exponent notation (such as '3' meaning 10^3) is NEVER assumed.
    """
    value = str(text).strip().replace("−", "-")
    if not value:
        return None
    try:
        power = _LOG_POWER.fullmatch(value)
        if power:
            exponent = float(power.group(1).replace(",", "."))
            number = 10.0 ** exponent
        else:
            if value.count(",") > 1 or ("," in value and "." in value):
                raise ReferenceValueError("Use either a dot or a comma as decimal separator.")
            number = float(value.replace(",", "."))
    except (ValueError, OverflowError) as exc:
        if isinstance(exc, ReferenceValueError):
            raise
        raise ReferenceValueError(
            "Enter a physical numeric value (for example 1e3, 1000 or 10^3)."
        ) from exc
    if not math.isfinite(number):
        raise ReferenceValueError("Reference values must be finite.")
    if axis.scale == "log" and number <= 0.0:
        raise ReferenceValueError("A logarithmic axis requires a strictly positive physical reference.")
    return number


def display_number(number: float, *, signed: bool = False) -> str:
    if not math.isfinite(number):
        raise ReferenceValueError("A calculated or reference value is not finite.")
    if number == 0:
        return "0"
    formatted = format(number, "+.7g" if signed else ".7g")
    return formatted.replace("e+0", "e+").replace("e-0", "e-")


@dataclass(frozen=True)
class AxisVerification:
    axis_id: str
    label: str
    unit: str
    scale: str
    measured: float
    reference: float | None
    delta: float | None
    comparison: float | None
    comparison_kind: str  # percent | decades | none
    error: str | None

    @property
    def reference_display(self) -> str:
        if self.error:
            return "Invalid"
        return "—" if self.reference is None else display_number(self.reference)

    @property
    def measured_display(self) -> str:
        return display_number(self.measured)

    @property
    def is_numerically_zero(self) -> bool:
        # Hide only roundoff-level residuals in the readout. Preserve the full
        # underlying result for tests and downstream scientific calculations.
        if self.reference is None or self.delta is None:
            return False
        scale = max(abs(self.measured), abs(self.reference))
        return self.delta == 0 or (scale > 0 and abs(self.delta) <= 1e-12*scale)

    @property
    def delta_display(self) -> str:
        if self.delta is None:
            return "—"
        return "0" if self.is_numerically_zero else display_number(self.delta, signed=True)

    @property
    def comparison_display(self) -> str:
        if self.comparison is None:
            return "—"
        if self.comparison_kind == "decades":
            return ("0" if self.is_numerically_zero else
                    display_number(self.comparison, signed=True)) + " decades"
        if self.comparison_kind == "percent":
            return ("0" if self.is_numerically_zero else
                    display_number(self.comparison, signed=True)) + " %"
        return "—"


def evaluate_verification(project: Project, pixel_x: float, pixel_y: float,
                          expected: dict[str, str]) -> list[AxisVerification]:
    """Return axis-independent physical readings and scale-aware differences.

    The four-corner homography is computed once. All axis values use its shared
    (u,v) coordinates, never separate geometric calibrations.
    """
    if not project.calibration_ready():
        raise CalibrationError("Select a complete, valid four-corner calibration first.")
    x, y = float(pixel_x), float(pixel_y)
    if not math.isfinite(x) or not math.isfinite(y):
        raise CalibrationError("Verification pixel positions must be finite.")
    u, v = project.calibration.pixel_to_unit(x, y)
    specs: list[tuple[str, AxisConfig, float]] = [
        ("x", project.x_axis, u),
        ("y1", project.y_axis, v),
    ]
    if project.y2_axis is not None:
        specs.append(("y2", project.y2_axis, v))
    result: list[AxisVerification] = []
    for axis_id, axis, coordinate in specs:
        measured = axis.from_unit(coordinate)
        if not math.isfinite(measured):
            raise CalibrationError(f"Non-finite calculated {axis_id} coordinate.")
        reference = delta = comparison = None
        comparison_kind = "none"
        error = None
        try:
            reference = parse_reference(expected.get(axis_id, ""), axis)
            if reference is not None:
                delta = measured - reference
                if not math.isfinite(delta):
                    raise ReferenceValueError("Difference exceeds finite numeric range.")
                if axis.scale == "log":
                    if measured <= 0:
                        raise ReferenceValueError("Calculated logarithmic value is nonpositive.")
                    # Difference in decades; safe across very large/small scales.
                    comparison = math.log10(measured) - math.log10(reference)
                    comparison_kind = "decades"
                elif reference != 0:
                    relative = 100.0 * (delta / abs(reference))
                    if math.isfinite(relative):
                        comparison = relative
                        comparison_kind = "percent"
        except ReferenceValueError as exc:
            error = str(exc)
            reference = delta = comparison = None
        result.append(AxisVerification(
            axis_id=axis_id,
            label=axis.name or axis_id.upper(),
            unit=axis.unit or "1",
            scale=axis.scale,
            measured=measured,
            reference=reference,
            delta=delta,
            comparison=comparison,
            comparison_kind=comparison_kind,
            error=error,
        ))
    return result
