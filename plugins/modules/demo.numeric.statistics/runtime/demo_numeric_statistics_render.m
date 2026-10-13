function demo_numeric_statistics_render(outdir,series_dataset_id,value_name,value_unit,mode,cfg)
% Render included observations and public summary references via Plot.dataset.
% SPDX-License-Identifier: GPL-3.0-or-later
  graph='demo.numeric.statistics.values';
  enabled=split_list_local(gxtxt_ini_get(cfg,'graph_provider.enabled',graph));
  items={};
  if(any(strcmp(enabled,graph)))
    session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
    if(isempty(session)),error('Statistics demo: Session missing');endif
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Statistics demo - values with mean and median'));
    xl=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'Included observation'));
    yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),value_name,value_unit);
    axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
    lw=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.4'),1.4);
    ms=positive_number(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'5'),5);
    if(strcmp(mode,'weighted')),mean_label='Weighted mean';median_label='Weighted median';
    else mean_label='Mean';median_label='Median';endif
    series={curve('included',series_dataset_id,'value','Included value','solid',max(0.7,0.55*lw),ms), ...
      curve('mean',series_dataset_id,'mean_reference',mean_label,'dashed',lw,0), ...
      curve('median',series_dataset_id,'median_reference',median_label,'dotted',lw,0)};
    panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{{}});
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
      'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
      'panels',{{panel}},'output',struct('extra_format','none'));
    items{end+1}=struct('key','values','spec',spec,'png','01_statistics_values.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'demo.numeric.statistics',items,mode);
endfunction
function s=curve(id,dataset,variable,label,line_style,width,marker_size)
  style=struct('line_style',line_style,'line_width',width);
  if(marker_size>0),style.marker='circle';style.marker_size=marker_size;endif
  s=struct('id',id,'dataset_id',dataset,'x_variable_id','sample_index','y_variable_id',variable, ...
    'axis','left','kind','line','label',label,'style',style);
endfunction
function s=axis_label(raw,name,unit),if(!strcmpi(strtrim(raw),'auto')),s=raw;return;endif;s=strrep(strtrim(name),'_',' ');if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif,endfunction
function v=positive_number(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif,endfunction
function out=split_list_local(raw),raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor;endfunction
