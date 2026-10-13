function demo_numeric_regression_render(outdir,dataset_id,coeff_dataset_id,has_wls,has_reference,has_sigma,x_name,y_name,x_unit,y_unit,degree,cfg)
% Render canonical regression Datasets through public Plot.dataset variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  ids={'demo.numeric.regression.fit','demo.numeric.regression.coefficients', ...
    'demo.numeric.regression.residual_x','demo.numeric.regression.residual_fitted', ...
    'demo.numeric.regression.absolute_residual','demo.numeric.regression.reference'};
  enabled=split_list_local(gxtxt_ini_get(cfg,'graph_provider.enabled',strjoin(ids,';')));
  items={};
  if(any(strcmp(enabled,ids{1})))
    graph=ids{1};title_text=graph_title(cfg,graph,'Regression demo - measured data and fitted model');
    axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.6'),1.6);
    ms=positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    measured=trace('measured',dataset_id,'x','measured','Measured','scatter','none',lw,ms);
    if(has_sigma)
      measured.kind='errorbar';measured.y_error=struct('mode','symmetric','variable_id','sigma');
    endif
    series={measured,trace('ols',dataset_id,'x','fitted_ols','OLS fit','line','solid',lw,0)};
    if(has_wls),series{end+1}=trace('wls',dataset_id,'x','fitted_wls','WLS fit','line','dashed',lw,0);endif
    items{end+1}=plot_item('fit',title_text,axes,series,{},'01_fit_comparison.png');
  endif
  if(any(strcmp(enabled,ids{2})))
    graph=ids{2};title_text=graph_title(cfg,graph,'Regression demo - coefficients and standard errors');
    axes=struct('x',struct('label',sprintf('Coefficient index (descending polynomial power, degree %d)',degree)), ...
      'y_left',struct('label','Coefficient estimate (units vary by power)'));
    ols=trace('ols',coeff_dataset_id,'coefficient_index','estimate_ols','OLS','errorbar','none',1.2,6);
    ols.y_error=struct('mode','symmetric','variable_id','stderr_ols');series={ols};
    if(has_wls)
      wls=trace('wls',coeff_dataset_id,'coefficient_index','estimate_wls','WLS','errorbar','none',1.2,6);
      wls.y_error=struct('mode','symmetric','variable_id','stderr_wls');series{end+1}=wls;
    endif
    items{end+1}=plot_item('coefficients',title_text,axes,series,{},'02_coefficient_diagnostics.png');
  endif
  if(any(strcmp(enabled,ids{3})))
    graph=ids{3};title_text=graph_title(cfg,graph,'Regression demo - residuals versus X');
    axes=plot_axes(cfg,graph,x_name,'Residual (measured - fitted)',x_unit,y_unit);
    ms=positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    series={trace('ols',dataset_id,'x','residual_ols','OLS residual','scatter','none',1,ms)};
    if(has_wls),series{end+1}=trace('wls',dataset_id,'x','residual_wls','WLS residual','scatter','none',1,ms);endif
    items{end+1}=plot_item('residual_x',title_text,axes,series,{zero_line()},'03_residuals_vs_x.png');
  endif
  if(any(strcmp(enabled,ids{4})))
    graph=ids{4};title_text=graph_title(cfg,graph,'Regression demo - residuals versus fitted value');
    axes=plot_axes(cfg,graph,'Fitted Y','Residual (measured - fitted)',y_unit,y_unit);
    ms=positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
    series={trace('ols',dataset_id,'fitted_ols','residual_ols','OLS','scatter','none',1,ms)};
    if(has_wls),series{end+1}=trace('wls',dataset_id,'fitted_wls','residual_wls','WLS','scatter','none',1,ms);endif
    items{end+1}=plot_item('residual_fitted',title_text,axes,series,{zero_line()},'04_residuals_vs_fitted.png');
  endif
  if(any(strcmp(enabled,ids{5})))
    graph=ids{5};title_text=graph_title(cfg,graph,'Regression demo - absolute residuals');
    axes=plot_axes(cfg,graph,x_name,'Absolute residual',x_unit,y_unit);
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.3'),1.3);
    series={trace('ols',dataset_id,'x','absolute_residual_ols','|OLS residual|','line','solid',lw,0)};
    if(has_wls),series{end+1}=trace('wls',dataset_id,'x','absolute_residual_wls','|WLS residual|','line','dashed',lw,0);endif
    items{end+1}=plot_item('absolute_residual',title_text,axes,series,{},'05_absolute_residuals.png');
  endif
  if(any(strcmp(enabled,ids{6})))
    graph=ids{6};title_text=graph_title(cfg,graph,'Regression demo - reference and fitted model');
    lw=positive(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.5'),1.5);
    if(has_reference)
      axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit);
      series={trace('reference',dataset_id,'x','reference','Reference','line','solid',max(1.8,lw),0), ...
        trace('ols',dataset_id,'x','fitted_ols','OLS fit','line','dashed',lw,0)};
      if(has_wls),series{end+1}=trace('wls',dataset_id,'x','fitted_wls','WLS fit','line','dotted',lw,0);endif
    else
      title_text='Regression demo - measured versus fitted (no reference bound)';
      axes=struct('x',struct('label',axis_label('auto','Fitted Y',y_unit)), ...
        'y_left',struct('label',axis_label('auto','Measured Y',y_unit)));
      series={trace('measured',dataset_id,'fitted_ols','measured','Measured','scatter','none',1,5), ...
        trace('identity',dataset_id,'fitted_ols','fitted_ols','Perfect fit','line','dotted',1,0)};
    endif
    items{end+1}=plot_item('reference',title_text,axes,series,{},'06_reference_comparison.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'demo.numeric.regression',items,'base');
endfunction
function s=trace(id,dataset,x,y,label,kind,line_style,width,marker_size)
  style=struct('line_style',line_style,'line_width',width);
  if(marker_size>0),style.marker='circle';style.marker_size=marker_size;endif
  s=struct('id',id,'dataset_id',dataset,'x_variable_id',x,'y_variable_id',y, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function item=plot_item(key,title_text,axes,series,annotations,png)
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  item=struct('key',key,'spec',spec,'png',png);
endfunction
function a=zero_line(),a=struct('type','reference_line','axis','left','value',0,'line_style','dotted');endfunction
function s=graph_title(cfg,graph,def),s=gxtxt_ini_get(cfg,['plot.' graph '.title'],def);endfunction
function axes=plot_axes(cfg,graph,x_name,y_name,x_unit,y_unit)
  xl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'),x_name,x_unit);
  yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),y_name,y_unit);
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
endfunction
function s=axis_label(raw,name,unit)
  if(!strcmpi(strtrim(raw),'auto')),s=raw;return;endif
  s=strrep(strtrim(name),'_',' ');if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif
endfunction
function v=positive(raw,def),v=str2double(raw);if(!isfinite(v)||v<=0),v=def;endif;endfunction
function out=split_list_local(raw)
  raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};
  for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor
endfunction
