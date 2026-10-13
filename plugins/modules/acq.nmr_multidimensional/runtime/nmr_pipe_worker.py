#!/usr/bin/env python3
"""Read acquired NMRPipe spectra and render domain-specific NMR views."""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import base64
import hashlib
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent / "vendor"))
import nmrglue as ng
import numpy as np


def emit(key, value):
    raw = str(value).encode("utf-8")
    print(f"{key}\t{base64.b64encode(raw).decode('ascii')}")


def source(path):
    d, array = ng.pipe.read(str(path))
    if array.ndim not in (2, 3):
        raise ValueError("Only acquired 2-D or 3-D NMRPipe spectra are supported")
    if np.iscomplexobj(array):
        raise ValueError("NMRPipe source is complex/time-domain; import a phase-corrected real spectrum")
    axes = []
    for index in range(array.ndim):
        uc = ng.pipe.make_uc(d, array, dim=index)
        number = int(d["FDDIMORDER"][array.ndim - index - 1])
        label = str(d.get(f"FDF{number}LABEL", "")).strip()
        nucleus = {"H": "1H", "HN": "1H", "N": "15N", "CO": "13C", "C": "13C", "CA": "13C", "CB": "13C"}.get(label.upper(), label)
        ppm = np.asarray(uc.ppm_scale(), dtype=np.float64)
        axes.append(dict(label=label, nucleus=nucleus, ppm=ppm,
                         frequency_mhz=float(d.get(f"FDF{number}OBS", 0))))
    return d, array, axes


def inspect(path):
    d, array, axes = source(path)
    emit("dimensions", array.ndim)
    emit("shape", ",".join(map(str, array.shape)))
    emit("experiment", pathlib.Path(path).name)
    emit("source_sha256", hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest())
    emit("minimum", float(np.nanmin(array)))
    emit("maximum", float(np.nanmax(array)))
    for i, axis in enumerate(axes, 1):
        for key in ("label", "nucleus", "frequency_mhz"):
            emit(f"axis_{i}_{key}", axis[key])
        emit(f"axis_{i}_ppm_first", axis["ppm"][0])
        emit(f"axis_{i}_ppm_last", axis["ppm"][-1])
        emit(f"axis_{i}_points", len(axis["ppm"]))


def plane_data(array, axes, plane, coords):
    keep = tuple(int(x) for x in plane.split(","))
    if len(keep) != 2 or len(set(keep)) != 2 or any(x not in range(array.ndim) for x in keep):
        raise ValueError("Plane must contain two distinct axis indices")
    slicer = tuple(slice(None) if i in keep else coords[i] for i in range(array.ndim))
    view = array[slicer]
    natural = tuple(i for i in range(array.ndim) if i in keep)
    if natural != keep:
        view = view.T
    return view, axes[keep[0]]["ppm"], axes[keep[1]]["ppm"], keep


