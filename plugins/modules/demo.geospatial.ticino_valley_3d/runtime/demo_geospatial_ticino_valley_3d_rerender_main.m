function demo_geospatial_ticino_valley_3d_rerender_main(args)
% Rerender presentation changes only; never read or recompute source datasets.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('demo.geospatial.ticino_valley_3d rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if(isempty(outdir)),error('demo.geospatial.ticino_valley_3d rerender: output directory missing');endif
  cache=gxtxt_render_cache_load(outdir);
  paths=struct();
  for source={'primary','river','settlements','hydraulic'}
    value=strtrim(gxtxt_ini_get(cfg,['analysis_source.' source{1} '.path'],''));
    if(!isempty(value)),paths.(source{1})=value;endif
  endfor
  expected=struct('module_id','demo.geospatial.ticino_valley_3d','module_version','2.0.0');
  if(numel(fieldnames(paths))==4)
    expected.source_fingerprint=gxtxt_render_cache_source_fingerprint(paths);
  endif
  report=gxtxt_render_cache_validate(cache,expected);
  if(!report.valid),error('demo.geospatial.ticino_valley_3d rerender: stale or incompatible cache');endif
  if(!isfield(cache,'module')),error('demo.geospatial.ticino_valley_3d rerender: no cache payload');endif
  demo_geospatial_ticino_valley_3d_render(outdir,cfg,cache.module);
endfunction

function value=arg_value(args,name,default_value)
  value=default_value;
  for i=1:(numel(args)-1)
    if(strcmp(args{i},name)),value=args{i+1};return;endif
  endfor
endfunction
