# SPDX-License-Identifier: GPL-3.0-or-later
"""Mixed document assembly extension of the existing PDF compositor.

Inputs are frozen by the CORE printing/Dataset/Graph authorities. Source
thumbnails are never accepted as scientific print assets. Matplotlib retains
its existing text/image PDF role; pypdf preserves original inserted PDF vectors.
"""
from pathlib import Path
from io import BytesIO
import copy, hashlib, json, math, tempfile
import matplotlib
matplotlib.use('Agg')
from matplotlib import pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.backends.backend_agg import RendererAgg
from matplotlib.font_manager import FontProperties, findfont
from matplotlib.ft2font import FT2Font
from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation

PAPERS={'A4':(210.,297.),'A3':(297.,420.),'LETTER':(215.9,279.4)}
PT=72/25.4
matplotlib.rcParams['pdf.fonttype']=42
matplotlib.rcParams['text.usetex']=False
matplotlib.rcParams['axes.formatter.use_mathtext']=False
_renderer=RendererAgg(1,1,100)
_glyphs=FT2Font(findfont(FontProperties(family='DejaVu Sans'))).get_charmap()

def wrap(value, width_mm, size=8):
    text=str(value)
    missing=sorted({ord(character) for character in text if character not in '\n\r\t' and ord(character) not in _glyphs})
    if missing: raise ValueError('Print font cannot represent '+', '.join(f'U+{point:04X}' for point in missing[:12]))
    available=width_mm/25.4*100; font=FontProperties(family='DejaVu Sans',size=size)
    if available<=0: raise ValueError('No printable text width remains')
    lines=[]
    for paragraph in text.expandtabs(4).replace('\r\n','\n').replace('\r','\n').split('\n'):
        if not paragraph: lines.append('');continue
        while paragraph:
            low, high=1,len(paragraph)
            while low<high:
                middle=(low+high+1)//2
                if _renderer.get_text_width_height_descent(paragraph[:middle],font,False)[0]<=available: low=middle
                else: high=middle-1
            end=low
            if end<len(paragraph):
                space=paragraph.rfind(' ',0,end+1)
                if space>0: end=space+1
            lines.append(paragraph[:end]);paragraph=paragraph[end:]
    return lines

def text_at(figure,x_mm,y_mm,text,width_mm,height_mm,size=8,**options):
    figure.text(x_mm/width_mm,1-y_mm/height_mm,str(text),fontsize=size,
                fontfamily='DejaVu Sans',va='top',parse_math=False,**options)

def figure(width,height,background='white'):
    return plt.figure(figsize=(width/25.4,height/25.4),facecolor=background)

