#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded printing adapter on the common auxiliary process transport."""
from pathlib import Path
import hashlib, json, os, shutil, signal, sys, tempfile, tkinter
FRAMEWORK=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(FRAMEWORK/'core/python'))
from gxtxt_job_supervisor import auxiliary_request_run, request_process_group, tcl_result
request_process_group();signal.signal(signal.SIGTERM,lambda *_:sys.exit(143))
tcl=tkinter.Tcl()
def dictionary(value):
    words=tcl.splitlist(value)
    if len(words)%2: raise ValueError('Malformed inert print dictionary')
    return dict(zip(words[::2],words[1::2]))
def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def verify(data, sources=True):
    pdf=Path(data['pdf'])
    if not pdf.is_file() or digest(pdf)!=data['pdf_sha256']:raise ValueError('PDF changed; update and review the document')
    if sources:verify_sources(data['source_manifest'])
    return pdf

def verify_sources(manifest_path):
    document=json.loads(Path(manifest_path).read_text())
    files=document.get('files',document)
    for name,sha in files.items():
        if sha=='absent:v1':
            if os.path.lexists(name):raise ValueError('Scientific source presentation changed; update and review the document')
            continue
        if not Path(name).is_file() or digest(name)!=sha:raise ValueError('Scientific source changed; update and review the document')
    if document.get('guards'):
        root=Path(manifest_path).parent
        with tempfile.TemporaryDirectory(prefix='.verify-',dir=root) as temporary:
            env={**os.environ,**{key:str(Path(temporary)/key) for key in ('XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','XDG_STATE_HOME','GXTXT_INSTALLATION_ROOT')}}
            run(['tclsh',FRAMEWORK/'core/tcl/print_document_verify.tcl',FRAMEWORK,document['session'],document['guards']],timeout=15,environment=env)

def run(args,timeout=90,max_bytes=2097152,environment=None):
    result=auxiliary_request_run([str(value) for value in args],timeout_seconds=timeout,max_bytes=max_bytes,environment=environment)
    if result['returncode']: raise RuntimeError(result['output'][-12000:] or f'{args[0]} failed')
    return result['output']

