# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded project-owned icon admission for the existing Viewer design owner."""
import base64, hashlib, json, os, re, resource, struct, subprocess, sys, zlib
from pathlib import Path
import xml.etree.ElementTree as ET
import tkinter
sys.path.insert(0,str(Path(__file__).resolve().parent))
from gxtxt_job_supervisor import tcl_result
LIMIT=262144
def sha(data):return hashlib.sha256(data).hexdigest()
def shared_catalog():
    """Discover only the fixed, distributed original icon library; no caller path."""
    root=Path(__file__).absolute().parents[1]/'assets/icons'
    manifest=root/'catalog.json'
    if root.resolve()!=root or manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_nlink!=1 or manifest.stat().st_size>65536:
        raise ValueError('Shared icon catalog must be an ordinary bounded CORE resource')
    spec=json.loads(manifest.read_text(encoding='utf-8'))
    if set(spec)!={'schema','icons'} or spec['schema']!='gxtxt.viewer_shared_icons.v1' or not isinstance(spec['icons'],list) or not 1<=len(spec['icons'])<=64:
        raise ValueError('Invalid shared icon catalog schema/bound')
    rows={};sources=set()
    for entry in spec['icons']:
        if not isinstance(entry,dict) or set(entry)!={'id','title','category','license','source'}:
            raise ValueError('Shared icon fields differ')
        identifier=entry['id'];name=entry['source']
        if not isinstance(identifier,str) or not re.fullmatch(r'[a-z][a-z0-9_]{0,63}',identifier) or identifier in rows or not isinstance(name,str) or not re.fullmatch(r'[a-z][a-z0-9_]{0,63}\.(svg|png)',name) or name in sources:
            raise ValueError('Invalid/duplicate shared icon identity/source')
        for key in ('title','category','license'):
            value=entry[key]
            if not isinstance(value,str) or not value.strip() or len(value)>200 or any(ord(c)<32 for c in value):
                raise ValueError('Shared icon provenance must be bounded single-line text')
        path=root/name
        if path.is_symlink() or path.resolve()!=path or not path.is_file() or path.stat().st_nlink!=1 or path.stat().st_size>LIMIT:
            raise ValueError('Shared icon source must be an ordinary bounded CORE asset')
        data=path.read_bytes();fmt=path.suffix[1:]
        if fmt=='svg':
            node=ET.fromstring(svg(data));width=int(node.get('width').removesuffix('px'));height=int(node.get('height').removesuffix('px'))
        else:width,height,_=png(data)
        rows[identifier]=dict(id=identifier,title=entry['title'],category=entry['category'],license=entry['license'],path=str(path),sha256=sha(data),source_format=fmt,width=width,height=height)
        sources.add(name)
    return dict(schema=spec['schema'],icons={key:rows[key] for key in sorted(rows)},count=len(rows),authority='Fixed CORE icon resources; discovery grants no filesystem reader')
