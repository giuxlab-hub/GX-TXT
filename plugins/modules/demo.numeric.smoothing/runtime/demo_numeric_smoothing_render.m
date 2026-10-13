function demo_numeric_smoothing_render(outdir,output_dataset_id,x_name,measured_name,reference_name,x_unit,measured_unit,reference_unit,cfg)
% Render published smoothing comparisons through persistent Plot.dataset variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  ids={'demo.numeric.smoothing.original','demo.numeric.smoothing.methods', ...
    'demo.numeric.smoothing.reference','demo.numeric.smoothing.errors'};
  enabled=split_list_local(gxtxt_ini_get(cfg,'graph_provider.enabled',strjoin(ids,';')));
  items={};methods={'moving_mean','moving_median','savitzky_golay','local_polynomial'};
  labels={'Moving mean','Moving median','Savitzky-Golay','Local polynomial'};
  styles={'dashed','dashdot','dotted','solid'};
  if(any(strcmp(enabled,ids{1})))
    graph=ids{1};title_text=gxtxt_ini_get(cfg,['plot.' graph '.title'],'Smoothing demo - measured and reference signal');
    axes=plot_axes(cfg,graph,x_name,measured_name,x_unit,measured_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.6'),1.6);
    ms=positive(gxtxt_ini_get(cfg,['plot.' graph '.measured_marker_size'],'3'),3);
    series={trace('measured',output_dataset_id,'measured','Measured / noisy','scatter','none',lw,ms), ...
      trace('reference',output_dataset_id,'reference','Reference / clean','line','solid',lw,0)};
    items{end+1}=plot_item('original',title_text,axes,series,{},'01_measured_and_reference.png');
  endif
  if(any(strcmp(enabled,ids{2})))
    graph=ids{2};title_text=gxtxt_ini_get(cfg,['plot.' graph '.title'],'Smoothing demo - measured signal and smoothing methods');
    axes=plot_axes(cfg,graph,x_name,measured_name,x_unit,measured_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.4'),1.4);
    mlw=positive(gxtxt_ini_get(cfg,['plot.' graph '.measured_line_width'],'0.8'),0.8);
    series={trace('measured',output_dataset_id,'measured','Measured / noisy','line','solid',mlw,0)};
    for k=1:numel(methods)
      series{end+1}=trace(methods{k},output_dataset_id,['smooth_' methods{k}],labels{k},'line',styles{k},lw,0);
    endfor
    items{end+1}=plot_item('methods',title_text,axes,series,{},'02_measured_and_smoothing.png');
  endif
  if(any(strcmp(enabled,ids{3})))
    graph=ids{3};title_text=gxtxt_ini_get(cfg,['plot.' graph '.title'],'Smoothing demo - reference signal and smoothing methods');
    axes=plot_axes(cfg,graph,x_name,reference_name,x_unit,reference_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.5'),1.5);
    series={trace('reference',output_dataset_id,'reference','Reference / clean','line','solid',max(lw,1.8),0)};
    for k=1:numel(methods)
      series{end+1}=trace(methods{k},output_dataset_id,['smooth_' methods{k}],labels{k},'line',styles{k},lw,0);
    endfor
    items{end+1}=plot_item('reference',title_text,axes,series,{},'03_reference_and_smoothing.png');
  endif
  if(any(strcmp(enabled,ids{4})))
    graph=ids{4};title_text=gxtxt_ini_get(cfg,['plot.' graph '.title'],'Smoothing demo - error relative to reference');
    axes=plot_axes(cfg,graph,x_name,'Smoothing error',x_unit,measured_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.3'),1.3);
    series={};
    for k=1:numel(methods)
      series{end+1}=trace(['error_' methods{k}],output_dataset_id,['error_' methods{k}],[labels{k} ' error'],'line',styles{k},lw,0);
    endfor
    annotations={struct('type','reference_line','axis','left','value',0,'line_style','dotted')};
    items{end+1}=plot_item('errors',title_text,axes,series,annotations,'04_smoothing_errors.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'demo.numeric.smoothing',items,'base');
endfunction
function s=trace(id,dataset,variable,label,kind,line_style,width,marker_size)
  style=struct('line_style',line_style,'line_width',width);
  if(marker_size>0),style.marker='circle';style.marker_size=marker_size;endif
  s=struct('id',id,'dataset_id',dataset,'x_variable_id','x','y_variable_id',variable, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function item=plot_item(key,title_text,axes,series,annotations,png)
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  item=struct('key',key,'spec',spec,'png',png);
endfunction
function axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit)
  xl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'),x_name,x_unit);
  yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),y_name,y_unit);
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
endfunction
function s=axis_label(raw,name,unit),if(!strcmpi(strtrim(raw),'auto')),s=raw;return;endif;s=strrep(strtrim(name),'_',' ');if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif,endfunction
function v=positive(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif;endfunction
function out=split_list_local(raw),raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor;endfunction