def table_pdf(item, path, width, height, margin):
    columns=item['columns']; rows=item['rows']; source_rows=item['source_rows']
    if not columns: raise ValueError('Print table has no explicitly selected columns')
    if len(rows)!=len(source_rows): raise ValueError('Print source-row identity count differs')
    if any(len(row)!=len(columns) for row in rows): raise ValueError('Print table row width differs from its declared schema')
    framed=item.get('_poster_frame',False);style=item.get('style',{})
    size=float(style.get('font_size',8)) if framed else 8
    line_mm=size*1.35/PT if framed else 3.8
    usable=width-2*margin; row_number_width=min(22.,max(12.,usable*.16)) if framed else 22.
    per_band=len(columns) if framed else max(1,math.floor((usable-row_number_width)/24))
    if usable<(24 if framed else 48) or height-2*margin<(12 if framed else 65): raise ValueError('Object/page leaves no legible table area')
    page_count=0
    caption_size=size if framed else 9
    caption_lines=wrap(item['caption'],usable,caption_size) if item['caption'] else []
    if len(caption_lines)>6: raise ValueError('Table caption requires a shorter title or wider page')
    heading_top=margin+len(caption_lines)*line_mm+(line_mm if caption_lines else 0) if framed else margin+12+len(caption_lines)*4+7
    with PdfPages(path) as pdf:
        for first in range(0,len(columns),per_band):
            band=columns[first:first+per_band];cell_width=(usable-row_number_width)/len(band)
            headings=['Source row\n(0-based)']
            for column in band:
                label=str(column.get('label') or column['variable_id'])
                if label!=column['variable_id']: label+=' · '+column['variable_id']
                headings.append(label+(f"\n[{column['unit']}]" if column.get('unit') else ''))
            widths=[row_number_width]+[cell_width]*len(band)
            wrapped_headers=[wrap(value,w-2,size) for value,w in zip(headings,widths)]
            header_height=max(map(len,wrapped_headers))*line_mm+3
            bottom_limit=height-(margin if framed else max(margin,10))
            if heading_top+header_height+8>bottom_limit: raise ValueError('Table headings leave no printable data area')
            position=0
            while position<len(rows) or (position==0 and not rows):
                page_count+=1
                if framed and page_count>1: raise ValueError(f"Poster table {item['id']} overflows its frame: enlarge it, reduce its explicit row range or choose a readable smaller font")
                if page_count>200: raise ValueError('Table exceeds the 200-page print limit; choose a smaller explicit row/column range')
                fig=figure(width,height,style.get('background','white') if framed else 'white')
                color=style.get('foreground','#000000') if framed else '#000000'
                text_at(fig,margin,margin if framed else margin+12,'\n'.join(caption_lines),width,height,caption_size,color=color)
                if not framed:text_at(fig,margin,heading_top-5,f"Dataset {item['source_id']} · columns {first+1}–{first+len(band)} of {len(columns)}",width,height,7)
                y=heading_top;x=margin
                for lines,w in zip(wrapped_headers,widths):
                    text_at(fig,x+1,y,'\n'.join(lines),width,height,size,weight='bold',color=color);x+=w
                y+=header_height
                while position<len(rows):
                    values=[source_rows[position]]+rows[position][first:first+len(band)]
                    wrapped=[wrap(value,w-2,size) for value,w in zip(values,widths)]
                    row_height=max(map(len,wrapped))*line_mm+2
                    if row_height>(bottom_limit-heading_top-header_height if framed else height-2*margin-30): raise ValueError('A table cell exceeds its printable frame/page; choose a wider column projection')
                    if y+row_height>bottom_limit: break
                    x=margin
                    for lines,w in zip(wrapped,widths):
                        text_at(fig,x+1,y,'\n'.join(lines),width,height,size,color=color);x+=w
                    y+=row_height;position+=1
                pdf.savefig(fig);plt.close(fig)
                if not rows: break
    return page_count

def text_pdf(item,path,width,height,margin):
    framed=item.get('_poster_frame',False);style=item.get('style',{})
    size=float(style.get('font_size',10)) if framed else 10
    text=item['text'];lines=wrap(text,width-2*margin,size)
    line_mm=size*1.4/PT
    caption_size=size if framed else 9
    caption_lines=wrap(item['caption'],width-2*margin,caption_size) if item['caption'] else []
    if len(caption_lines)>6: raise ValueError('Text caption requires a shorter title or wider page')
    body_top=margin+(len(caption_lines)+1)*line_mm if framed and caption_lines else margin if framed else margin+12+len(caption_lines)*4+4
    per_page=math.floor((height-(margin if framed else max(margin,10))-body_top)/line_mm)
    if per_page<1: raise ValueError('Page margins leave no printable text area')
    count=max(1,math.ceil(len(lines)/per_page))
    if framed and count>1: raise ValueError(f"Poster text {item['id']} overflows its frame: enlarge it, shorten the text or choose a readable smaller font")
    if count>200: raise ValueError('Text exceeds the 200-page print limit')
    with PdfPages(path) as pdf:
        for first in range(0,max(1,len(lines)),per_page):
            fig=figure(width,height,style.get('background','white') if framed else 'white')
            color=style.get('foreground','#000000') if framed else '#000000'
            text_at(fig,margin,margin if framed else margin+12,'\n'.join(caption_lines),width,height,caption_size,color=color)
            for row,line in enumerate(lines[first:first+per_page]):
                align=style.get('align','left') if framed else 'left'
                x={'left':margin,'center':width/2,'right':width-margin}[align]
                text_at(fig,x,body_top+row*line_mm,line,width,height,size,color=color,weight=style.get('weight','normal') if framed else 'normal',ha=align)
            pdf.savefig(fig);plt.close(fig)

