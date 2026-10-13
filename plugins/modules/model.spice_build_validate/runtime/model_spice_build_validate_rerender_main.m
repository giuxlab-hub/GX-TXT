function model_spice_build_validate_rerender_main(args)
% GX-TXT v0.7.8 - cache-only rerender for SPICE Build and Validation.
% SPDX-License-Identifier: GPL-3.0-or-later

  config_path=gxtxt_spice_arg_value(args,'--config','');
  if(isempty(config_path)), error('model.spice_build_validate rerender: --config is required'); endif
  cfg=gxtxt_spice_read_ini(config_path);
  outdir=gxtxt_spice_ini_get(cfg,'runtime.output_dir','');
  if(isempty(outdir)), error('model.spice_build_validate rerender: runtime.output_dir missing'); endif
  cache_path=fullfile(outdir,'render_cache.mat');
  if(exist(cache_path,'file')!=2), error('model.spice_build_validate rerender: render_cache.mat not found: %s',cache_path); endif

  gxtxt_progress_start('loading_cache','Loading SPICE validation render cache','indeterminate');
  try
    cache=load(cache_path);
    required={'input_x','input_family','measured_y','analytical_y','spice_y','residual_spice_analytical','residual_spice_measured','comparison','profile','domain_role','model_x_name','model_family_name','model_y_name'};
    for i=1:numel(required)
      if(!isfield(cache,required{i})), error('render_cache.mat missing variable: %s',required{i}); endif
    endfor
    raw=gxtxt_spice_ini_get(cfg,'graph_provider.enabled','model.spice.overlay;model.spice.residuals;model.spice.parity');
    parts=strsplit(strrep(raw,',',';'),';'); parts=cellfun(@strtrim,parts,'UniformOutput',false); total=sum(!cellfun(@isempty,parts)); if(total<1),total=1;endif
    gxtxt_progress_stage('rendering','Rendering SPICE validation graphs','determinate',total);
    model_spice_render(outdir,cfg,cache);
    gxtxt_progress_update(total,total,'rendering','Rendering SPICE validation graphs');
    gxtxt_progress_complete('completed','SPICE validation rerender completed');
  catch err
    try gxtxt_progress_fail('failed','SPICE validation rerender failed; see log'); catch, end_try_catch
    rethrow(err);
  end_try_catch
endfunction
