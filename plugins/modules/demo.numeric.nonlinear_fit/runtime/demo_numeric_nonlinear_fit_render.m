function demo_numeric_nonlinear_fit_render(outdir,cfg,derived_id)
% Render published observations and fit through the public Plot.dataset API.
% SPDX-License-Identifier: GPL-3.0-or-later
  graph='demo.nonlinear.fit.curve';enabled=parse_list(gxtxt_ini_get(cfg,'graph_provider.enabled',graph));
  items={};
  if(any(strcmp(enabled,graph)))
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Nonlinear fitting - generated observations and exponential fit'));
    xl=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'x'));
    yl=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'y'));
    axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
    series={struct('id','observations','dataset_id',derived_id,'x_variable_id','x', ...
      'y_variable_id','measured','axis','left','kind','scatter', ...
      'label','Generated observations','style',struct('marker','circle','marker_size',5)), ...
      struct('id','fitted','dataset_id',derived_id,'x_variable_id','x', ...
      'y_variable_id','fitted','axis','left','kind','line', ...
      'label','Exponential least-squares fit','style',struct('line_width',1.5))};
    panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{{}});
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
      'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
      'panels',{{panel}},'output',struct('extra_format','none'));
    items{end+1}=struct('key','fit','spec',spec,'png','01_nonlinear_fit.png');
  endif
  gxtxt_plot_provider_render_v1(gxtxt_ini_get(cfg,'runtime.session',''),outdir,'demo.numeric.nonlinear_fit',items,'base');
endfunction
function out=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