def png(data, *, max_bytes=LIMIT, max_dimension=512, capture_metadata=False):
    if len(data)>max_bytes or data[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('Only bounded genuine PNG images are accepted')
    pos=8;chunks=[];compressed=bytearray();width=height=depth=color=None
    while pos<len(data):
        if pos+12>len(data):raise ValueError('Truncated PNG')
        length=struct.unpack('>I',data[pos:pos+4])[0];kind=data[pos+4:pos+8]
        if length>max_bytes or pos+length+12>len(data):raise ValueError('Invalid PNG chunk size')
        body=data[pos+8:pos+8+length];crc=struct.unpack('>I',data[pos+8+length:pos+12+length])[0]
        if zlib.crc32(kind+body)!=crc:raise ValueError('PNG checksum differs')
        chunks.append(kind)
        if len(chunks)==1:
            if kind!=b'IHDR' or length!=13:raise ValueError('PNG requires IHDR first')
            width,height,depth,color,compression,filtering,interlace=struct.unpack('>IIBBBBB',body)
            if not 1<=width<=max_dimension or not 1<=height<=max_dimension or depth!=8 or color not in (0,2,3,4,6) or compression or filtering or interlace:
                raise ValueError('Images require bounded noninterlaced 8-bit PNG dimensions')
        elif kind==b'IHDR':raise ValueError('Duplicate PNG header')
        if kind==b'caNv' and capture_metadata and length==16:
            pass  # ImageMagick native capture canvas metadata; never evaluated.
        elif kind not in {b'IHDR',b'PLTE',b'IDAT',b'IEND',b'tRNS',b'gAMA',b'cHRM',b'sRGB',b'sBIT',b'pHYs',b'tEXt',b'iTXt',b'zTXt',b'bKGD',b'tIME'}:
            raise ValueError('Unsupported PNG chunk, animation or embedded resource')
        if kind==b'IDAT':compressed.extend(body)
        pos+=length+12
        if kind==b'IEND':
            if length or pos!=len(data):raise ValueError('Invalid PNG terminator/trailing bytes')
            break
    channels={0:1,2:3,3:1,4:2,6:4}[color]
    expected=height*(1+width*channels)
    decoder=zlib.decompressobj();raw=decoder.decompress(bytes(compressed),expected+1)
    if chunks[-1:]!=[b'IEND'] or len(raw)!=expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError('PNG pixel stream has invalid bounded dimensions')
    if any(raw[n]>4 for n in range(0,len(raw),1+width*channels)):raise ValueError('Invalid PNG row filter')
    return width,height,color in (4,6) or b'tRNS' in chunks
def svg(data):
    screened=data.replace(b'xmlns="http://www.w3.org/2000/svg"',b'').replace(b"xmlns='http://www.w3.org/2000/svg'",b'')
    if len(data)>LIMIT or re.search(br'<!|<\?|url\s*\(|https?:|file:|data:|@',screened,re.I):
        raise ValueError('SVG declarations, scripts, references, styles and external resources are prohibited')
    root=ET.fromstring(data)
    tags={'svg','g','path','rect','circle','ellipse','line','polyline','polygon'}
    attrs={'xmlns','viewBox','width','height','x','y','x1','y1','x2','y2','cx','cy','r','rx','ry','d','points','fill','stroke','stroke-width','stroke-linecap','stroke-linejoin','fill-rule','opacity','fill-opacity','stroke-opacity','transform'}
    nodes=list(root.iter())
    if len(nodes)>256 or root.tag.split('}')[-1]!='svg':raise ValueError('SVG element bound/root differs')
    for node in nodes:
        if node.tag not in tags and not (node.tag.startswith('{http://www.w3.org/2000/svg}') and node.tag.split('}')[-1] in tags):raise ValueError('Unsupported SVG element')
        for key,value in node.attrib.items():
            if key not in attrs or len(value)>32768 or not re.fullmatch(r'[A-Za-z0-9#.,+\-() %\s]*',value):raise ValueError('Unsupported or unsafe SVG attribute')
            if key in {'fill','stroke'} and not re.fullmatch(r'none|#[0-9a-fA-F]{3,8}|[a-zA-Z]+',value):raise ValueError('Use a literal SVG color')
    for key in ('width','height'):
        if not re.fullmatch(r'[0-9]{1,3}(px)?',root.get(key,'')) or not 1<=int(root.get(key).removesuffix('px'))<=512:raise ValueError('SVG requires explicit 1..512 pixel dimensions')
    return data
def limits():
    resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,512*1024**2))
    resource.setrlimit(resource.RLIMIT_CPU,(3,3));resource.setrlimit(resource.RLIMIT_FSIZE,(LIMIT,LIMIT))
def raster(source,fmt,size=None,tool='/usr/bin/magick'):
    # No author command, path or decoder selection reaches this trusted invocation.
    if fmt=='svg':
        # MSVG can lose inherited group paint and carry zero stroke opacity
        # into later shapes. Materialize the already admitted inheritable paint
        # attributes on every element, with opacities after their paint. Paths,
        # transforms and group opacity remain entirely decoder-owned.
        ET.register_namespace('','http://www.w3.org/2000/svg')
        root=ET.fromstring(svg(source))
        defaults={'fill':'black','stroke':'none','fill-rule':'nonzero',
                  'stroke-width':'1','stroke-linecap':'butt','stroke-linejoin':'miter',
                  'fill-opacity':'1','stroke-opacity':'1'}
        def explicit_paint(node,inherited):
            paint=dict(inherited)
            for key,fallback in defaults.items():
                if key not in node.attrib:continue
                declared=node.attrib.pop(key)
                paint[key]=inherited.get(key,fallback) if declared=='inherit' else declared
            for key,value in paint.items():
                if key!='stroke-opacity':node.set(key,value)
            node.set('stroke-opacity',paint['stroke-opacity'])
            for child in node:explicit_paint(child,paint)
            if node.tag.split('}')[-1] in {'svg','g'}:
                # These containers paint no geometry. Keeping inherited paint
                # here as well makes MSVG multiply fill/stroke opacity twice.
                # Group opacity and transforms are distinct and remain intact.
                for key in defaults:node.attrib.pop(key,None)
        explicit_paint(root,{'stroke-opacity':'1'})
        source=ET.tostring(root,encoding='utf-8')
    command=[tool,'-limit','memory','32MiB','-limit','map','32MiB','-background','none',fmt+':-']
    if size is not None:
        if type(size)is not int or not 8<=size<=192:raise ValueError('Icon display size exceeds supported DPI bound')
        command+=['-resize',str(size)+'x'+str(size)]
    temporary=os.environ.get('TMPDIR','/tmp')
    result=subprocess.run(command+['-strip','-depth','8','PNG32:-'],input=source,capture_output=True,timeout=5,
                          env={'PATH':'/usr/bin:/bin','MAGICK_THREAD_LIMIT':'1','TMPDIR':temporary,'MAGICK_TEMPORARY_PATH':temporary,'HOME':temporary},preexec_fn=limits)
    if result.returncode or len(result.stdout)>LIMIT:raise ValueError('Bounded icon rasterization failed: '+result.stderr.decode(errors='replace')[-2048:])
    png(result.stdout);return result.stdout