def render(path, out, plane, coords, threshold, levels, positive, negative, xlim, ylim):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec
    _, array, axes = source(path)
    coords = [max(0, min(array.shape[i] - 1, int(x))) for i, x in enumerate(coords)]
    view, ya, xa, keep = plane_data(array, axes, plane, coords)
    finite = np.asarray(view, dtype=np.float64)
    finite[~np.isfinite(finite)] = 0
    scale = max(float(np.max(np.abs(finite))), 1.0)
    floor = max(float(threshold), 0.001) * scale
    contour = np.geomspace(floor, scale, max(2, int(levels)))
    fig = plt.figure(figsize=(8.6, 6.3), dpi=100, facecolor="#f5f7fa")
    gs = GridSpec(2, 2, width_ratios=[5, 1.15], height_ratios=[1.1, 5],
                  left=.10, right=.94, top=.94, bottom=.12, wspace=.06, hspace=.07)
    top = fig.add_subplot(gs[0, 0])
    main = fig.add_subplot(gs[1, 0], sharex=top)
    right = fig.add_subplot(gs[1, 1], sharey=main)
    xp, yp = xa, ya
    X, Y = np.meshgrid(xp, yp)
    main.imshow(finite, extent=[xp[0], xp[-1], yp[-1], yp[0]], origin="upper",
                aspect="auto", cmap="Greys", alpha=.22, interpolation="nearest")
    if positive and np.any(finite >= floor):
        main.contour(X, Y, finite, levels=contour, colors="#135fa8", linewidths=.8)
    if negative and np.any(finite <= -floor):
        main.contour(X, Y, finite, levels=-contour[::-1], colors="#c24c54", linewidths=.8, linestyles="solid")
    yi, xi = coords[keep[0]], coords[keep[1]]
    main.axvline(xp[xi], color="#e6a225", lw=1, ls="--")
    main.axhline(yp[yi], color="#e6a225", lw=1, ls="--")
    main.scatter([xp[xi]], [yp[yi]], c="#e6a225", s=22, zorder=4)
    main.set_xlabel(f"F{keep[1]+1} {axes[keep[1]]['nucleus']} chemical shift (ppm)")
    main.set_ylabel(f"F{keep[0]+1} {axes[keep[0]]['nucleus']} chemical shift (ppm)")
    main.set_xlim(*(xlim or (xp[0], xp[-1])))
    main.set_ylim(*(ylim or (yp[0], yp[-1])))
    main.grid(alpha=.12)
    top.plot(xp, finite[yi, :], color="#135fa8", lw=1)
    top.plot(xp, np.max(finite, axis=0), color="#6b7f93", lw=.7, alpha=.7)
    top.axvline(xp[xi], color="#e6a225", lw=.8, ls="--")
    top.tick_params(labelbottom=False, labelsize=8)
    top.set_ylabel(f"F{keep[1]+1} slice / max", fontsize=8)
    right.plot(finite[:, xi], yp, color="#135fa8", lw=1)
    right.plot(np.max(finite, axis=1), yp, color="#6b7f93", lw=.7, alpha=.7)
    right.axhline(yp[yi], color="#e6a225", lw=.8, ls="--")
    right.tick_params(labelleft=False, labelsize=8)
    right.set_xlabel(f"F{keep[0]+1} slice / max", fontsize=8)
    fig.savefig(out, dpi=100)
    fig.canvas.draw()
    bbox = main.get_window_extent()
    h = fig.canvas.get_width_height()[1]
    emit("plot_bbox", ",".join(f"{v:.2f}" for v in (bbox.x0, h-bbox.y1, bbox.x1, h-bbox.y0)))
    emit("x_bounds", ",".join(map(str, main.get_xlim())))
    emit("y_bounds", ",".join(map(str, main.get_ylim())))
    emit("selected_ppm", ",".join(str(axes[i]["ppm"][coords[i]]) for i in range(array.ndim)))
    emit("intensity", float(array[tuple(coords)]))
    from scipy.ndimage import maximum_filter
    candidates = (finite >= floor) & (finite == maximum_filter(finite, size=9))
    peaks = np.argwhere(candidates)
    peaks = sorted(peaks, key=lambda ij: float(finite[tuple(ij)]), reverse=True)[:25]
    emit("peak_table", "\n".join(f"{xp[ix]:.4f}\t{yp[iy]:.4f}\t{finite[iy, ix]:.6g}"
                                  for iy, ix in peaks))
    emit("image", out)
    plt.close(fig)


def extract(path, out, plane, coords, kind):
    _, array, axes = source(path)
    coords = [max(0, min(array.shape[i] - 1, int(x))) for i, x in enumerate(coords)]
    view, ya, xa, keep = plane_data(array, axes, plane, coords)
    if kind == "projection_max":
        hidden = [i for i in range(array.ndim) if i not in keep]
        if hidden:
            view = np.max(array, axis=hidden[0])
            if tuple(i for i in range(array.ndim) if i in keep) != keep:
                view = view.T
    with open(out, "w", encoding="utf-8", newline="") as stream:
        if kind in ("plane", "projection_max"):
            stream.write(f"f{keep[0]+1}_ppm,f{keep[1]+1}_ppm,intensity\n")
            for iy, y in enumerate(ya):
                for ix, x in enumerate(xa):
                    stream.write(f"{y:.9g},{x:.9g},{float(view[iy, ix]):.9g}\n")
        elif kind == "profile_x":
            stream.write(f"f{keep[1]+1}_ppm,intensity\n")
            for x, z in zip(xa, view[coords[keep[0]], :]):
                stream.write(f"{x:.9g},{float(z):.9g}\n")
        elif kind == "profile_y":
            stream.write(f"f{keep[0]+1}_ppm,intensity\n")
            for y, z in zip(ya, view[:, coords[keep[1]]]):
                stream.write(f"{y:.9g},{float(z):.9g}\n")
        else:
            raise ValueError("Unknown extraction kind")
    emit("rows", sum(1 for _ in open(out, encoding="utf-8")) - 1)
    emit("output", out)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=("inspect", "render", "extract"))
    p.add_argument("path")
    p.add_argument("--out", default="")
    p.add_argument("--plane", default="0,1")
    p.add_argument("--coords", default="0,0,0")
    p.add_argument("--threshold", type=float, default=.08)
    p.add_argument("--levels", type=int, default=8)
    p.add_argument("--positive", type=int, default=1)
    p.add_argument("--negative", type=int, default=1)
    p.add_argument("--xlim", default="")
    p.add_argument("--ylim", default="")
    p.add_argument("--kind", default="plane")
    a = p.parse_args()
    if a.action == "inspect":
        inspect(a.path)
    elif a.action == "render":
        def bounds(value):
            return tuple(float(x) for x in value.split(",")) if value else None
        render(a.path, a.out, a.plane, [int(x) for x in a.coords.split(",")],
               a.threshold, a.levels, a.positive, a.negative,
               bounds(a.xlim), bounds(a.ylim))
    else:
        extract(a.path, a.out, a.plane, [int(x) for x in a.coords.split(",")], a.kind)


if __name__ == "__main__":
    main()
