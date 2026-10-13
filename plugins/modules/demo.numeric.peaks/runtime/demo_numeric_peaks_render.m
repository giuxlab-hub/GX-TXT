function demo_numeric_peaks_render(outdir,source_dataset_id,output_dataset_id,x_id,y_id,peak_count,x_name,y_name,x_unit,y_unit,cfg)
% Persist the source trace and detected peaks through public Plot.dataset.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('Peak demo: Session missing');endif
  graph='demo.numeric.peaks.detected';enabled=split_list_local(gxtxt_ini_get(cfg,'graph_provider.enabled',graph));
  items={};
  if(any(strcmp(enabled,graph)))
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Peak detection demo'));
    xl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'),x_name,x_unit);
    yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),y_name,y_unit);
    axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      axes.x.min=selection.x_min;axes.x.max=selection.x_max;
      axes.x.display_unit=x_unit;
    endif
    lw=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.3'),1.3);
    ms=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'8'),8);
    series={struct('id','source_signal','dataset_id',source_dataset_id,'x_variable_id',x_id, ...
      'y_variable_id',y_id,'axis','left','kind','line','label','Source signal', ...
      'style',struct('line_width',lw))};
    if(peak_count>0)
      series{end+1}=struct('id','detected_peaks','dataset_id',output_dataset_id, ...
        'x_variable_id','peak_x','y_variable_id','peak_y','axis','left', ...
        'kind','scatter','label','Detected peaks', ...
        'style',struct('marker','circle','marker_size',ms));
    endif
    panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{{}});
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
      'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
      'panels',{{panel}},'output',struct('extra_format','none'));
    items{end+1}=struct('key','detected','spec',spec,'png','01_peak_detection.png');
  endif
  gxtxt_plot_provider_render_v1(session,outdir,'demo.numeric.peaks',items,'base');
endfunction
function s=axis_label(raw,name,unit),if(!strcmpi(strtrim(raw),'auto')),s=raw;return;endif;s=strrep(strtrim(name),'_',' ');if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif,endfunction
function v=positive_number(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif,endfunction
function out=split_list_local(raw),raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor,endfunction