def compose(data,root):
    private=root/'worker';private.mkdir()
    env={**os.environ,**{key:str(private/key) for key in ('XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','XDG_STATE_HOME','GXTXT_INSTALLATION_ROOT')}}
    request=root/'request.tcldict';request.write_text(data['payload'],encoding='utf-8')
    materialized=root/'materialized.tcldict'
    run(['tclsh',FRAMEWORK/'core/tcl/print_document_materialize.tcl',FRAMEWORK,data['session'],request,materialized],environment=env)
    if materialized.stat().st_size>33554432:raise ValueError('Frozen print model exceeds 32 MiB')
    raw=dictionary(materialized.read_text());page=dictionary(raw['page'])
    for key in ('rows','columns'):page[key]=int(page[key])
    for key in ('margin_mm','gap_mm'):page[key]=float(page[key])
    page['captions']=bool(tcl.getboolean(page['captions']))
    items=[]
    for value in tcl.splitlist(raw['items']):
        item=dictionary(value)
        if 'frame' in item:
            item['frame']=dictionary(item['frame'])
            for key in ('x_mm','y_mm','width_mm','height_mm'):item['frame'][key]=float(item['frame'][key])
            item['frame']['page']=int(item['frame']['page'])
        if 'style' in item:
            item['style']=dictionary(item['style'])
            for key in ('font_size','padding_mm','border_pt'):
                if key in item['style']:item['style'][key]=float(item['style'][key])
        if item['kind']=='table':
            item['columns']=[dictionary(column) for column in tcl.splitlist(item['columns'])]
            item['rows']=[list(tcl.splitlist(row)) for row in tcl.splitlist(item['rows'])]
            item['source_rows']=list(tcl.splitlist(item['source_rows']))
        if 'pdf_pages' in item:item['pdf_pages']=[int(number) for number in tcl.splitlist(item['pdf_pages'])]
        items.append(item)
    manifest=dictionary(raw['manifest']);source_manifest=root/'source_manifest.json'
    guards=root/'scientific_guards.tcldict'
    # Preserve Tcl's canonical data representation without evaluating source
    # metadata or Python's wantobjects tuple stringification as Tcl code.
    tcl.setvar('_print_guard_datasets',raw['guards']);tcl.setvar('_print_guard_nodes',raw['nodes'])
    guards.write_text(tcl.eval('list datasets $_print_guard_datasets nodes $_print_guard_nodes'),encoding='utf-8')
    source_manifest.write_text(json.dumps(dict(schema='gxtxt.print_sources.v1',files=manifest,session=data['session'],guards=str(guards)),sort_keys=True),encoding='utf-8')
    os.environ['MPLCONFIGDIR']=str(root/'matplotlib')
    from gxtxt_print_document import compose as assemble
    pdf=root/'document.pdf';receipt=assemble(dict(schema=raw['schema'],title=raw['title'],page=page,items=items),pdf)
    qpdf=shutil.which('qpdf')
    if not qpdf:raise RuntimeError('qpdf is required to validate the assembled PDF')
    run([qpdf,'--check',pdf],timeout=30)
    result=dict(pdf=str(pdf),pdf_sha256=digest(pdf),source_manifest=str(source_manifest),page_count=receipt['page_count'],pages=receipt['pages'],notices=receipt['notices'])
    if receipt.get('objects'):
        objects=[];pixel_count=0
        from PIL import Image
        for item in receipt['objects']:
            prefix=Path(item['asset_pdf']).with_suffix('')
            run(['pdftoppm','-f',1,'-l',1,'-singlefile','-scale-to',1200,'-png',item['asset_pdf'],prefix],timeout=30)
            png=prefix.with_suffix('.png')
            with Image.open(png) as image:
                dimensions=list(image.size);pixel_count+=image.width*image.height
            if pixel_count>64000000:raise ValueError('Poster editor object images exceed their bounded 64-megapixel total; reduce objects or split the composition')
            objects.append(dict(item,preview_png=str(png),preview_sha256=digest(png),preview_dimensions=dimensions))
        result['objects']=objects
    verify(result)
    (root/'receipt.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result

def main():
    data=dictionary(sys.stdin.read(10485760));operation=data['operation'];root=Path(data['root']).resolve()
    if not root.is_dir() or root.is_symlink():raise ValueError('CORE managed print allocation required')
    if operation=='compose':return compose(data,root)
    if operation=='media_info':
        from PIL import Image
        source=Path(data['path'])
        if not source.is_file() or source.stat().st_size>67108864 or digest(source)!=data['sha256']:raise ValueError('Original scientific image is unavailable or its SHA changed')
        with Image.open(source) as image:
            frames=getattr(image,'n_frames',1)
            supported=image.mode in ('1','L','LA','P','PA','RGB','RGBA','CMYK') and frames==1 and image.width*image.height<=32000000
            return dict(printable=int(supported),mode=image.mode,frames=frames,width=image.width,height=image.height,reason='' if supported else 'An explicit scientific display/frame projection is required; the metadata synopsis is available.')
    if operation=='source_preview':
        from PIL import Image
        source=Path(data['path']).resolve();analysis=Path(data['session']).resolve()/'analysis'
        if not source.is_relative_to(analysis) or not source.is_file() :raise ValueError('Published Graph source changed')
        stat=source.stat()
        if list(map(int,tcl.splitlist(data['stamp'])))!=[stat.st_size,int(stat.st_mtime),int(stat.st_ctime),stat.st_ino]:raise ValueError('Published Graph source changed')
        if source.suffix.lower()=='.pdf':
            run(['pdftoppm','-f',1,'-l',1,'-singlefile','-scale-to',400,'-png',source,root/'source'],timeout=30)
        else:
            with Image.open(source) as image:
                if image.width*image.height>32000000:raise ValueError('Graph source exceeds 32 megapixels')
                image.thumbnail((400,240));image.convert('RGB').save(root/'source.png')
        return dict(path=str(root/'source.png'))
    pdf=verify(data,sources=operation not in ('page','object_preview','thumbnails'))
    if operation=='object_preview':
        # Reproject already prepared, hash-checked PDF object pixels for a layout
        # draft. No canonical materialization, scientific plot or TeX execution.
        from PIL import Image
        receipt=json.loads((pdf.parent/'receipt.json').read_text())
        if receipt.get('pdf_sha256')!=data['pdf_sha256']:raise ValueError('Object assets belong to another PDF revision')
        requested=tcl.splitlist(data['objects'])
        if not 1<=len(requested)<=200:raise ValueError('Object Preview requires 1 to 200 objects')
        available={item['id']:item for item in receipt.get('objects',[])}
        result=[];seen=set();total_pixels=0
        for raw in requested:
            item=dictionary(raw);identifier=item['id'];w=int(item['width']);h=int(item['height'])
            if identifier not in available or identifier in seen or not 1<=w<=6000 or not 1<=h<=6000:raise ValueError('Invalid object Preview identity or dimensions')
            seen.add(identifier);total_pixels+=w*h
            if total_pixels>64000000:raise ValueError('Object Preview exceeds 64 megapixels')
            asset=available[identifier];source=Path(asset['preview_png'])
            if not source.resolve().is_relative_to(pdf.parent/'objects') or digest(source)!=asset['preview_sha256']:raise ValueError('Prepared object pixels changed')
            destination=root/(identifier+'.png')
            with Image.open(source) as image:image.resize((w,h),Image.Resampling.LANCZOS).save(destination)
            result.append(dict(id=identifier,path=str(destination),width=w,height=h,sha256=digest(destination),asset_key=asset['asset_key']))
        return dict(objects=result,pdf_sha256=data['pdf_sha256'],projection='prepared_object_layout_draft')
    if operation=='verify':return dict(status='verified',pdf_sha256=data['pdf_sha256'])
    if operation=='thumbnails':
        count=int(data['page_count'])
        if not 1<=count<=200:raise ValueError('Invalid thumbnail page count')
        run(['pdftoppm','-f',1,'-l',count,'-scale-to',120,'-png',pdf,root/'thumb'],timeout=60)
        paths=sorted(root.glob('thumb-*.png'),key=lambda path:int(path.stem.rsplit('-',1)[1]))
        if len(paths)!=count:raise ValueError('Thumbnail count differs from validated PDF')
        return dict(paths=[str(path) for path in paths],pdf_sha256=data['pdf_sha256'])
    if operation=='page':
        page=int(data['page']);width=int(data['width']);count=int(data['page_count'])
        if not 1<=page<=count<=200 or not 200<=width<=3000:raise ValueError('Invalid page Preview projection')
        prefix=root/'page'
        run(['pdftoppm','-f',page,'-l',page,'-singlefile','-scale-to-x',width,'-scale-to-y',-1,'-png',pdf,prefix],timeout=30)
        from PIL import Image
        with Image.open(str(prefix)+'.png') as image:
            if image.width*image.height>16000000:raise ValueError('Page Preview exceeds 16 megapixels')
            dimensions=[image.width,image.height]
        result=dict(path=str(prefix)+'.png',page=page,width=dimensions[0],height=dimensions[1],pdf_sha256=data['pdf_sha256'])
        receipt_path=pdf.parent/'receipt.json'
        if receipt_path.is_file():
            receipt=json.loads(receipt_path.read_text())
            if receipt.get('pdf_sha256')!=data['pdf_sha256']:raise ValueError('Object asset receipt belongs to another PDF revision')
            objects=[];total_pixels=0
            from pypdf import PdfReader
            paper_mm=float(PdfReader(pdf).pages[page-1].mediabox.width)*25.4/72
            for item in receipt.get('objects',[]):
                if int(item['frame']['page'])!=page:continue
                source=Path(item['preview_png'])
                if not source.resolve().is_relative_to(pdf.parent/'objects') or digest(source)!=item['preview_sha256']:raise ValueError('Owned poster object image changed')
                w=max(1,round(item['frame']['width_mm']*dimensions[0]/paper_mm));h=max(1,round(item['frame']['height_mm']*dimensions[0]/paper_mm))
                total_pixels+=w*h
                if total_pixels>64000000:raise ValueError('Visible poster object images exceed 64 megapixels')
                destination=root/(item['id']+'.png')
                with Image.open(source) as image:image.resize((w,h),Image.Resampling.LANCZOS).save(destination)
                objects.append(dict(id=item['id'],path=str(destination),asset_key=item['asset_key'],frame=item['frame'],width=w,height=h))
            result['objects']=objects
        return result
    if operation=='export':
        target=Path(data['destination'])
        if not target.is_absolute() or target.is_symlink() or target.suffix.lower()!='.pdf':raise ValueError('Choose a regular absolute PDF destination')
        if target.resolve().is_relative_to(Path(data['session']).resolve()/'datasets') or target.resolve().is_relative_to(Path(data['session']).resolve()/'analysis'):raise ValueError('Choose a report/export folder outside scientific source directories')
        target.parent.mkdir(parents=True,exist_ok=True)
        env={**os.environ,**{key:str(root/key) for key in ('XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','XDG_STATE_HOME','GXTXT_INSTALLATION_ROOT')}}
        run(['tclsh',FRAMEWORK/'core/tcl/print_document_promote.tcl',FRAMEWORK,pdf,target,data['pdf_sha256'],'replace' if data.get('replace','0')=='1' else 'create_only'],environment=env)
        return dict(path=str(target),pdf_sha256=digest(target),status='exported')
    raise ValueError('Unknown print document operation')
if __name__=='__main__':
    try:print(tcl_result(dict(ok=1,result=main())))
    except Exception as exc:print(tcl_result(dict(ok=0,error=str(exc),category='print_document')));sys.exit(1)
