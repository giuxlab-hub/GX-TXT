"""Trusted Native2D raster provider. Native owns geometry; ImageMagick owns pixels.

Only fixed operations/arguments below are accepted. Input resources remain
immutable; output is owned by the existing Scientific Execution Job.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib,json,math,struct,tkinter
from gxtxt_scientific_execution import tdict

MAX_PIXELS=16777216
BLENDS={'Over','Multiply','Screen','Overlay','SoftLight','DstIn'}

def seq(value):return tkinter.Tcl().splitlist(value)
def number(value):
    result=float(value)
    if not math.isfinite(result) or abs(result)>1e9:raise ValueError('Invalid bounded raster coordinate')
    return format(result,'.17g')
def png_info(raw):
    if len(raw)<33 or raw[:8]!=b'\x89PNG\r\n\x1a\n' or raw[12:16]!=b'IHDR':raise ValueError('Only verified PNG image resources are supported')
    w,h,depth,color=struct.unpack('>IIBB',raw[16:26])
    if not w or not h or w*h>MAX_PIXELS or color not in (0,2,3,4,6) or depth not in ((1,2,4,8,16) if color in (0,3) else (8,16)):raise ValueError('Unsupported or oversized PNG resource')
    return w,h,depth,color

def run(c):
    manifest=tdict(c.inputs['composition'].decode('utf-8'))
    if manifest.get('schema')!='gxtxt.native2d.raster_composition.v1':raise ValueError('Unknown raster composition schema')
    width=int(float(manifest['width']));height=int(float(manifest['height']))
    if width<1 or height<1 or width*height>MAX_PIXELS:raise ValueError('Raster canvas exceeds pixel bounds')
    size=f'{width}x{height}';operation=c.parameters['operation'];feather=c.parameters['feather'];antialias=c.parameters['antialias'];invert=c.parameters['invert'];effect=c.parameters['effect']
    if operation not in ('mask','extract','composite','effect'):raise ValueError('Unsupported fixed raster operation')
    limits=['-limit','memory','256MiB','-limit','map','512MiB','-limit','disk','1GiB','-limit','thread','1','-limit','time','120']
    def im(args):return c.run('magick',limits+args)
    versions=c.run('magick',['-version'])['stdout'];operators=c.run('magick',['-list','compose'])['stdout'].split()
    if not BLENDS.issubset(set(operators)):raise ValueError('Configured ImageMagick lacks required compose operators')
    roi=tdict(manifest.get('roi',''))
    def mask(path,definition,inverse=False):
        vertices=[seq(p) for p in seq(definition['vertices'])]
        if len(vertices)<3 or len(vertices)>128:raise ValueError('Native ROI vertex bounds invalid')
        points=' '.join(','.join(number(v) for v in p) for p in vertices)
        if any(len(p)!=2 for p in vertices):raise ValueError('Native ROI point shape invalid')
        args=['-size',size,'xc:black','-colorspace','Gray', '-antialias' if antialias else '+antialias','-fill','white','-stroke','none','-draw','polygon '+points]
        if feather:args+=['-blur','0x'+number(feather)]
        if inverse:args+=['-negate']
        im(args+['-depth','16','-define','png:bit-depth=16','-define','png:color-type=0','PNG:'+str(path)])
    roi_path=c.scratch/'roi.png'
    if operation in ('mask','extract','effect'):
        if not roi:raise ValueError('This operation requires a current image-local ROI')
        mask(roi_path,roi,invert)
    layers=[tdict(x) for x in seq(manifest['layers'])]
    if not layers or len(layers)>16:raise ValueError('Expected 1..16 owned raster layers')
    provenance=[]
    for i,layer in enumerate(layers):
        raw=c.inputs[layer['alias']];w,h,depth,color=png_info(raw)
        if hashlib.sha256(raw).hexdigest()!=layer['source_sha256']:raise ValueError('Layer resource SHA mismatch')
        path=c.scratch/f'input-{i}.png';path.write_bytes(raw);layer['_path']=path
        provenance.append({k:v for k,v in layer.items() if k!='_path'})
    output=c.output/'raster.png'
    if operation=='mask':
        im(['PNG:'+str(roi_path),'-depth','16','-define','png:bit-depth=16','-define','png:color-type=0','PNG:'+str(output)])
    else:
        canvas=c.scratch/'canvas.png';im(['-size',size,'xc:none','-colorspace','sRGB','-depth','16','PNG64:'+str(canvas)])
        for i,layer in enumerate(layers):
            if not int(layer['visible']) or int(layer.get('mask_only','0')):continue
            blend=layer['blend'];opacity=float(layer['opacity'])
            if blend not in BLENDS or not math.isfinite(opacity) or not 0<=opacity<=1:raise ValueError('Invalid layer blend or opacity')
            matrix=seq(layer['matrix'])
            if len(matrix)!=6:raise ValueError('Expected Native image-map affine projection')
            coefficients=','.join(number(v) for v in matrix)
            item=c.scratch/f'layer-{i}.png'
            args=['PNG:'+str(layer['_path']),'-colorspace','sRGB','-alpha','on','-channel','A','-evaluate','multiply',number(opacity),'+channel', '-virtual-pixel','transparent','-background','none','-define','distort:viewport='+size+'+0+0','-distort','AffineProjection',coefficients,'+repage','PNG:'+str(item)]
            im(args)
            if layer.get('roi_mask'):
                layer_mask=c.scratch/f'roi-layer-mask-{i}.png';mask(layer_mask,tdict(layer['roi_mask']))
                alpha_mask=c.scratch/f'roi-layer-alpha-{i}.png'
                im(['PNG:'+str(layer_mask),'-alpha','copy','PNG:'+str(alpha_mask)])
                im(['PNG:'+str(item),'PNG:'+str(alpha_mask),'-compose','DstIn','-composite','PNG:'+str(item)])
            if layer.get('mask_alias'):
                raw=c.inputs[layer['mask_alias']];png_info(raw)
                if hashlib.sha256(raw).hexdigest()!=layer['mask_sha256']:raise ValueError('Layer mask SHA mismatch')
                source=c.scratch/f'mask-source-{i}.png';source.write_bytes(raw);mpath=c.scratch/f'layer-mask-{i}.png'
                mm=seq(layer['mask_matrix'])
                if len(mm)!=6:raise ValueError('Invalid native mask mapping')
                args=['PNG:'+str(source)]
                if layer.get('mask_channel','luminance')=='alpha':args+=['-alpha','extract']
                elif layer.get('mask_channel','luminance')=='luminance':args+=['-colorspace','Gray','-alpha','off']
                else:raise ValueError('Unsupported layer mask channel')
                if int(layer.get('mask_invert','0')):args+=['-negate']
                im(args+['-virtual-pixel','black','-background','black','-define','distort:viewport='+size+'+0+0','-distort','AffineProjection',','.join(number(v) for v in mm),'+repage','-alpha','copy','PNG:'+str(mpath)])
                im(['PNG:'+str(item),'PNG:'+str(mpath),'-compose','DstIn','-composite','PNG:'+str(item)])
            im(['PNG:'+str(canvas),'PNG:'+str(item),'-compose',blend,'-composite','PNG64:'+str(canvas)])
        if operation=='effect':
            effect_args={'negate':['-channel','RGB','-negate','+channel'],'grayscale':['-colorspace','Gray','-colorspace','sRGB'],'blur':['-blur','0x'+number(c.parameters['effect_radius'])]}
            if effect not in effect_args:raise ValueError('Unknown fixed ROI effect')
            edited=c.scratch/'edited.png';im(['PNG:'+str(canvas),*effect_args[effect],'PNG:'+str(edited)])
            im(['PNG:'+str(canvas),'PNG:'+str(edited),'PNG:'+str(roi_path),'-compose','Over','-composite','-depth','16','PNG32:'+str(output)])
        elif operation=='extract':
            alpha=c.scratch/'roi-alpha.png';im(['PNG:'+str(roi_path),'-alpha','copy','PNG:'+str(alpha)])
            im(['PNG:'+str(canvas),'PNG:'+str(alpha),'-compose','DstIn','-composite','-depth','8','PNG32:'+str(output)])
        else:im(['PNG:'+str(canvas),'-depth','8','PNG32:'+str(output)])
    raw=output.read_bytes();actual=png_info(raw)
    if actual[:2]!=(width,height):raise ValueError('ImageMagick changed declared canvas dimensions')
    if operation!='mask' and actual[3]!=6:raise ValueError('Export is not a genuine RGBA PNG')
    report={'schema':'gxtxt.native2d.raster_export.v1','operation':operation,'width':width,'height':height,'canvas_policy':'full_base_image_canvas','source_pixel_origin':[0,0],'base_object_token':manifest['base_object_token'],'base_document_id':manifest['document_id'],'base_document_generation':manifest['document_generation'],'base_image_state':tdict(manifest['base_image_state']),'base_resource':tdict(manifest['base_resource']),'sampling':'ImageMagick native polygon rasterization at source pixel coordinates; optional antialias and Gaussian feather; canvas clips out-of-bounds geometry','roi':roi,'invert':invert,'antialias':antialias,'feather_pixels':feather,'layers':provenance,'output_sha256':hashlib.sha256(raw).hexdigest(),'output_color_type':actual[3],'output_bit_depth':actual[2],'colorspace':'sRGB explicit display composition; no radiometric measurement claim','profile_policy':'ImageMagick colorspace conversion; exported 8-bit RGBA unless grayscale mask16; original source profiles and pixels unchanged','imagemagick_version':versions[:4096],'source_manifest_sha256':hashlib.sha256(c.inputs['composition']).hexdigest(),'scientific_values_modified':False}
    receipt=c.output/'raster-provenance.json';receipt.write_text(json.dumps(report,indent=2))
    c.publish_output('raster.png','raster','png');c.publish_output('raster-provenance.json','provenance','json')
    c.summary({'validation':'validated_structure','width':width,'height':height,'rgba':operation!='mask','output_sha256':report['output_sha256'],'layer_count':len(layers)})
