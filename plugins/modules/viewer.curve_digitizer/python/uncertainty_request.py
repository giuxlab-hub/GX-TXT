# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage the existing calibration owner's facts in CORE typed binary transport."""
from pathlib import Path
import base64
import json
import sys
import numpy as np

from companion_bridge import _load, _project_from_config


def stage(configuration, workspace):
    root = Path(__file__).resolve().parents[4]
    sys.path.insert(0, str(root / "core" / "python"))
    from gxtxt_scientific_binary_v1 import write_buffer

    cfg = _load(Path(configuration))
    project = _project_from_config(cfg)
    spec = cfg.get("uncertainty", {})
    if not spec or spec.get("mode") == "none":
        raise ValueError("Declare and review an uncertainty model before publication.")
    workspace = Path(workspace).resolve(strict=True)
    points = [(s, i, p) for s in project.series for i, p in enumerate(s.points)]
    if not 1 <= len(points) <= 4096:
        raise ValueError("Uncertainty review supports 1 to 4096 original points.")
    identities = [p.id for _, _, p in points]
    if len(set(identities)) != len(identities) or any(not x or len(x) > 160 for x in identities):
        raise ValueError("Every point needs a unique, bounded scientific identity.")
    pixels = np.asarray([[p.pixel_x, p.pixel_y] for _, _, p in points])
    linearization = project.calibration_linearization(pixels)

    def pack(value):
        if isinstance(value, dict):
            return {"kind": "struct", "fields": {k: pack(v) for k, v in value.items()}}
        if isinstance(value, str):
            return {"kind": "text", "value": value}
        if isinstance(value, (list, tuple)) and all(isinstance(v, str) for v in value):
            return {"kind": "cell", "items": [pack(v) for v in value]}
        return {"kind": "binary", "descriptor": write_buffer(workspace, np.asarray(value))}

    request = dict(family="digitizer", action="propagate", binary_workspace=str(workspace),
                   a=pack(linearization), b=pack(spec), c={"kind": "empty"},
                   options=pack({"workspace": str(workspace)}))
    payload = json.dumps(request, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    if len(payload.encode()) > 1048576:
        raise ValueError("Uncertainty control request exceeds its bounded transport.")
    (workspace / "request.json").write_text(payload, encoding="utf-8")
    encode = lambda x: base64.b64encode(str(x).encode()).decode("ascii")
    lines = []
    for series, index, point in points:
        if len(series.name) > 256 or len(series.id) > 160:
            raise ValueError("Curve names and identities exceed their publication bound.")
        lines.append("\t".join(map(encode, [series.id, series.name, point.id, index, series.parameter_value])))
    (workspace / "points.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    stage(*sys.argv[1:])
