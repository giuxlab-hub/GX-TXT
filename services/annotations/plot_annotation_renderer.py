#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Non-destructive raster compositor for Plot Annotation API v1."""
from __future__ import annotations
import argparse, json, math, os, subprocess
from PIL import Image, ImageColor, ImageDraw, ImageFont


def truth(v, default=True):
    if v is None:
        return default
    if isinstance(v, bool):
        return v
    return str(v).lower() in {"1", "true", "yes", "on"}


def color(value, default="#000000", alpha=255):
    s = str(value or "").strip()
    if not s or s.lower() in {"none", "transparent"}:
        return None
    try:
        rgb = ImageColor.getrgb(s)
        if len(rgb) == 4:
            return rgb
        return (*rgb, alpha)
    except Exception:
        rgb = ImageColor.getrgb(default)
        return (*rgb, alpha)


def find_font(family: str, bold=False, italic=False):
    family = (family or "sans").strip()
    candidates = []
    if os.path.isfile(family):
        candidates.append(family)
    if shutil_which("fc-match"):
        pattern = family
        if bold:
            pattern += ":style=Bold"
        if italic:
            pattern += ":slant=italic"
        try:
            p = subprocess.run(["fc-match", "-f", "%{file}", pattern], capture_output=True, text=True, check=False)
            if p.stdout.strip():
                candidates.append(p.stdout.strip())
        except Exception:
            pass
    candidates.extend([
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ])
    return next((p for p in candidates if os.path.isfile(p)), None)


def shutil_which(cmd):
    import shutil
    return shutil.which(cmd)


def font_for(obj, dpi):
    size = float(obj.get("font_size", 12) or 12)
    unit = str(obj.get("font_unit", "pt") or "pt").lower()
    px = size if unit == "px" else size * float(dpi) / 72.0
    px = max(1, int(round(px)))
    path = find_font(str(obj.get("font_family", "sans")), truth(obj.get("bold"), False), truth(obj.get("italic"), False))
    if path:
        try:
            return ImageFont.truetype(path, px)
        except Exception:
            pass
    return ImageFont.load_default()


def xy(obj, keyx, keyy, w, h):
    return float(obj.get(keyx, 0)) * w, (1.0 - float(obj.get(keyy, 0))) * h


def width_px(obj, dpi):
    v = float(obj.get("stroke_width", 1.5) or 1.5)
    if str(obj.get("stroke_unit", "px")).lower() == "pt":
        v = v * dpi / 72.0
    return max(1, int(round(v)))


def dashed_line(draw, p1, p2, fill, width, style="solid"):
    if style in {"", "solid", "none"}:
        draw.line([p1, p2], fill=fill, width=width)
        return
    dash = 8 * width if style == "dashed" else 2 * width
    gap = 5 * width if style == "dashed" else 4 * width
    x1, y1 = p1; x2, y2 = p2
    length = math.hypot(x2-x1, y2-y1)
    if length <= 0:
        return
    ux, uy = (x2-x1)/length, (y2-y1)/length
    pos = 0.0
    while pos < length:
        end = min(length, pos + dash)
        draw.line([(x1+ux*pos, y1+uy*pos), (x1+ux*end, y1+uy*end)], fill=fill, width=width)
        pos = end + gap


def arrow_head(draw, p1, p2, fill, width, kind):
    if kind in {"", "none"}:
        return
    x1,y1=p1; x2,y2=p2
    ang = math.atan2(y2-y1, x2-x1)
    length = max(8.0, width * 5.0)
    spread = math.radians(28)
    a = (x2 - length*math.cos(ang-spread), y2 - length*math.sin(ang-spread))
    b = (x2 - length*math.cos(ang+spread), y2 - length*math.sin(ang+spread))
    if kind == "open":
        draw.line([a,p2,b], fill=fill, width=width)
    else:
        draw.polygon([p2,a,b], fill=fill)


def text_origin(draw, pos, text, font, halign, valign, stroke_width=0):
    bbox = draw.multiline_textbbox((0,0), text, font=font, spacing=2, stroke_width=stroke_width)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    x,y=pos
    if halign == "center": x -= tw/2
    elif halign == "right": x -= tw
    if valign in {"middle","center"}: y -= th/2
    elif valign in {"bottom","baseline"}: y -= th
    return x,y,tw,th