def admit(path,title,category,license,tool='/usr/bin/magick'):
    p=Path(path)
    if p.is_symlink() or p.resolve()!=p.absolute() or not p.is_file() or p.stat().st_nlink!=1 or p.stat().st_size>LIMIT:raise ValueError('Use an ordinary bounded owned icon file; links are refused')
    if not title.strip() or not category.strip() or not license.strip() or max(map(len,(title,category,license)))>200:raise ValueError('Title/category/license provenance is required')
    data=p.read_bytes();fmt=p.suffix.lower().lstrip('.')
    if fmt=='png':width,height,alpha=png(data);pixels=raster(data,'png',tool=tool)
    elif fmt=='svg':svg(data);pixels=raster(data,'svg',tool=tool);width,height,alpha=png(pixels)
    else:raise ValueError('Icon import accepts PNG or the documented safe SVG subset only')
    return dict(title=title,category=category,license=license,source_format=fmt,source_data=base64.b64encode(data).decode(),sha256=sha(data),png=base64.b64encode(pixels).decode(),png_sha256=sha(pixels),width=width,height=height,alpha=alpha)
def validate(record):
    expected={'title','category','license','source_format','source_data','sha256','png','png_sha256','width','height','alpha'}
    if set(record)!=expected:raise ValueError('Icon resource fields differ')
    data=base64.b64decode(record['source_data'],validate=True);pixels=base64.b64decode(record['png'],validate=True)
    if sha(data)!=record['sha256'] or sha(pixels)!=record['png_sha256']:raise ValueError('Icon resource hash differs')
    w,h,a=png(pixels)
    if (int(record['width']),int(record['height']),bool(int(record['alpha'])))!=(w,h,a):raise ValueError('Icon metadata differs from pixels')
    if record['source_format']=='png':png(data)
    elif record['source_format']=='svg':svg(data)
    else:raise ValueError('Unsupported icon source codec')
    for key in ('title','category','license'):
        if not record[key].strip() or len(record[key])>200:raise ValueError('Icon provenance is required')
    return record

def package_resources(raw):
    """Add resources to the current standard Module packaging owner payload."""
    t=tkinter.Tcl()
    def dictionary(value):
        words=t.splitlist(value);return dict(zip(words[::2],words[1::2]))
    result={};catalog={}
    for identifier,value in dictionary(raw).items():
        if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}',identifier):raise ValueError('Invalid packaged icon ID')
        record=validate(dictionary(value))
        result['resources/icons/'+identifier+'.png']=base64.b64decode(record['png'])
        result['resources/icons/'+identifier+'.source.'+record['source_format']]=base64.b64decode(record['source_data'])
        catalog[identifier]={key:value for key,value in record.items() if key not in {'png','source_data'}}
    if catalog:result['resources/icons/catalog.json']=(json.dumps({'schema':'gxtxt.viewer_icon_resources.v1','icons':catalog},indent=2)+'\n').encode()
    return result
if __name__=='__main__':
    try:
        if sys.argv[1]=='catalog':
            if len(sys.argv)!=2:raise ValueError('Shared icon discovery accepts no path or arguments')
            result=shared_catalog()
        elif sys.argv[1]=='import':result=admit(*sys.argv[2:])
        elif sys.argv[1] in {'validate','photo'}:
            raw=sys.stdin.read(1048577)
            if len(raw)>1048576:raise ValueError('Icon resource exceeds bound')
            words=tkinter.Tcl().splitlist(raw)
            if len(words)%2 or len(set(words[::2]))!=len(words)//2:raise ValueError('Invalid icon dictionary')
            result=validate(dict(zip(words[::2],words[1::2])))
            if sys.argv[1]=='photo':result={'png':base64.b64encode(raster(base64.b64decode(result['png']),'png',int(sys.argv[2]),sys.argv[3] if len(sys.argv)>3 else '/usr/bin/magick')).decode()}
        else:raise ValueError('Unsupported icon resource operation')
        print(tcl_result({'ok':True,'result':result}))
    except Exception as error:
        print(tcl_result({'ok':False,'error':str(error)}));sys.exit(1)
