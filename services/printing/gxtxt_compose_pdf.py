#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Server-side PDF compositor for GX-TXT plots."""
from __future__ import annotations
import argparse
from pathlib import Path
import math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.image as mpimg

PAGES_MM = {'A4': (210.0,297.0), 'A3': (297.0,420.0), 'LETTER': (215.9,279.4)}


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
    ap.add_argument('images',nargs='+')
    a=ap.parse_args()
    if a.rows<1 or a.cols<1: raise SystemExit('rows/cols devono essere >=1')
    w,h=PAGES_MM[a.page]
    if a.orientation=='landscape': w,h=h,w
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
