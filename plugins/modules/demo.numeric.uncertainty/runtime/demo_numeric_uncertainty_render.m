function demo_numeric_uncertainty_render(outdir,series_dataset_id,value_name,value_unit,interpretation,cfg)
% Render published measurements and uncertainty through public Plot.dataset.
% SPDX-License-Identifier: GPL-3.0-or-later
  graph='demo.numeric.uncertainty.measurements';
  enabled=split_list_local(gxtxt_ini_get(cfg,'graph_provider.enabled',graph));
  items={};
  if(any(strcmp(enabled,graph)))
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Measurement uncertainty demo'));
    xl=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'Measurement'));
    yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),value_name,value_unit);
    axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
    lw=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.4'),1.4);
    ms=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'6'),6);
    measurement=curve('measurements',series_dataset_id,'value','Measurement','line_marker','solid',max(0.7,0.55*lw),ms);
    if(strcmp(interpretation,'standard_uncertainty'))
      measurement.label='Measurement with standard uncertainty';
      measurement.kind='errorbar';
      measurement.y_error=struct('mode','symmetric','variable_id','aux');
      series={measurement,curve('ordinary',series_dataset_id,'ordinary_reference','Arithmetic mean','line','dashed',lw,0)};
    else
      series={measurement,curve('ordinary',series_dataset_id,'ordinary_reference','Ordinary mean','line','dotted',lw,0), ...
        curve('weighted',series_dataset_id,'weighted_reference','Weighted mean','line','dashed',lw,0)};
    endif
    panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{{}});
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
      'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
      'panels',{{panel}},'output',struct('extra_format','none'));
    items{end+1}=struct('key','measurements','spec',spec,'png','01_uncertainty_measurements.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'demo.numeric.uncertainty',items,interpretation);
endfunction
function s=curve(id,dataset,variable,label,kind,line_style,width,marker_size)
  style=struct('line_style',line_style,'line_width',width);
  if(marker_size>0),style.marker='circle';style.marker_size=marker_size;endif
  s=struct('id',id,'dataset_id',dataset,'x_variable_id','sample_index', ...
    'y_variable_id',variable,'axis','left','kind',kind,'label',label,'style',style);
endfunction
function s=axis_label(raw,name,unit),if(!strcmpi(strtrim(raw),'auto')),s=raw;return;endif;s=strrep(strtrim(name),'_',' ');if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif,endfunction
function v=positive_number(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif,endfunction
function out=split_list_local(raw),raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor;endfunction
