#!/usr/bin/env python3
"""Render CORE snapshot primitives; parse Tcl lists without evaluating Tcl code."""
# SPDX-License-Identifier: GPL-3.0-or-later
import math
import sys
from pathlib import Path
from tkinter import Tcl
import xml.etree.ElementTree as ET

DECODER = Tcl()
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)

def seq(value):
    return DECODER.splitlist(value)

def record(value):
    fields = seq(value)
    if len(fields) % 2:
        raise ValueError("Malformed snapshot dictionary")
    return dict(zip(fields[::2], fields[1::2]))

def numbers(value):
    result = tuple(float(x) for x in seq(value))
    if not all(math.isfinite(x) for x in result):
        raise ValueError("Nonfinite snapshot coordinate")
    return result

def rgba(value):
    color = numbers(value)
    if len(color) != 4 or any(x < 0 or x > 1 for x in color):
        raise ValueError("Invalid RGBA snapshot color")
    return color

def css(color):
    return "rgb(%d,%d,%d)" % tuple(round(x * 255) for x in color[:3])

def child(parent, name, attributes):
    return ET.SubElement(parent, "{%s}%s" % (NS, name),
                         {key: str(value) for key, value in attributes.items()})

def decode(snapshot):
    if snapshot["api_id"] != "NATIVE2D_PRESENTATION_SNAPSHOT_v1" or snapshot["api_version"] != "1":
        raise ValueError("Unsupported snapshot")
    view = seq(snapshot["view"])
    width, height, left, top, right, bottom = (float(x) for x in view[:6])
    if not all(math.isfinite(x) for x in (width, height, left, top, right, bottom)) or not 1 <= width <= 16384 or not 1 <= height <= 16384:
        raise ValueError("Invalid snapshot viewport")
    clip = (left, top, width - right - left, height - bottom - top)
    if min(clip[2:]) <= 0:
        raise ValueError("Empty snapshot plot")
    background = rgba(record(snapshot["presentation"])["background"])
    background = tuple(x * background[3] + 1 - background[3] for x in background[:3]) + (1.,)
    primitives = []
    def line(points, color, linewidth, linestyle=0):
        if len(points) > 1:
            primitives.append(("line", points, color, float(linewidth), int(linestyle)))
    for raw in seq(snapshot["grid_primitives"]):
        grid = record(raw)
        line([numbers(grid["a"]), numbers(grid["b"])], rgba(grid["color"]), grid["width"], grid["style"])
    for raw in seq(snapshot["objects"]):
        obj = record(raw); style = record(obj["style"]); color = rgba(style["color"])
        for raw_path in seq(obj["paths"]):
            points = [numbers(p) for p in seq(raw_path)]
            if obj["kind"] == "curve":
                line(points, color, style["line_width"], style["line_style"])
            marker = int(style["marker"])
            if obj["kind"] != "curve" or marker:
                for point in points:
                    primitives.append(("glyph", point, color, marker, 3.))
        if "marker" in obj:
            marker = record(obj["marker"]); marker_style = record(obj["marker_style"])
            line([numbers(marker["tail"]), numbers(marker["tip"])], rgba(marker_style["color"]), marker_style["line_width"])
            line([numbers(marker["head_left"]), numbers(marker["tip"]), numbers(marker["head_right"])], rgba(marker_style["color"]), marker_style["line_width"])
    for raw in seq(snapshot.get("legend_primitives", "")):
        legend = record(raw)
        line([numbers(legend["a"]), numbers(legend["b"])], rgba(legend["color"]), legend["width"], legend["style"])
    texts = []
    for raw in seq(snapshot["texts"]):
        text = record(raw)
        texts.append((numbers(text["position"]), text["text"], text["anchor"],
                      float(text["rotation"]), float(text["font_size"]), rgba(text["color"])))
    return width, height, clip, background, primitives, texts

