#!/usr/bin/env python3
"""Bounded host raster compositing of Native2D device primitives.

The caller supplies a private render plan; geometry/calibration/view decisions
already came from Native2D. No plugin code or archive content is executed.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import argparse
import base64
import math
import io
import sys
from functools import lru_cache
from pathlib import Path
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = 64_000_000


def rgba(text):
    values = [float(value) for value in text.split()]
    return tuple(round(max(0, min(1, value)) * 255) for value in values)


@lru_cache(maxsize=2)
def reference_pixels(path):
    # Managed resources are immutable; the small worker cache avoids reopening
    # and decoding the same calibrated image for every camera frame.
    with Image.open(path) as image:
        if image.width * image.height > 64_000_000:
            raise ValueError("reference raster exceeds limit")
        return image.convert("RGBA")


def composite_image(canvas, path, opacity, frame):
    source = reference_pixels(path)
    x0, y0, ax, ay, bx, by = frame
    det = ax * by - ay * bx
    if not math.isfinite(det) or abs(det) < 1e-20:
        raise ValueError("singular reference raster device transform")
    # Inverse device mapping only: uniform world calibration belongs to C.
    coefficients = (by / det, -bx / det, (-by*x0 + bx*y0)/det,
                    -ay / det, ax / det, (ay*x0 - ax*y0)/det)
    warped = source.transform(canvas.size, Image.Transform.AFFINE, coefficients,
                              resample=Image.Resampling.BILINEAR)
    if opacity != 1:
        alpha = warped.getchannel("A").point(lambda value: round(value * opacity))
        warped.putalpha(alpha)
    canvas.alpha_composite(warped)

def render_text(plan, output):
    rows = [line.split("\t") for line in plan.splitlines()]
    width, height = map(int, rows[0][1:3])
    if width < 16 or height < 16 or width > 4096 or height > 4096:
        raise ValueError("preview dimensions must be 16..4096")
    canvas = Image.new("RGBA", (width, height), rgba(rows[0][3]))
    clip = tuple(map(float, rows[0][4].split()))
    layer = Image.new("RGBA", canvas.size)
    for row in rows[1:]:
        if row[0] == "image":
            path = base64.b64decode(row[1], validate=True).decode("utf-8")
            composite_image(layer, path, float(row[2]), list(map(float, row[3].split())))
        elif row[0] == "line":
            xy = list(map(float, row[3].split()))
            if len(xy) % 2 or len(xy) > 131072:
                raise ValueError("invalid bounded primitive")
            primitive = Image.new("RGBA", canvas.size)
            draw = ImageDraw.Draw(primitive)
            if len(xy) >= 4:
                points = list(zip(xy[::2], xy[1::2]))
                stroke = max(1, round(float(row[2])))
                style = int(row[4]) if len(row) > 4 else 0
                if style == 0:
                    draw.line(points, fill=rgba(row[1]), width=stroke, joint="curve")
                else:
                    # Carry dash phase across the sampled Native path, rather
                    # than restarting at each segment and changing its style.
                    dash, gap = (6., 3.) if style == 1 else (1., 3.)
                    phase = 0.
                    for start, end in zip(points, points[1:]):
                        dx, dy = end[0]-start[0], end[1]-start[1]
                        length = math.hypot(dx, dy); position = 0.
                        while position < length:
                            on = phase < dash
                            step = min(length-position, (dash if on else dash+gap)-phase)
                            if on and step > 0:
                                a = (start[0]+dx*position/length, start[1]+dy*position/length)
                                b = (start[0]+dx*(position+step)/length, start[1]+dy*(position+step)/length)
                                draw.line((a,b), fill=rgba(row[1]), width=stroke)
                            position += step; phase = (phase+step) % (dash+gap)
                layer.alpha_composite(primitive)
        elif row[0] == "point":
            x, y = map(float, row[3].split());radius = float(row[2])
            primitive = Image.new("RGBA", canvas.size)
            ImageDraw.Draw(primitive).ellipse((x-radius,y-radius,x+radius,y+radius), fill=rgba(row[1]))
            layer.alpha_composite(primitive)
        elif row[0] == "label":
            continue
        elif row[0] == "text":
            x, y = map(float, row[2].split())
            text = base64.b64decode(row[3], validate=True).decode("utf-8")
            primitive = Image.new("RGBA", canvas.size)
            ImageDraw.Draw(primitive).text((x,y), text, fill=rgba(row[1]))
            layer.alpha_composite(primitive)
        else:
            raise ValueError("unknown render primitive")
    mask = Image.new("L", canvas.size);ImageDraw.Draw(mask).rectangle(clip, fill=255)
    alpha = layer.getchannel("A")
    from PIL import ImageChops
    layer.putalpha(ImageChops.multiply(alpha, mask))
    canvas.alpha_composite(layer)
    for row in rows[1:]:
        if row[0] == "label":
            x,y=map(float,row[2].split());ImageDraw.Draw(canvas).text((x,y),base64.b64decode(row[3]).decode("utf-8"),fill=rgba(row[1]))
    canvas.save(output, "PNG", optimize=False, compress_level=6)


def render(plan, output):
    render_text(Path(plan).read_text(encoding="utf-8"), output)


def worker():
    # A single host-owned process, with one in-flight request. Geometry and
    # calibration remain Native decisions encoded in the shared render plan.
    for line in sys.stdin:
        try:
            plan = base64.b64decode(line.strip(), validate=True).decode("utf-8")
            result = io.BytesIO()
            render_text(plan, result)
            reply = base64.b64encode(result.getvalue()).decode("ascii")
        except Exception as error:
            reply = "ERROR " + base64.b64encode(str(error).encode()).decode("ascii")
        print(reply, flush=True)


def render_pdf(plan, output):
    """Vector PDF from the same Native presentation plan used by previews."""
    from reportlab.pdfgen import canvas as pdfcanvas
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    rows = [line.split("\t") for line in Path(plan).read_text(encoding="utf-8").splitlines()]
    width, height = map(int, rows[0][1:3])
    if not (16 <= width <= 4096 and 16 <= height <= 4096):
        raise ValueError("PDF dimensions must be 16..4096")
    c = pdfcanvas.Canvas(output, pagesize=(width, height), pageCompression=1)
    c.setTitle("GX-TXT Curve Workbench graphics")
    bg = list(map(float, rows[0][3].split()))
    c.setFillColorRGB(*bg[:3]); c.rect(0, 0, width, height, stroke=0, fill=1)
    x0, y0, x1, y1 = map(float, rows[0][4].split())
    c.saveState()
    p = c.beginPath(); p.rect(x0, height-y1, x1-x0, y1-y0); c.clipPath(p, stroke=0)
    font = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    if font.exists():
        pdfmetrics.registerFont(TTFont("GXText", str(font))); c.setFont("GXText", 10)
    else:
        c.setFont("Helvetica", 10)
    for row in rows[1:]:
        if row[0] == "label": continue
        if row[0] == "image":
            layer = Image.new("RGBA", (width, height))
            composite_image(layer, base64.b64decode(row[1]).decode(), float(row[2]), list(map(float, row[3].split())))
            c.drawImage(ImageReader(layer), 0, 0, width, height, mask="auto")
        else:
            color = list(map(float, row[1].split()))
            # Native styles may target a dark interactive canvas. Preserve hue
            # but cap luminance on paper so white/light geometry remains legible.
            luminance = .2126*color[0]+.7152*color[1]+.0722*color[2]
            if sum(bg[:3])/3 > .8 and luminance > .65:
                color[:3] = [v*.45/luminance for v in color[:3]]
            c.setStrokeColorRGB(*color[:3]); c.setFillColorRGB(*color[:3])
            c.setStrokeAlpha(color[3]); c.setFillAlpha(color[3])
            if row[0] == "line":
                xy = list(map(float, row[3].split()))
                if len(xy) < 4: continue
                p = c.beginPath(); p.moveTo(xy[0], height-xy[1])
                for x,y in zip(xy[2::2], xy[3::2]): p.lineTo(x, height-y)
                c.setLineWidth(float(row[2]))
                style = int(row[4]) if len(row)>4 else 0
                c.setDash([] if style==0 else ([6,3] if style==1 else [1,3]))
                c.drawPath(p)
            elif row[0] == "point":
                x,y = map(float,row[3].split()); c.circle(x,height-y,float(row[2]),stroke=0,fill=1)
            elif row[0] == "text":
                x,y = map(float,row[2].split()); c.drawString(x,height-y-10,base64.b64decode(row[3]).decode("utf-8"))
            else: raise ValueError("unknown PDF primitive")
    c.restoreState();c.setFont("GXText" if font.exists() else "Helvetica",10)
    for row in rows[1:]:
        if row[0] == "label":
            x,y=map(float,row[2].split());color=list(map(float,row[1].split()));c.setFillColorRGB(*color[:3])
            c.drawString(x,height-y-10,base64.b64decode(row[3]).decode("utf-8"))
    c.showPage(); c.save()


def main():
    if sys.argv[1:] == ["worker"]:
        worker()
        return
    parser = argparse.ArgumentParser();parser.add_argument("operation", choices=("render", "pdf", "info"))
    parser.add_argument("input");parser.add_argument("output", nargs="?");args = parser.parse_args()
    if args.operation == "info":
        with Image.open(args.input) as image:
            if image.width*image.height > 64_000_000 or max(image.size) > 32768:
                raise ValueError("reference raster exceeds limit")
            print(f"{image.width} {image.height}")
    elif args.operation == "pdf":
        render_pdf(args.input, args.output)
    else:
        render(args.input, args.output)


if __name__ == "__main__":
    main()
