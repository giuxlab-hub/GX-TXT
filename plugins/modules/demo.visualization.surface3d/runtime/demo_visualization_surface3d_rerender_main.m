function demo_visualization_surface3d_rerender_main(args)
% Cache-only rerender for presentation changes.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('demo.visualization.surface3d rerender: --config is required'); endif
  cfg=gxtxt_ini_read(config_path); outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if(isempty(outdir)), error('demo.visualization.surface3d rerender: runtime.output_dir missing'); endif
  cache=gxtxt_render_cache_load(outdir);
  expected=struct('module_id','demo.visualization.surface3d','module_version','1.0.3');
  source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));
  if(!isempty(source_path)),expected.source_fingerprint=gxtxt_render_cache_source_fingerprint(struct('primary',source_path));endif
  rep=gxtxt_render_cache_validate(cache,expected);
  if(!rep.valid), error('demo.visualization.surface3d rerender: stale/incompatible render cache: %s',joincell(rep.errors,',')); endif
  if(!isfield(cache,'module')), error('demo.visualization.surface3d rerender: render cache has no module payload'); endif
  demo_visualization_surface3d_render(outdir,cfg,cache.module);
endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
function s=joincell(c,sep),if(isempty(c)),s='';return;endif;s=c{1};for i=2:numel(c),s=[s sep c{i}];endfor;endfunction
