function plot_dataset_render(outdir,cfg,module_cache)
% Render every currently enabled graph from its graph-specific prepared cache.
% SPDX-License-Identifier: GPL-3.0-or-later
  enabled=pd_enabled_graphs(cfg);gxtxt_setup_graphics();
  if(any(strcmp(enabled,'plot.dataset.xy'))),require_and_render(module_cache,'plot2d_xy',outdir,cfg,'plot.dataset.xy','01_dataset_xy.png');endif
  if(any(strcmp(enabled,'plot.dataset.xy_region'))),require_and_render(module_cache,'plot2d_xy_region',outdir,cfg,'plot.dataset.xy_region','02_dataset_xy_region.png');endif
  if(any(strcmp(enabled,'plot.dataset.xyz'))),if(!isfield(module_cache,'prepared_3d')||!module_cache.prepared_3d),error('plot.dataset: 3D graph is enabled but 3D data were not prepared; run the module again');endif;pd_render_3d(outdir,cfg,module_cache.plot3d,'plot.dataset.xyz','03_dataset_xyz.png');endif
endfunction
function require_and_render(M,fld,outdir,cfg,graph,file),if(!isfield(M,fld)),error('plot.dataset: 2D cache for %s is unavailable; run the module again',graph);endif;P=pd_refresh_plotspec_v2(M.(fld),cfg,graph);pd_render_2d(outdir,cfg,P,graph,file);endfunction
function out=pd_enabled_graphs(cfg),out=pd_split(gxtxt_ini_get(cfg,'graph_provider.enabled','plot.dataset.xy'));endfunction
function out=pd_split(s),s=strrep(s,',',';');a=strsplit(s,';');out={};for i=1:numel(a),q=strtrim(a{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