def render(base_path, json_path, out_path, dpi_override=None):
    original = Image.open(base_path)
    preserve_alpha = "A" in original.getbands() or "transparency" in original.info
    base = original.convert("RGBA")
    w,h = base.size
    with open(json_path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    if not truth(doc.get("enabled"), True):
        base.save(out_path)
        return
    dpi = int(dpi_override or (doc.get("canvas") or {}).get("dpi") or 200)
    objects = sorted((o for o in doc.get("objects", []) if isinstance(o,dict)), key=lambda o: float(o.get("z_index",0) or 0))
    layer = Image.new("RGBA", base.size, (0,0,0,0))
    draw = ImageDraw.Draw(layer, "RGBA")
    for obj in objects:
        if not truth(obj.get("visible"), True):
            continue
        if obj.get("space", "figure_norm") != "figure_norm":
            continue
        typ = obj.get("type")
        stroke = color(obj.get("stroke") or obj.get("color") or "#000000")
        sw = width_px(obj, dpi)
        dash = str(obj.get("dash", "solid"))
        if typ in {"line", "arrow"}:
            p1=xy(obj,"x1","y1",w,h); p2=xy(obj,"x2","y2",w,h)
            dashed_line(draw,p1,p2,stroke,sw,dash)
            if typ == "arrow": arrow_head(draw,p1,p2,stroke,sw,str(obj.get("head","triangle")))
        elif typ in {"rectangle","ellipse"}:
            p1=xy(obj,"x1","y1",w,h); p2=xy(obj,"x2","y2",w,h)
            box=[min(p1[0],p2[0]),min(p1[1],p2[1]),max(p1[0],p2[0]),max(p1[1],p2[1])]
            op = int(max(0,min(255,round(float(obj.get("fill_opacity",0) or 0)*255))))
            fill = color(obj.get("fill"), "#FFFFFF", op) if op else None
            if typ == "rectangle": draw.rectangle(box, fill=fill, outline=stroke, width=sw)
            else: draw.ellipse(box, fill=fill, outline=stroke, width=sw)
        elif typ == "text":
            pos=xy(obj,"x","y",w,h)
            txt=str(obj.get("text", ""))
            if not txt: continue
            font=font_for(obj,dpi)
            fg=color(obj.get("color"),"#000000")
            x,y,tw,th=text_origin(draw,pos,txt,font,str(obj.get("h_align","left")),str(obj.get("v_align","middle")))
            bg=color(obj.get("background"),"#FFFFFF",230)
            border=truth(obj.get("border"),False)
            pad=max(2,int(round(font.size*0.18))) if hasattr(font,"size") else 2
            if bg is not None:
                draw.rectangle([x-pad,y-pad,x+tw+pad,y+th+pad], fill=bg, outline=fg if border else None, width=1)
            elif border:
                draw.rectangle([x-pad,y-pad,x+tw+pad,y+th+pad], outline=fg, width=1)
            rotation=float(obj.get("rotation_deg",0) or 0)
            if abs(rotation) < 1e-9:
                draw.multiline_text((x,y),txt,font=font,fill=fg,spacing=2)
            else:
                twi=max(1,int(math.ceil(tw+2*pad))); thi=max(1,int(math.ceil(th+2*pad)))
                txtim=Image.new("RGBA",(twi,thi),(0,0,0,0)); td=ImageDraw.Draw(txtim,"RGBA")
                td.multiline_text((pad,pad),txt,font=font,fill=fg,spacing=2)
                rot=txtim.rotate(-rotation,expand=True,resample=Image.Resampling.BICUBIC)
                layer.alpha_composite(rot,(int(round(pos[0]-rot.width/2)),int(round(pos[1]-rot.height/2))))
    out=Image.alpha_composite(base,layer)
    if not preserve_alpha:
        out=out.convert("RGB")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)),exist_ok=True)
    out.save(out_path, format="PNG", dpi=(dpi,dpi))


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base",required=True); ap.add_argument("--annotations",required=True); ap.add_argument("--output",required=True); ap.add_argument("--dpi",type=int)
    a=ap.parse_args(); render(a.base,a.annotations,a.output,a.dpi); print(a.output)
if __name__ == "__main__": main()