def image_pdf(item,path):
    source=Path(item['path'])
    with Image.open(source) as opened:
        if opened.width*opened.height>32000000: raise ValueError('Original image exceeds the bounded 32-megapixel print limit')
        if opened.mode not in ('1','L','LA','P','PA','RGB','RGBA','CMYK'):
            raise ValueError('Scientific high-bit/float image needs an explicitly accepted display projection; choose the metadata synopsis instead of silently clipping intensities')
        if getattr(opened,'n_frames',1)>1:
            raise ValueError('Multi-frame image needs an explicit accepted frame projection; choose the metadata synopsis')
        pixels=opened.convert('RGBA')
        width,height=pixels.size
        fig=plt.figure(figsize=(width/100,height/100),dpi=100)
        axes=fig.add_axes([0,0,1,1]);axes.imshow(pixels,interpolation='none');axes.set_axis_off()
        with PdfPages(path) as pdf: pdf.savefig(fig,dpi=100)
        plt.close(fig)
    return width,height

def page_overlay(width,height,title,number,total,captions=()):
    buffer=BytesIO();fig=figure(width,height)
    title_lines=wrap(title,width-16,9)
    if len(title_lines)>2: raise ValueError('Document title exceeds the two-line page header')
    text_at(fig,8,4,'\n'.join(title_lines),width,height,9)
    for x,y,text in captions: text_at(fig,x,y,text,width,height,8)
    fig.text(.5,4/height,f'{number} / {total}',ha='center',va='bottom',fontsize=8,fontfamily='DejaVu Sans',parse_math=False)
    with PdfPages(buffer) as pdf: pdf.savefig(fig,transparent=True)
    plt.close(fig);buffer.seek(0)
    return PdfReader(buffer).pages[0]

