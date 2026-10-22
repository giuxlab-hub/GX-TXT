# SPDX-License-Identifier: GPL-3.0-or-later
"""Serialize the public Plot preview projection for the existing Native3D host."""
import json,sys,hashlib,math
from pathlib import Path
from tkinter import _join
root=Path(sys.argv[1]);d=json.loads((root/'plot/presentation.json').read_text())
def tcl(value):
    if isinstance(value,dict):return _join([x for k,v in value.items() for x in (k,tcl(v))])
    if isinstance(value,list):return _join([tcl(v) for v in value])
    return str(int(value)) if isinstance(value,bool) else str(value)
def vector(v):return ';'.join(format(float(x),'.17g') for x in v)
def prepared_style(data):
    """Consume only versioned effective-object metadata; no config resolution."""
    original=' · '.join(data['legend'])
    if 'prepared_presentation' not in data:
        return {},original
    prepared=data['prepared_presentation']
    if not isinstance(prepared,dict) or type(prepared.get('version')) is not int or prepared['version']!=1:
        raise ValueError('Unsupported prepared presentation version')
    def flag(record,key):
        value=record[key]
        if not isinstance(value,bool):raise ValueError('Invalid prepared presentation flag: '+key)
        return value
    def numbers(value,count):
        if not isinstance(value,list) or len(value)!=count or any(isinstance(x,bool) or not isinstance(x,(int,float)) or not math.isfinite(x) for x in value):
            raise ValueError('Invalid prepared presentation coordinates')
        return value
    def rectangle(value):
        x,y,w,h=numbers(value,4)
        if min(x,y)<-1e-9 or min(w,h)<=0 or max(x+w,y+h)>1+1e-9:
            raise ValueError('Prepared presentation rectangle lies outside the figure')
        return x,y,w,h
    style={}
    automatic=flag(prepared,'layout_auto')
    x,y,w,h=rectangle(prepared['axes_position'])
    if not automatic:
        style.update(margin_left=x,margin_bottom=y,margin_right=max(0,1-x-w),margin_top=max(0,1-y-h))
    legend=prepared['legend']
    explicit=flag(legend,'position_explicit')
    if not flag(legend,'visible'):
        return style,''
    x,y,w,h=rectangle(legend['box'])
    entries=legend['entries']
    if isinstance(entries,dict):entries=[entries] # Octave scalar struct encoding
    if not isinstance(entries,list) or not entries:
        raise ValueError('Prepared legend has no text entries')
    ordered=[]
    for entry in entries:
        if not isinstance(entry,dict) or not isinstance(entry.get('text'),str):raise ValueError('Invalid prepared legend text')
        px,py=numbers(entry['position'],2)
        font=entry['font_px']
        if isinstance(font,bool) or not isinstance(font,(int,float)) or not math.isfinite(font) or font<=0:
            raise ValueError('Invalid prepared legend font')
        ordered.append((py,px,entry['text'],font))
    ordered.sort(key=lambda entry:(-entry[0],entry[1]))
    if any(not math.isclose(entry[3],ordered[0][3],rel_tol=1e-9) for entry in ordered):
        raise ValueError('Prepared legend requires a uniform native text font')
    rows=[];row_y=None
    for py,px,text,font in ordered:
        if row_y is None or abs(py-row_y)>1e-7:
            rows.append([]);row_y=py
        rows[-1].append(text)
    text='\n'.join(' · '.join(row) for row in rows)
    if len(text.encode('utf-8'))>=1024:
        raise ValueError('Prepared legend exceeds the native text contract; static graph is preserved')
    style.update(legend_font_size=ordered[0][3],legend_alignment=1,
                 legend_background=int(flag(legend,'background')),legend_border=int(flag(legend,'border')))
    for key in ('background','border'):
        rgb=numbers(legend[key+'_rgb'],3)
        if any(channel<0 or channel>1 for channel in rgb):raise ValueError('Invalid prepared legend color')
        style.update({f'legend_{key}_{channel}':value for channel,value in zip('rgb',rgb)})
    if explicit:
        style.update(legend_x=x+w/2,legend_y=y+h/2)
    return style,text

