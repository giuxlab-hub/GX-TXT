function demo_numeric_calculus_render(outdir,dataset_id,x_name,function_name,derivative_name,integral_name,x_unit,function_unit,derivative_unit,integral_unit,cfg)
% Scientific plots are persistent public Dataset Plot Variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)||isempty(dataset_id)),error('Calculus demo: Session or published Dataset missing');endif
  if(exist('gxtxt_plot_provider_render_v1','file')!=2),error('Calculus demo: public Plot Provider bridge missing');endif
  graphs={ ...
    {'function','demo.numeric.calculus.function','01_function.png','Calculus demo - source function',function_name,function_unit,{'function'}, {'Source function'}}, ...
    {'derivative','demo.numeric.calculus.derivative','02_derivative_comparison.png','Calculus demo - exact and numerical derivative',derivative_name,derivative_unit,{'derivative_exact','derivative_numeric'},{'Exact derivative','Numerical derivative'}}, ...
    {'derivative_error','demo.numeric.calculus.derivative_error','03_derivative_error.png','Calculus demo - derivative error','Derivative error',derivative_unit,{'derivative_error'},{'Derivative error'}}, ...
    {'integral','demo.numeric.calculus.integral','04_integral_comparison.png','Calculus demo - exact and numerical cumulative integral',integral_name,integral_unit,{'integral_exact','integral_numeric'},{'Exact integral','Numerical cumulative integral'}}, ...
    {'integral_error','demo.numeric.calculus.integral_error','05_integral_error.png','Calculus demo - cumulative integration error','Cumulative integration error',integral_unit,{'integral_error'},{'Cumulative integration error'}}};
  enabled=split_list(gxtxt_ini_get(cfg,'graph_provider.enabled', ...
    'demo.numeric.calculus.function;demo.numeric.calculus.derivative;demo.numeric.calculus.derivative_error;demo.numeric.calculus.integral;demo.numeric.calculus.integral_error'));
  items={};
  for k=1:numel(graphs)
    row=graphs{k};key=row{1};graph=row{2};if(!any(strcmp(enabled,graph))),continue;endif
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],row{4}));
    xl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'),x_name,x_unit);
    yl=axis_label(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'),row{5},row{6});
    axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
    variables=row{7};labels=row{8};series=cell(1,numel(variables));
    width=str2double(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'1.5'));
    if(!isfinite(width)||width<=0),width=1.5;endif
    for j=1:numel(variables)
      style=struct('line_width',width);
      if(j==2),style.line_style='dashed';endif
      series{j}=struct('id',variables{j},'dataset_id',dataset_id,'x_variable_id','x', ...
        'y_variable_id',variables{j},'axis','left','kind','line','label',labels{j},'style',style);
    endfor
    annotations={};
    if(any(strcmp(key,{'derivative_error','integral_error'})))
      annotations={struct('type','reference_line','axis','left','value',0,'line_style','dotted')};
    endif
    panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
      'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
      'panels',{{panel}},'output',struct('extra_format','none'));
    items{end+1}=struct('key',key,'spec',spec,'png',row{3});
  endfor
  gxtxt_plot_provider_render_v1(session,outdir,'demo.numeric.calculus',items,'base');
endfunction
function value=axis_label(raw,name,unit)
  value=strtrim(raw);
  if(isempty(value)||strcmpi(value,'auto'))
    value=strrep(strtrim(name),'_',' ');
    if(!isempty(strtrim(unit))),value=[value ' [' strtrim(unit) ']'];endif
  endif
endfunction
function out=split_list(raw)
  raw=strrep(raw,',',';');parts=strsplit(raw,';');out={};
  for k=1:numel(parts),q=strtrim(parts{k});if(!isempty(q)),out{end+1}=q;endif,endfor
endfunction
