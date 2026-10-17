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
        layer_order=i,representation='wireframe' if d['plot_type']=='mesh' else 'points' if kind=='points' else 'surface',
        base_color=vector(layer['color']),line_width=d['line_width'],point_size=d['point_size'],backface_culling=0,scalar_coloring=layer['scalar'],
        local_transform=vector(transform))
labels=d['axis_labels'];caption=str(d['title'])+'\n'+' · '.join(f'{a}: {label} [{limits[i][0]:.6g}, {limits[i][1]:.6g}]' for i,(a,label) in enumerate(zip('XYZ',labels)))
if d['legend']:caption+='\n'+ ' · '.join(d['legend'])
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
    legend=' · '.join(d['legend']),scalar_label=d['colorbar_label'],
    scalar_min=d['clim'][0],scalar_max=d['clim'][1],palette=[vector(v) for v in d['colormap']])
(root/'scene.tcldict').write_text(tcl(dict(view=view,layers=layers,caption=caption,
    scientific_figure=figure,presentation=d)),encoding='utf-8')
print('NATIVE3D_PREPARED')
