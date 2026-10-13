function curvefit_family_render_public(outdir,cfg,D,hname,gname,yname,mode)
% Five persistent fitting/validation graphs using public Plot.dataset.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('curvefit.family_global: Session path missing for public graphs');endif
  ids={'curvefit.family.overlay','curvefit.family.residuals','curvefit.family.parity', ...
    'curvefit.family.relative_residuals','curvefit.family.error_by_family'};
  enabled=split_list(ini_get(cfg,'graph_provider.enabled',ids{1}));items={};
  if(any(strcmp(enabled,ids{1})))
    graph=ids{1};title_text=mode_title(cfg,graph,'Curve Family Fitting - measured vs fitted','Curve Family Validation - measured vs predicted',mode);
    axes=plot_axes(cfg,graph,hname,yname);series={};
    ms=positive(ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    lw=positive(ini_get(cfg,['plot.' graph '.line_width'],'1.5'),1.5);
    if(parse_bool(ini_get(cfg,['plot.' graph '.show_measured'],'1'),true))
      series{end+1}=trace('measured',D.result_id,'horizontal','measured','Measured','scatter', ...
        struct('marker','circle','marker_size',ms,'color','#555555'));
    endif
    if(parse_bool(ini_get(cfg,['plot.' graph '.show_fitted'],'1'),true))
      word='Fitted';if(strcmp(mode,'evaluate')),word='Predicted';endif
      series{end+1}=family_trace('predicted',D.result_id,'horizontal','predicted',word,'line',gname,struct('line_width',lw));
    endif
    if(isempty(series)),series={trace('identity',D.identity_id,'measured','identity','No series selected','line',struct())};endif
    items{end+1}=item('overlay',title_text,axes,series,{},'01_curve_family_fit.png');
  endif
  if(any(strcmp(enabled,ids{2})))
    graph=ids{2};title_text=mode_title(cfg,graph,'Curve Family Fitting - residuals','Curve Family Validation - residuals',mode);
    axes=plot_axes(cfg,graph,hname,['Residual [' strrep(yname,'_',' ') ']']);
    ms=positive(ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    series={family_trace('residual',D.result_id,'horizontal','residual','Residual','line_marker',gname,struct('marker','circle','marker_size',ms))};
    annotations=zero_annotation(cfg,graph);
    items{end+1}=item('residuals',title_text,axes,series,annotations,'02_curve_family_residuals.png');
  endif
  if(any(strcmp(enabled,ids{3})))
    graph=ids{3};title_text=mode_title(cfg,graph,'Curve Family Fitting - parity plot','Curve Family Validation - parity plot',mode);
    xl=['Measured ' strrep(yname,'_',' ')];yl=['Fitted ' strrep(yname,'_',' ')];
    if(strcmp(mode,'evaluate')),yl=['Predicted ' strrep(yname,'_',' ')];endif
    axes=plot_axes(cfg,graph,xl,yl);
    if(parse_bool(ini_get(cfg,['plot.' graph '.same_axis_range'],'1'),true))
      axes.x.min=D.parity_min;axes.x.max=D.parity_max;
      axes.y_left.min=D.parity_min;axes.y_left.max=D.parity_max;
    endif
    ms=positive(ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    s=trace('observations',D.result_id,'measured_axis','predicted','Measured vs predicted','scatter',struct('marker','circle','marker_size',ms));
    if(parse_bool(ini_get(cfg,['plot.' graph '.distinguish_family'],'0'),false)),s.family_variable_id='group';s.family_label_prefix=gname;endif
    series={s,trace('identity',D.identity_id,'measured','identity','Identity','line',struct('line_style','dashed'))};
    items{end+1}=item('parity',title_text,axes,series,{},'03_curve_family_parity.png');
  endif
  if(any(strcmp(enabled,ids{4})))
    graph=ids{4};title_text=mode_title(cfg,graph,'Curve Family Fitting - relative residuals','Curve Family Validation - relative residuals',mode);
    axes=plot_axes(cfg,graph,hname,'Relative error [%]');
    ms=positive(ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    series={family_trace('relative_residual',D.result_id,'horizontal','relative_percent','Relative residual','line_marker',gname,struct('marker','circle','marker_size',ms))};
    annotations=zero_annotation(cfg,graph);
    items{end+1}=item('relative_residuals',title_text,axes,series,annotations,'04_curve_family_relative_residuals.png');
  endif
  if(any(strcmp(enabled,ids{5})))
    graph=ids{5};title_text=mode_title(cfg,graph,'Curve Family Fitting - error by family','Curve Family Validation - error by group',mode);
    metric=lower(strtrim(ini_get(cfg,['plot.' graph '.metric'],'rmse')));
    if(!any(strcmp(metric,{'rmse','mae','max_abs_error'}))),metric='rmse';endif
    names=struct('rmse','RMSE','mae','MAE','max_abs_error','MaxAbsError');
    axes=plot_axes(cfg,graph,gname,[names.(metric) ' [' strrep(yname,'_',' ') ']']);
    ticks=arrayfun(@num2str,1:numel(D.group_labels),'UniformOutput',false);
    axes.x.tick_positions=strjoin(ticks,';');axes.x.tick_labels=strjoin(D.group_labels,';');
    series={trace(metric,D.metrics_id,'group_index',metric,names.(metric),'bar',struct('opacity',0.6))};
    items{end+1}=item('error_by_family',title_text,axes,series,{},'05_curve_family_error_by_family.png');
  endif
  gxtxt_plot_provider_render_v1(session,outdir,'curvefit.family_global',items,'base');
endfunction

function s=family_trace(id,dataset,x,y,label,kind,prefix,style)
  s=trace(id,dataset,x,y,label,kind,style);s.family_variable_id='group';s.family_label_prefix=prefix;
endfunction
function s=trace(id,dataset,x,y,label,kind,style)
  s=struct('id',id,'dataset_id',dataset,'x_variable_id',x,'y_variable_id',y, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function out=item(key,title_text,axes,series,annotations,png)
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  out=struct('key',key,'spec',spec,'png',png);
endfunction
function axes=plot_axes(cfg,graph,xname,yname)
  xl=auto_label(ini_get(cfg,['plot.' graph '.x_label'],'auto'),xname);
  yl=auto_label(ini_get(cfg,['plot.' graph '.y_label'],'auto'),yname);
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
  pairs={'x','x_min','x_max';'y_left','y_min','y_max'};
  for i=1:rows(pairs)
    a=pairs{i,1};lo=str2double(ini_get(cfg,['plot.' graph '.' pairs{i,2}],''));
    hi=str2double(ini_get(cfg,['plot.' graph '.' pairs{i,3}],''));
    if(isfinite(lo)&&isfinite(hi)&&hi>lo),axes.(a).min=lo;axes.(a).max=hi;endif
  endfor
endfunction
function out=zero_annotation(cfg,graph)
  out={};if(parse_bool(ini_get(cfg,['plot.' graph '.show_zero_line'],'1'),true))
    out={struct('type','reference_line','axis','left','value',0,'line_style','dashed')};
  endif
endfunction
function s=mode_title(cfg,graph,fit_default,eval_default,mode)
  s=ini_get(cfg,['plot.' graph '.title'],fit_default);
  if(strcmp(mode,'evaluate')&&strcmp(strtrim(s),fit_default)),s=eval_default;endif
endfunction
function s=auto_label(raw,name),if(strcmpi(strtrim(raw),'auto')),s=strrep(name,'_',' ');else s=raw;endif,endfunction
function v=positive(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif,endfunction
function b=parse_bool(raw,def),s=lower(strtrim(raw));if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif,endfunction
function a=split_list(raw),raw=strrep(raw,',',';');if(isempty(strtrim(raw))),a={};return;endif;a=strsplit(raw,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
