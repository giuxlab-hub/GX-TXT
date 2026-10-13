function analysis_welch_spectrum_rerender_main(args)
% Cache-only rerender for Welch PSD & Averaged Spectrum.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('analysis.welch_spectrum rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('analysis.welch_spectrum rerender: output directory missing');endif
  cache_path=strtrim(gxtxt_ini_get(cfg,'render_cache_api.path',''));if(isempty(cache_path)),cache_path=outdir;endif;cache=gxtxt_render_cache_load(cache_path);rep=gxtxt_render_cache_validate(cache,struct('module_id','analysis.welch_spectrum'));if(!rep.valid||!isfield(cache,'module')),error('analysis.welch_spectrum rerender: stale/incompatible cache');endif
  analysis_welch_spectrum_render(outdir,cfg,cache.module);
endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
