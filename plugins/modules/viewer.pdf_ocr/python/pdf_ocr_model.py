# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Rect:
    x1: int
    y1: int
    x2: int
    y2: int

    def normalized(self) -> "Rect":
        return Rect(min(self.x1, self.x2), min(self.y1, self.y2), max(self.x1, self.x2), max(self.y1, self.y2))

    @property
    def width(self) -> int:
        r = self.normalized()
        return max(0, r.x2 - r.x1)

    @property
    def height(self) -> int:
        r = self.normalized()
        return max(0, r.y2 - r.y1)

    def clamp(self, width: int, height: int) -> "Rect":
        r = self.normalized()
        x1 = max(0, min(width, r.x1))
        y1 = max(0, min(height, r.y1))
        x2 = max(0, min(width, r.x2))
        y2 = max(0, min(height, r.y2))
        return Rect(x1, y1, x2, y2).normalized()

    def moved(self, dx: int, dy: int, width: int, height: int) -> "Rect":
        r = self.normalized()
        w, h = r.width, r.height
        nx1 = max(0, min(max(0, width - w), r.x1 + dx))
        ny1 = max(0, min(max(0, height - h), r.y1 + dy))
        return Rect(nx1, ny1, nx1 + w, ny1 + h)

    def resized(self, handle: str, x: int, y: int, width: int, height: int, minimum: int = 2) -> "Rect":
        r = self.normalized()
        x = max(0, min(width, x))
        y = max(0, min(height, y))
        x1, y1, x2, y2 = r.x1, r.y1, r.x2, r.y2
        if "w" in handle:
            x1 = min(x, x2 - minimum)
        if "e" in handle:
            x2 = max(x, x1 + minimum)
        if "n" in handle:
            y1 = min(y, y2 - minimum)
        if "s" in handle:
            y2 = max(y, y1 + minimum)
        return Rect(x1, y1, x2, y2).clamp(width, height)

    def as_csv(self) -> str:
        r = self.normalized()
        return f"{r.x1},{r.y1},{r.x2},{r.y2}"


HANDLES = ("nw", "n", "ne", "e", "se", "s", "sw", "w")


def handle_points(rect: Rect) -> dict[str, tuple[float, float]]:
    r = rect.normalized()
    mx = (r.x1 + r.x2) / 2.0
    my = (r.y1 + r.y2) / 2.0
    return {
        "nw": (r.x1, r.y1), "n": (mx, r.y1), "ne": (r.x2, r.y1),
        "e": (r.x2, my), "se": (r.x2, r.y2), "s": (mx, r.y2),
        "sw": (r.x1, r.y2), "w": (r.x1, my),
    }


def hit_test(rect: Rect | None, x: float, y: float, radius: float) -> tuple[str, str]:
    if rect is None or rect.width < 1 or rect.height < 1:
        return ("new", "")
    for name, (hx, hy) in handle_points(rect).items():
        if abs(x - hx) <= radius and abs(y - hy) <= radius:
            return ("resize", name)
    r = rect.normalized()
    if r.x1 <= x <= r.x2 and r.y1 <= y <= r.y2:
        return ("move", "")
    return ("new", "")
