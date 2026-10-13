#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Server-side PDF compositor for GX-TXT plots."""
from __future__ import annotations
import argparse
from pathlib import Path
import math
import sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.image as mpimg
from matplotlib.backends.backend_agg import RendererAgg
from matplotlib.font_manager import FontProperties

PAGES_MM = {'A4': (210.0,297.0), 'A3': (297.0,420.0), 'LETTER': (215.9,279.4)}


def compose_text(a, width_mm, height_mm):
    """Paginate complete UTF-8 text using the same PDF and host page settings."""
    matplotlib.rcParams['pdf.fonttype'] = 42
    text = (sys.stdin.buffer.read().decode('utf-8') if a.text_input == '-'
            else Path(a.text_input).read_text(encoding='utf-8'))
    dpi = 100
    font = FontProperties(family='DejaVu Sans', size=10)
    renderer = RendererAgg(1, 1, dpi)
    available = (width_mm - 2 * a.margin_mm) / 25.4 * dpi
    if available <= 0 or height_mm <= 2 * a.margin_mm + 20:
        raise ValueError('Page margins leave no printable text area')
    lines = []
    for paragraph in text.split('\n'):
        if not paragraph:
            lines.append('')
            continue
        remaining = paragraph
        while remaining:
            low, high = 1, min(32, len(remaining))
            while high < len(remaining) and renderer.get_text_width_height_descent(remaining[:high], font, False)[0] <= available:
                low = high
                high = min(2 * high, len(remaining))
            while low < high:
                middle = (low + high + 1) // 2
                if renderer.get_text_width_height_descent(remaining[:middle], font, False)[0] <= available:
                    low = middle
                else:
                    high = middle - 1
            end = low
            if end < len(remaining):
                space = remaining.rfind(' ', 0, end + 1)
                if space > 0:
                    end = space + 1
            lines.append(remaining[:end])
            remaining = remaining[end:]
    line_mm = 14 * 25.4 / 72
    per_page = max(1, math.floor((height_mm - 2 * a.margin_mm - 12) / line_mm))
    count = max(1, math.ceil(len(lines) / per_page))
    with PdfPages(a.output) as pdf:
        for first in range(0, max(1, len(lines)), per_page):
            fig = plt.figure(figsize=(width_mm / 25.4, height_mm / 25.4))
            for row, line in enumerate(lines[first:first + per_page]):
                fig.text(a.margin_mm / width_mm,
                         1 - (a.margin_mm + (row + 1) * line_mm) / height_mm,
                         line, fontproperties=font, va='baseline')
            fig.text(.5, a.margin_mm / height_mm, f'{first // per_page + 1} / {count}',
                     ha='center', fontsize=8)
            pdf.savefig(fig)
            plt.close(fig)
    print(f'PDF created: {a.output} ({count} pages; complete UTF-8 text)')


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',required=True)
    ap.add_argument('--page',default='A4',choices=PAGES_MM)
    ap.add_argument('--orientation',default='portrait',choices=['portrait','landscape'])
    ap.add_argument('--rows',type=int,default=2)
    ap.add_argument('--cols',type=int,default=2)
    ap.add_argument('--margin-mm',type=float,default=10.0)
    ap.add_argument('--gap-mm',type=float,default=5.0)
    ap.add_argument('--title',default='')
    ap.add_argument('--captions',type=int,default=1)
    ap.add_argument('--text-input', help='UTF-8 document path, or - for stdin; separate from plot images')
    ap.add_argument('images',nargs='*')
    a=ap.parse_args()
    if a.rows<1 or a.cols<1: raise SystemExit('rows/cols devono essere >=1')
    w,h=PAGES_MM[a.page]
    if a.orientation=='landscape': w,h=h,w
    if a.text_input:
        if a.images:
            raise SystemExit('Choose text input or plot images separately')
        compose_text(a, w, h)
        return
    if not a.images:
        raise SystemExit('Select plot images or a UTF-8 text document')
    fw,fh=w/25.4,h/25.4
    out=Path(a.output); out.parent.mkdir(parents=True,exist_ok=True)
    per=a.rows*a.cols
    imgs=[Path(x) for x in a.images]
    with PdfPages(out) as pdf:
        for p0 in range(0,len(imgs),per):
            page=imgs[p0:p0+per]
            fig,axes=plt.subplots(a.rows,a.cols,figsize=(fw,fh),squeeze=False)
            if a.title:
                fig.suptitle(a.title,fontsize=11)
            left=a.margin_mm/w; right=1-a.margin_mm/w
            bottom=a.margin_mm/h; top=1-a.margin_mm/h
            if a.title: top-=0.025
            wg=a.gap_mm/w; hg=a.gap_mm/h
            fig.subplots_adjust(left=left,right=right,bottom=bottom,top=top,wspace=wg*5,hspace=hg*5)
            flat=[ax for row in axes for ax in row]
            for ax in flat: ax.axis('off')
            for ax,path in zip(flat,page):
                im=mpimg.imread(path)
                ax.imshow(im)
                ax.axis('off')
                if a.captions:
                    ax.set_title(path.stem,fontsize=7,pad=2)
            pdf.savefig(fig)
            plt.close(fig)
    print(f'PDF creato: {out} ({math.ceil(len(imgs)/per)} pagine)')

if __name__=='__main__': main()