def svg(frame):
    width, height, clip, background, primitives, texts = frame
    root = ET.Element("{%s}svg" % NS, {"width": str(width), "height": str(height), "viewBox": "0 0 %g %g" % (width, height)})
    defs = child(root, "defs", {}); clipping = child(defs, "clipPath", {"id": "native-viewport"})
    child(clipping, "rect", dict(zip(("x", "y", "width", "height"), clip)))
    child(root, "rect", {"width": width, "height": height, "fill": css(background)})
    group = child(root, "g", {"clip-path": "url(#native-viewport)"})
    for kind, points, color, width_or_marker, dash_or_radius in primitives:
        if kind == "line":
            attrs = {"points": " ".join("%g,%g" % p for p in points), "fill": "none", "stroke": css(color), "stroke-opacity": color[3], "stroke-width": width_or_marker, "stroke-linejoin": "round", "stroke-linecap": "round"}
            if dash_or_radius: attrs["stroke-dasharray"] = "6 3" if dash_or_radius == 1 else "1 3"
            child(group, "polyline", attrs)
        else:
            x, y = points; radius = dash_or_radius
            attrs = {"fill": css(color), "fill-opacity": color[3]}
            if width_or_marker == 2:
                child(group, "rect", dict(attrs, x=x-radius, y=y-radius, width=2*radius, height=2*radius))
            elif width_or_marker == 3:
                child(group, "path", {"d": "M %g %g h %g M %g %g v %g" % (x-radius, y, 2*radius, x, y-radius, 2*radius), "fill": "none", "stroke": css(color), "stroke-opacity": color[3]})
            else: child(group, "circle", dict(attrs, cx=x, cy=y, r=radius))
    child(root, "rect", dict(zip(("x", "y", "width", "height"), clip), fill="none", stroke="#8393A5"))
    for (x,y), content, anchor, rotation, fontsize, color in texts:
        attrs = {"x": x, "y": y, "fill": css(color), "fill-opacity": color[3], "font-family": "sans-serif", "font-size": fontsize, "text-anchor": "end" if "e" in anchor else "start" if "w" in anchor else "middle", "dominant-baseline": "hanging" if "n" in anchor else "text-after-edge" if "s" in anchor else "central"}
        if rotation: attrs["transform"] = "rotate(%g %g %g)" % (-rotation, x, y)
        child(root, "text", attrs).text = content
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)

def png(frame, scale, path):
    import cairo
    width, height, clip, background, primitives, texts = frame
    w, h = math.ceil(width*scale), math.ceil(height*scale)
    if w*h > 64000000: raise ValueError("PNG pixel budget exceeds 64 million")
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h); c = cairo.Context(surface); c.scale(scale,scale)
    c.set_source_rgba(*background); c.paint(); c.save(); c.rectangle(*clip); c.clip()
    c.set_line_join(cairo.LINE_JOIN_ROUND);c.set_line_cap(cairo.LINE_CAP_ROUND)
    for kind, points, color, width_or_marker, dash_or_radius in primitives:
        c.set_source_rgba(*color)
        if kind == "line":
            c.set_line_width(width_or_marker);c.set_dash((6,3) if dash_or_radius==1 else (1,3) if dash_or_radius==2 else ())
            c.move_to(*points[0])
            for point in points[1:]: c.line_to(*point)
            c.stroke()
        else:
            x,y=points;radius=dash_or_radius;c.set_dash(())
            if width_or_marker==2: c.rectangle(x-radius,y-radius,2*radius,2*radius);c.fill()
            elif width_or_marker==3:
                c.set_line_width(1);c.move_to(x-radius,y);c.line_to(x+radius,y);c.move_to(x,y-radius);c.line_to(x,y+radius);c.stroke()
            else: c.arc(x,y,radius,0,2*math.pi);c.fill()
    c.restore();c.set_dash(());c.set_line_width(1);c.set_source_rgb(.514,.576,.647);c.rectangle(*clip);c.stroke()
    for (x,y),content,anchor,rotation,fontsize,color in texts:
        c.save();c.translate(x,y);c.rotate(-math.radians(rotation));c.set_source_rgba(*color);c.select_font_face("sans-serif");c.set_font_size(fontsize)
        xb,yb,tw,th,_,_=c.text_extents(content)
        dx=-xb-tw if "e" in anchor else -xb if "w" in anchor else -xb-tw/2
        dy=-yb if "n" in anchor else -yb-th if "s" in anchor else -yb-th/2
        c.move_to(dx,dy);c.show_text(content);c.restore()
    surface.write_to_png(str(path))

def main():
    source, target, fmt, scale = sys.argv[1:]
    size = Path(source).stat().st_size
    if size > 64*1024*1024: raise ValueError("Snapshot transport exceeds 64 MiB")
    frame = decode(record(Path(source).read_text(encoding="utf-8")))
    if fmt == "svg": Path(target).write_bytes(svg(frame))
    elif fmt == "png":
        scale=float(scale)
        if not math.isfinite(scale) or not .25<=scale<=4: raise ValueError("Invalid PNG scale")
        png(frame,scale,target)
    else: raise ValueError("Unknown output format")

if __name__=="__main__": main()
