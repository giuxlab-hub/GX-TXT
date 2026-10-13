# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

from dataclasses import dataclass
import csv
import io
import math
import re
import statistics
import unicodedata
from typing import Iterable


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
        return r.x2 - r.x1

    @property
    def height(self) -> int:
        r = self.normalized()
        return r.y2 - r.y1

    def clamp(self, width: int, height: int) -> "Rect":
        r = self.normalized()
        return Rect(max(0, min(width, r.x1)), max(0, min(height, r.y1)), max(0, min(width, r.x2)), max(0, min(height, r.y2)))

    def moved(self, dx: int, dy: int, width: int, height: int) -> "Rect":
        r = self.normalized()
        w, h = r.width, r.height
        nx1 = max(0, min(width - w, r.x1 + dx))
        ny1 = max(0, min(height - h, r.y1 + dy))
        return Rect(nx1, ny1, nx1 + w, ny1 + h)

    def resized(self, handle: str, x: int, y: int, width: int, height: int) -> "Rect":
        r = self.normalized()
        left, top, right, bottom = r.x1, r.y1, r.x2, r.y2
        if "w" in handle:
            left = x
        if "e" in handle:
            right = x
        if "n" in handle:
            top = y
        if "s" in handle:
            bottom = y
        return Rect(left, top, right, bottom).normalized().clamp(width, height)

    def as_csv(self) -> str:
        r = self.normalized()
        return f"{r.x1},{r.y1},{r.x2},{r.y2}"


HANDLES = ("nw", "n", "ne", "e", "se", "s", "sw", "w")


def handle_points(rect: Rect) -> dict[str, tuple[float, float]]:
    r = rect.normalized()
    cx = (r.x1 + r.x2) / 2
    cy = (r.y1 + r.y2) / 2
    return {
        "nw": (r.x1, r.y1), "n": (cx, r.y1), "ne": (r.x2, r.y1),
        "e": (r.x2, cy), "se": (r.x2, r.y2), "s": (cx, r.y2),
        "sw": (r.x1, r.y2), "w": (r.x1, cy),
    }


def hit_test(rect: Rect | None, x: float, y: float, radius: float) -> tuple[str, str]:
    if rect is None:
        return ("new", "")
    r = rect.normalized()
    for name, (hx, hy) in handle_points(r).items():
        if abs(x - hx) <= radius and abs(y - hy) <= radius:
            return ("resize", name)
    if r.x1 <= x <= r.x2 and r.y1 <= y <= r.y2:
        return ("move", "")
    return ("new", "")


@dataclass(frozen=True)
class Word:
    x: float
    y: float
    w: float
    h: float
    text: str
    confidence: float = 100.0

    @property
    def x2(self) -> float:
        return self.x + self.w

    @property
    def y2(self) -> float:
        return self.y + self.h

    @property
    def cx(self) -> float:
        return self.x + self.w / 2.0

    @property
    def cy(self) -> float:
        return self.y + self.h / 2.0


def _parse_tsv_rows(text: str) -> list[dict[str, str]]:
    if not text.strip():
        return []
    reader = csv.DictReader(io.StringIO(text), delimiter="\t")
    return [row for row in reader if row]


def parse_tesseract_tsv(text: str) -> list[Word]:
    out: list[Word] = []
    for row in _parse_tsv_rows(text):
        if row.get("level") != "5":
            continue
        token = (row.get("text") or "").strip()
        if not token:
            continue
        try:
            conf = float(row.get("conf", "-1") or -1)
            out.append(Word(float(row["left"]), float(row["top"]), float(row["width"]), float(row["height"]), token, conf))
        except (KeyError, ValueError):
            continue
    return out


def parse_pdftotext_tsv(text: str, dpi: int) -> list[Word]:
    scale = float(dpi) / 72.0
    out: list[Word] = []
    for row in _parse_tsv_rows(text):
        if row.get("level") != "5":
            continue
        token = (row.get("text") or "").strip()
        if not token or token.startswith("###"):
            continue
        try:
            out.append(Word(
                float(row["left"]) * scale,
                float(row["top"]) * scale,
                float(row["width"]) * scale,
                float(row["height"]) * scale,
                token,
                100.0,
            ))
        except (KeyError, ValueError):
            continue
    return out


def filter_words(words: Iterable[Word], roi: Rect | None) -> list[Word]:
    if roi is None:
        return list(words)
    r = roi.normalized()
    return [w for w in words if r.x1 <= w.cx <= r.x2 and r.y1 <= w.cy <= r.y2]


def cluster_rows(words: Iterable[Word]) -> list[list[Word]]:
    words = sorted(words, key=lambda w: (w.cy, w.x))
    if not words:
        return []
    heights = [max(1.0, w.h) for w in words]
    tolerance = max(3.0, statistics.median(heights) * 0.65)
    rows: list[list[Word]] = []
    centers: list[float] = []
    for word in words:
        best = -1
        best_distance = float("inf")
        for i, center in enumerate(centers):
            distance = abs(word.cy - center)
            if distance <= tolerance and distance < best_distance:
                best = i
                best_distance = distance
        if best < 0:
            rows.append([word])
            centers.append(word.cy)
        else:
            rows[best].append(word)
            centers[best] = statistics.median([w.cy for w in rows[best]])
    order = sorted(range(len(rows)), key=lambda i: centers[i])
    return [sorted(rows[i], key=lambda w: w.x) for i in order]