def _poster_asset(item,assets):
    """One physical frame; its exact PDF also supplies the editor's pixels."""
    frame=item['frame'];width,height=frame['width_mm'],frame['height_mm']
    style=item.get('style',{});padding=float(style.get('padding_mm',2))
    if 2*padding>=min(width,height):raise ValueError(f"Object {item['id']} padding leaves no content area")
    kind=item['kind'];raw=assets/(item['id']+'-content.pdf')
    full_frame=kind in ('table','text','metadata','annotation')
    pixels=None
    if full_frame:
        framed=dict(item,_poster_frame=True)
        if kind=='table':table_pdf(framed,raw,width,height,padding)
        else:text_pdf(framed,raw,width,height,padding)
    elif kind=='image':pixels=image_pdf(item,raw)
    elif kind in ('pdf','graph','xy'):raw=Path(item['path'])
    elif kind not in ('box','separator'):raise ValueError(f'Unsupported poster object: {kind}')
    caption=[] if full_frame or kind in ('box','separator') else wrap(item.get('caption',''),width-2*padding,float(style.get('font_size',8)))
    line_mm=float(style.get('font_size',8))*1.4/PT
    caption_height=len(caption)*line_mm+(line_mm*.5 if caption else 0)
    available_width=width-2*padding;available_height=height-2*padding-caption_height
    if min(available_width,available_height)<=0:raise ValueError(f"Object {item['id']} caption leaves no content area")
    fig=figure(width,height,style.get('background','#ffffff'))
    if caption:text_at(fig,padding,padding,'\n'.join(caption),width,height,float(style.get('font_size',8)),color=style.get('foreground','#000000'))
    if kind=='separator':
        from matplotlib.lines import Line2D
        fig.add_artist(Line2D([padding/width,1-padding/width],[.5,.5],transform=fig.transFigure,color=style.get('foreground','#000000'),linewidth=max(.5,float(style.get('border_pt',1)))))
    background=BytesIO()
    with PdfPages(background) as pdf:pdf.savefig(fig)
    plt.close(fig);background.seek(0)
    writer=PdfWriter();target=writer.add_page(PdfReader(background).pages[0])
    ppi=None
    if kind not in ('box','separator'):
        reader=PdfReader(raw)
        if reader.is_encrypted:raise ValueError('Encrypted PDFs require an explicitly decrypted authorized source')
        chosen=item.get('pdf_pages') or ([1] if len(reader.pages)==1 else [])
        if len(chosen)!=1:raise ValueError(f"Poster object {item['id']} requires exactly one explicit PDF page; insert additional pages as separate objects")
        number=int(chosen[0])
        if not 1<=number<=len(reader.pages):raise ValueError('Selected PDF page is outside its source')
        source=copy.copy(reader.pages[number-1])
        if source.rotation:source.transfer_rotation_to_content()
        box=source.cropbox;sw,sh=float(box.width),float(box.height)
        if min(sw,sh)<=0:raise ValueError('Source PDF has invalid page dimensions')
        aw,ah=(width,height) if full_frame else (available_width,available_height)
        scale=min(aw*PT/sw,ah*PT/sh)
        left=((width-aw)/2)*PT+(aw*PT-sw*scale)/2
        top=0 if full_frame else padding+caption_height
        bottom=(height-top-ah)*PT+(ah*PT-sh*scale)/2
        target.merge_transformed_page(source,Transformation().translate(-float(box.left),-float(box.bottom)).scale(scale).translate(left,bottom),over=True,expand=False)
        if pixels:ppi=pixels[0]/(sw*scale/72)
    border=float(style.get('border_pt',0))
    if border:
        from matplotlib.patches import Rectangle
        overlay=BytesIO();fig=figure(width,height)
        inset=border/2/PT
        fig.add_artist(Rectangle((inset/width,inset/height),1-2*inset/width,1-2*inset/height,transform=fig.transFigure,fill=False,edgecolor=style.get('border','#000000'),linewidth=border))
        with PdfPages(overlay) as pdf:pdf.savefig(fig,transparent=True)
        plt.close(fig);overlay.seek(0);target.merge_page(PdfReader(overlay).pages[0],over=True)
    destination=assets/(item['id']+'.pdf')
    with destination.open('xb') as stream:writer.write(stream)
    return destination,ppi,pixels

