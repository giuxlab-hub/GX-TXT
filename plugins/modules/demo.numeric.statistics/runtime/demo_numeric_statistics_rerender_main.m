function demo_numeric_statistics_rerender_main(args)
% Cache-only rerender for demo.numeric.statistics.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('demo.numeric.statistics rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('demo.numeric.statistics rerender: runtime.output_dir missing');endif
  try
    gxtxt_progress_start('loading_cache','Loading statistics render cache','indeterminate');
    cache_path=fullfile(outdir,'render_cache.mat');if(exist(cache_path,'file')!=2),error('demo.numeric.statistics rerender: render_cache.mat not found: %s',cache_path);endif
    c=load(cache_path);required={'series_dataset_id','value_name','value_unit','mode'};for k=1:numel(required),if(!isfield(c,required{k})),error('demo.numeric.statistics rerender: cache missing %s',required{k});endif,endfor
    demo_numeric_statistics_render(outdir,c.series_dataset_id,c.value_name,c.value_unit,c.mode,cfg);
    gxtxt_progress_complete('done','Statistics graph rerendered');
  catch err
    try gxtxt_progress_fail('failed','Statistics graph rerender failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif,endfor,endfunction
