function demo_numeric_interpolation_render(outdir,output_dataset_id,source_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,cfg)
% Persist interpolation graphs through public Plot.dataset variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)||isempty(output_dataset_id)),error('Interpolation demo: Session or published Dataset missing');endif
  if(exist('gxtxt_plot_provider_render_v1','file')!=2),error('Interpolation demo: public Plot Provider bridge missing');endif
  enabled=split_list(gxtxt_ini_get(cfg,'graph_provider.enabled','demo.numeric.interpolation.curves;demo.numeric.interpolation.errors'));
  items={};methods={'linear','cubic','spline','pchip'};names={'Linear','Cubic','Spline','PCHIP'};
  graph='demo.numeric.interpolation.curves';
  if(any(strcmp(enabled,graph)))
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Interpolation demo - samples, reference and interpolants'));
    axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit);
    width=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.5'),1.5);
    marker=positive(gxtxt_ini_get(cfg,['plot.' graph '.source_marker_size'],'6'),6);
    series={struct('id','source_samples','dataset_id',source_dataset_id,'x_variable_id',x_id, ...
      'y_variable_id',y_id,'axis','left','kind','scatter','label','Original samples', ...
      'style',struct('marker','circle','marker_size',marker)), ...
      curve('reference',output_dataset_id,'y_reference','Analytical reference','solid',max(width,1.8))};
    styles={'dashed','dashdot','dotted','solid'};
    for k=1:numel(methods)
      series{end+1}=curve(methods{k},output_dataset_id,['y_' methods{k}],[names{k} ' interpolation'],styles{k},width);
    endfor
    spec=plot_spec(title_text,axes,series,{});
    items{end+1}=struct('key','curves','spec',spec,'png','01_interpolation_curves.png');
  endif
  graph='demo.numeric.interpolation.errors';
  if(any(strcmp(enabled,graph)))
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Interpolation demo - error against analytical reference'));
    axes=plot_axes(cfg,graph,x_name,'Interpolation error',x_unit,y_unit);
    width=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.4'),1.4);
    styles={'solid','dashed','dashdot','dotted'};series={};
    for k=1:numel(methods)
      series{end+1}=curve(['error_' methods{k}],output_dataset_id,['error_' methods{k}],[names{k} ' error'],styles{k},width);
    endfor
    annotations={struct('type','reference_line','axis','left','value',0,'line_style','dotted')};
    spec=plot_spec(title_text,axes,series,annotations);
    items{end+1}=struct('key','errors','spec',spec,'png','02_interpolation_errors.png');
  endif
  gxtxt_plot_provider_render_v1(session,outdir,'demo.numeric.interpolation',items,'base');
endfunction
function s=curve(id,dataset,variable,label,line_style,width)
  s=struct('id',id,'dataset_id',dataset,'x_variable_id','x','y_variable_id',variable, ...
    'axis','left','kind','line','label',label,'style',struct('line_style',line_style,'line_width',width));
endfunction
function axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit)
  xl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'),x_name,x_unit);
  yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),y_name,y_unit);
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
endfunction
function spec=plot_spec(title_text,axes,series,annotations)
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
endfunction
function value=axis_label(raw,name,unit)
  value=strtrim(raw);if(isempty(value)||strcmpi(value,'auto'))
    value=strrep(strtrim(name),'_',' ');
    if(!isempty(strtrim(unit))),value=[value ' [' strtrim(unit) ']'];endif
  endif
endfunction
function v=positive(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif;endfunction
function out=split_list(raw),raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor;endfunction