def _compose_poster(document,output,assets,width,height):
    items=document['items']
    if not items:raise ValueError('Add at least one poster object')
    count=max(int(item['frame']['page']) for item in items)
    if not 1<=count<=200:raise ValueError('Poster exceeds the 200-page limit')
    writer=PdfWriter();records=[];objects=[];notices=[]
    for page in range(1,count+1):
        buffer=BytesIO();fig=figure(width,height,document['page'].get('background','#ffffff'))
        with PdfPages(buffer) as pdf:pdf.savefig(fig)
        plt.close(fig);buffer.seek(0)
        writer.add_page(PdfReader(buffer).pages[0])
        records.append(dict(width_pt=width*PT,height_pt=height*PT,items=[]))
    for item in items:
        frame=item['frame'];x,y,w,h=[float(frame[key]) for key in ('x_mm','y_mm','width_mm','height_mm')]
        if not all(math.isfinite(value) for value in (x,y,w,h)) or min(x,y)<0 or min(w,h)<1 or x+w>width+1e-7 or y+h>height+1e-7:raise ValueError(f"Invalid physical poster frame for {item['id']}")
        asset,ppi,pixels=_poster_asset(item,assets)
        source=PdfReader(asset).pages[0];page=int(frame['page'])
        writer.pages[page-1].merge_translated_page(source,x*PT,(height-y-h)*PT,over=True,expand=False)
        records[page-1]['items'].append(item['id'])
        fingerprint={key:value for key,value in item.items() if key not in ('frame','path')}
        fingerprint['size_mm']=[w,h]
        if item.get('path'):
            with Path(item['path']).open('rb') as stream:fingerprint['source_asset_sha256']=hashlib.file_digest(stream,'sha256').hexdigest()
        key=hashlib.sha256(json.dumps(fingerprint,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        with asset.open('rb') as stream:sha=hashlib.file_digest(stream,'sha256').hexdigest()
        objects.append(dict(id=item['id'],frame=frame,asset_key=key,asset_pdf=str(asset),asset_sha256=sha,source_id=item.get('source_id',''),caption=item.get('caption','')))
        if ppi is not None and ppi<100:notices.append(dict(item_id=item['id'],message='Original raster resolution is limited at the chosen physical size',effective_ppi=round(ppi,1),source_pixels=pixels))
    output=Path(output)
    writer.add_metadata({'/Title':document['title'],'/Creator':'GX-TXT Print Studio','/Subject':'Editable poster composition; exact source-derived object assets retained'})
    with output.open('xb') as stream:writer.write(stream)
    if output.stat().st_size>100663296:raise ValueError('Generated PDF exceeds its 96 MiB limit')
    if len(PdfReader(output).pages)!=count:raise ValueError('Poster page verification differs from its model')
    return dict(schema='gxtxt.print_pdf_receipt.v1',page_count=count,pages=records,notices=notices,objects=objects)

def _compose(document, output, assets):
    if document.get('schema')!='gxtxt.print_materialized.v1': raise ValueError('Unknown materialized print schema')
    page=document['page'];width,height=PAPERS[page['paper']]
    if page['orientation']=='landscape': width,height=height,width
    if page.get('layout_mode','grid')=='poster':return _compose_poster(document,output,assets,width,height)
    margin=float(page['margin_mm']);gap=float(page['gap_mm'])
    rows,cols=int(page['rows']),int(page['columns'])
    if not 1<=rows<=4 or not 1<=cols<=4: raise ValueError('Invalid print N-up grid')
    if width-2*margin<=30 or height-2*margin<=30: raise ValueError('Margins leave no printable area')
    output=Path(output);output.parent.mkdir(parents=True,exist_ok=True)
    if output.exists(): raise FileExistsError('Refusing an existing managed PDF destination')
    writer=PdfWriter();records=[];pending=[];notices=[]
    def append_record(target,ids):
        if len(writer.pages)>200: raise ValueError('Composition exceeds its 200-page limit')
        records.append(dict(width_pt=float(target.mediabox.width),height_pt=float(target.mediabox.height),items=ids))
    def flush():
        nonlocal pending
        if not pending: return
        cell_width=(width-2*margin-(cols-1)*gap)/cols
        top_margin=max(margin,8);bottom_margin=max(margin,8)
        cell_height=(height-top_margin-bottom_margin-8-(rows-1)*gap)/rows
        if min(cell_width,cell_height)<25: raise ValueError('The selected N-up grid leaves no legible artwork area')
        per=rows*cols
        for first in range(0,len(pending),per):
            target=writer.add_blank_page(width*PT,height*PT);captions=[];ids=[]
            for slot,(item,source) in enumerate(pending[first:first+per]):
                row,col=divmod(slot,cols);x=margin+col*(cell_width+gap);top=top_margin+8+row*(cell_height+gap)
                caption_lines=wrap(item['caption'],cell_width,8) if page['captions'] else []
                if len(caption_lines)>6: raise ValueError('Caption is too long for the selected N-up cell')
                caption_height=len(caption_lines)*3.8+2 if caption_lines else 0
                if caption_lines: captions.append((x,top,'\n'.join(caption_lines)))
                available_height=cell_height-caption_height
                source=copy.copy(source)
                if source.rotation: source.transfer_rotation_to_content()
                box=source.cropbox;sw=float(box.width);sh=float(box.height)
                if min(sw,sh)<=0: raise ValueError('Source PDF has invalid page dimensions')
                scale=min(cell_width*PT/sw,available_height*PT/sh)
                if item.get('source_pixels'):
                    ppi=item['source_pixels'][0]/(sw*scale/72)
                    if ppi<100 and not any(note.get('item_id')==item['id'] for note in notices):
                        notices.append(dict(item_id=item['id'],message='Original raster resolution is limited at the chosen physical size',effective_ppi=round(ppi,1),source_pixels=item['source_pixels']))
                left=x*PT+(cell_width*PT-sw*scale)/2
                bottom=(height-top-caption_height-available_height)*PT+(available_height*PT-sh*scale)/2
                transform=Transformation().translate(-float(box.left),-float(box.bottom)).scale(scale).translate(left,bottom)
                target.merge_transformed_page(source,transform,over=True,expand=False)
                ids.append(item['id'])
            append_record(target,ids)
            records[-1]['captions']=captions
        pending=[]
    for item in document['items']:
        kind=item['kind'];temporary=assets/(item['id']+'.pdf')
        if kind in ('table','text','metadata'):
            flush()
            if kind=='table': table_pdf(item,temporary,width,height,margin)
            else: text_pdf(item,temporary,width,height,margin)
            for source in PdfReader(temporary).pages:
                target=writer.add_page(source);append_record(target,[item['id']])
        else:
            if kind=='image':
                pixels=image_pdf(item,temporary);source_path=temporary;item=dict(item,source_pixels=pixels)
            elif kind in ('pdf','graph','xy'): source_path=Path(item['path'])
            else: raise ValueError(f'Unsupported materialized print representation: {kind}')
            reader=PdfReader(source_path)
            if reader.is_encrypted: raise ValueError('Encrypted PDFs require an explicitly decrypted authorized source')
            chosen=item.get('pdf_pages') or list(range(1,len(reader.pages)+1))
            if len(chosen)>200: raise ValueError('Choose an explicit PDF range within the 200-page limit')
            for number in chosen:
                if not 1<=int(number)<=len(reader.pages): raise ValueError('Selected PDF page is outside its original document')
                pending.append((item,reader.pages[int(number)-1]))
    flush()
    if not writer.pages: raise ValueError('Choose at least one supported print item')
    for index,target in enumerate(writer.pages):
        target.merge_page(page_overlay(width,height,document['title'],index+1,len(writer.pages),records[index].pop('captions',())),over=True)
    writer.add_metadata({'/Title':document['title'],'/Creator':'GX-TXT Print Studio','/Subject':'Frozen scientific print composition; source identities retained in the receipt'})
    with output.open('xb') as stream: writer.write(stream)
    if output.stat().st_size>100663296: raise ValueError('Generated PDF exceeds its 96 MiB limit')
    verified=PdfReader(output)
    if len(verified.pages)!=len(records): raise ValueError('PDF page verification differs from the assembled model')
    return dict(schema='gxtxt.print_pdf_receipt.v1',page_count=len(records),pages=records,notices=notices)

def compose(document, output):
    output=Path(output);output.parent.mkdir(parents=True,exist_ok=True)
    if output.exists(): raise FileExistsError('Refusing an existing managed PDF destination')
    if document.get('page',{}).get('layout_mode','grid')=='poster':
        assets=output.parent/'objects';assets.mkdir()
        return _compose(document,output,assets)
    with tempfile.TemporaryDirectory(prefix='.gxtxt-print-assets-',dir=output.parent) as scratch:
        return _compose(document,output,Path(scratch))
