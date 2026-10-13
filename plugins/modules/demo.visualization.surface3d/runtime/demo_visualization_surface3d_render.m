function demo_visualization_surface3d_render(outdir,cfg,D)
% Render the canonical XYZ Dataset through persistent public Plot Variants.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('demo.visualization.surface3d: Session path missing');endif
  if(!isfield(D,'dataset_id')||!isfield(D,'x_var')||!isfield(D,'y_var')||!isfield(D,'z_var'))
    error('demo.visualization.surface3d: cached Dataset bindings missing');
  endif
  enabled=parse_list(gxtxt_ini_get(cfg,'graph_provider.enabled', ...
    'demo.visualization.surface3d.surface;demo.visualization.surface3d.mesh;demo.visualization.surface3d.contour3'));
  graphs={ ...
    'demo.visualization.surface3d.surface','surface','01_surface.png','3D thermal surface'; ...
    'demo.visualization.surface3d.mesh','mesh','02_mesh.png','3D thermal mesh'; ...
    'demo.visualization.surface3d.contour3','contour3','03_contour3.png','3D thermal contours'};
  items={};
  for gi=1:rows(graphs)
    graph=graphs{gi,1};if(!any(strcmp(enabled,graph))),continue;endif
    config=struct('plot_type',graphs{gi,2},'reduction_mode','none');
    for key={'x_label','y_label','z_label','contour_levels','extra_format'}
      name=key{1};raw=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' name],'auto'));
      if(!isempty(raw)&&!strcmpi(raw,'auto')&&(!strcmp(name,'contour_levels')||strcmp(graph,graphs{3,1})))
        config.(name)=raw;
      endif
    endfor
    labels={'x_label','X','x_unit';'y_label','Y','y_unit';'z_label','T','z_unit'};
    for li=1:rows(labels)
      field=labels{li,1};if(!isfield(config,field))
        unit='';if(isfield(D,labels{li,3})),unit=D.(labels{li,3});endif
        config.(field)=axis_label(labels{li,2},unit);
      endif
    endfor
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],graphs{gi,4}));
    spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_3d', ...
      'graph_id','plot.dataset.xyz','dataset_id',D.dataset_id, ...
      'x_variable_id',D.x_var,'y_variable_id',D.y_var,'z_variable_id',D.z_var, ...
      'title',title_text,'config',config);
    item=struct('key',graphs{gi,2},'spec',spec,'png',graphs{gi,3});
    if(isfield(config,'extra_format')),item.extra_format=config.extra_format;endif
    items{end+1}=item;
  endfor
  gxtxt_plot_provider_render_v1(session,outdir,'demo.visualization.surface3d',items,'base');
endfunction
function out=axis_label(name,unit)
  out=name;if(!isempty(strtrim(unit))),out=[name ' [' strtrim(unit) ']'];endif
endfunction
function out=parse_list(s)
  s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif
  out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);
  out=out(!cellfun(@isempty,out));
endfunction