def _candidate_boundaries(rows: list[list[Word]]) -> list[tuple[float, float, int]]:
    if not rows:
        return []
    all_heights = [max(1.0, w.h) for row in rows for w in row]
    median_height = statistics.median(all_heights) if all_heights else 10.0
    min_gap = max(8.0, median_height * 0.85)
    candidates: list[tuple[float, float, int]] = []
    for ri, row in enumerate(rows):
        for left, right in zip(row, row[1:]):
            gap = right.x - left.x2
            if gap >= min_gap:
                candidates.append(((left.x2 + right.x) / 2.0, gap, ri))
    return candidates


def infer_boundaries(rows: list[list[Word]], expected_columns: int = 0) -> list[float]:
    candidates = _candidate_boundaries(rows)
    if not candidates:
        return []
    all_heights = [max(1.0, w.h) for row in rows for w in row]
    tolerance = max(12.0, (statistics.median(all_heights) if all_heights else 10.0) * 1.6)
    groups: list[list[tuple[float, float, int]]] = []
    for item in sorted(candidates, key=lambda x: x[0]):
        if not groups or abs(item[0] - statistics.mean(x[0] for x in groups[-1])) > tolerance:
            groups.append([item])
        else:
            groups[-1].append(item)
    ranked: list[tuple[float, float, int]] = []
    row_count = max(1, len(rows))
    min_support = 1 if row_count <= 2 else max(2, math.ceil(row_count * 0.35))
    for group in groups:
        pos = statistics.median(x[0] for x in group)
        support = len({x[2] for x in group})
        mean_gap = statistics.mean(x[1] for x in group)
        score = support * 1000.0 + mean_gap
        if expected_columns > 0 or support >= min_support:
            ranked.append((pos, score, support))
    if expected_columns > 0:
        needed = max(0, expected_columns - 1)
        ranked = sorted(ranked, key=lambda x: x[1], reverse=True)[:needed]
    return sorted(x[0] for x in ranked)


def reconstruct_table(words: Iterable[Word], expected_columns: int = 0) -> tuple[list[list[str]], list[float]]:
    rows = cluster_rows(words)
    if not rows:
        return ([], [])
    boundaries = infer_boundaries(rows, expected_columns=expected_columns)
    col_count = len(boundaries) + 1
    table: list[list[str]] = []
    for row in rows:
        cells: list[list[Word]] = [[] for _ in range(col_count)]
        for word in row:
            ci = 0
            while ci < len(boundaries) and word.cx > boundaries[ci]:
                ci += 1
            cells[ci].append(word)
        values = [" ".join(w.text for w in sorted(cell, key=lambda w: w.x)).strip() for cell in cells]
        if any(values):
            table.append(values)
    return (table, boundaries)


_INT_RE = re.compile(r"^[+-]?\d+$")
_FLOAT_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def normalize_numeric_text(value: str) -> str:
    return value.strip().replace("−", "-").replace("–", "-")


def infer_dtype(values: Iterable[str]) -> str:
    values = [normalize_numeric_text(v) for v in values]
    if not values or any(v == "" for v in values):
        return "string"
    if all(_INT_RE.fullmatch(v) for v in values):
        return "int64"
    if all(_FLOAT_RE.fullmatch(v) for v in values):
        return "float64"
    return "string"


def sanitize_variable_id(label: str, index: int) -> str:
    ascii_label = unicodedata.normalize("NFKD", label).encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^A-Za-z0-9_]+", "_", ascii_label.strip()).strip("_").lower()
    if not value:
        value = f"column_{index + 1}"
    if not value[0].isalpha():
        value = f"column_{value}"
    return value[:80]


def build_columns(table: list[list[str]], first_row_header: bool) -> tuple[list[dict[str, str]], list[list[str]]]:
    if not table:
        return ([], [])
    col_count = max(len(row) for row in table)
    normalized = [row + [""] * (col_count - len(row)) for row in table]
    if first_row_header:
        labels = [cell.strip() or f"Column {i + 1}" for i, cell in enumerate(normalized[0])]
        data_rows = normalized[1:]
    else:
        labels = [f"Column {i + 1}" for i in range(col_count)]
        data_rows = normalized
    if not data_rows:
        return ([], [])
    seen: dict[str, int] = {}
    columns: list[dict[str, str]] = []
    for i, label in enumerate(labels):
        base = sanitize_variable_id(label, i)
        count = seen.get(base, 0) + 1
        seen[base] = count
        var_id = base if count == 1 else f"{base}_{count}"
        dtype = infer_dtype(row[i] for row in data_rows)
        columns.append({"id": var_id, "label": label, "dtype": dtype})
    return (columns, data_rows)