native_style,legend_text=prepared_style(d)
dar=d['aspect'];limits=d['limits']
if len(dar)!=3 or not all(math.isfinite(v) and v>0 for v in dar):raise ValueError('Invalid graph aspect')
view={k:vector(d[k]) for k in ('camera_position','camera_target','camera_up')}
distance=math.dist(d['camera_position'],d['camera_target'])
view.update(projection=d['projection'],vertical_fov_degrees=d['fov'],near_clip=max(distance*1e-4,1e-8),far_clip=max(distance*100,10),
    background_rgb=vector(d['background']),background_bottom_rgb=vector(d['background']),background_gradient=0,lighting=0,axes_world=0,
    clip_box=vector([limits[i][0]/dar[i] for i in range(3)]+[limits[i][1]/dar[i] for i in range(3)]))
transform=[0.0]*16
for i in range(3):transform[i*5]=1/dar[i]
transform[15]=1
layers={}
for i,layer in enumerate(d['layers']):
    path=root/'plot'/layer['path'];kind=layer['primitive']
    layers[f'series_{i}']=dict(kind=kind,source_mode='artifact',format='vtp',absolute_path=str(path),resource_path=str(path),
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(),visible=1,opacity=1,colormap='viridis',scalar_range=vector(d['clim']),
        scalar_array='scientific_scalar' if layer['scalar'] else '',color_array=layer['color_array'] if layer['scalar'] else '',
        vector_array='',radius_array='',opacity_array='',sphere_glyphs=0,tube_radius=0,isovalues='',volume_transfer='',volume_sample_distance=.05,
        layer_order=i,representation='points' if kind=='points' else 'surface',
        base_color=vector(layer['color']),line_width=d['line_width'],point_size=d['point_size'],backface_culling=0,scalar_coloring=layer['scalar'],
        local_transform=vector(transform))
labels=d['axis_labels'];caption=str(d['title'])+'\n'+' · '.join(f'{a}: {label} [{limits[i][0]:.6g}, {limits[i][1]:.6g}]' for i,(a,label) in enumerate(zip('XYZ',labels)))
if legend_text:caption+='\n'+legend_text
caption+='\n'+d['plot_type']+' · exact prepared graph'
if d.get('coordinate_policies'):
    caption+='\nDataset view: '+' · '.join(f'{axis.upper()} ×{policy["view_factor"]:g} about {policy["view_pivot"]:g} {policy["source"]["unit"]}' for axis,policy in d['coordinate_policies'].items())
    caption+=' · numerical calibration is not applied'

colorbar=dict(visible=d['colorbar_visible'],label=d['colorbar_label'],range=d['clim'],palette=['#'+''.join(f'{round(max(0,min(1,v))*255):02x}' for v in color) for color in d['colormap']])
figure=dict(axes_grid_visible=1,colorbar_visible=d['colorbar_visible'],
    bounds_min=vector([limits[i][0]/dar[i] for i in range(3)]),
    bounds_max=vector([limits[i][1]/dar[i] for i in range(3)]),
    axis_min=vector([limits[i][0] for i in range(3)]),axis_max=vector([limits[i][1] for i in range(3)]),
    x_label=labels[0],y_label=labels[1],z_label=labels[2],title=d['title'],
    legend=legend_text,scalar_label=d['colorbar_label'],
    scalar_min=d['clim'][0],scalar_max=d['clim'][1],palette=[vector(v) for v in d['colormap']])
if native_style:figure['native_style']=native_style
(root/'scene.tcldict').write_text(tcl(dict(view=view,layers=layers,caption=caption,
    scientific_figure=figure,presentation=d)),encoding='utf-8')
print('NATIVE3D_PREPARED')
