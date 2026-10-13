function demo_numeric_calculus_rerender_main(args)
% Cache-only rerender for demo.numeric.calculus.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('demo.numeric.calculus rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('demo.numeric.calculus rerender: runtime.output_dir missing');endif
  try
    gxtxt_progress_start('loading_cache','Loading calculus render cache','indeterminate');
    cache_path=fullfile(outdir,'render_cache.mat');if(exist(cache_path,'file')!=2),error('demo.numeric.calculus rerender: render_cache.mat not found: %s',cache_path);endif
    c=load(cache_path);required={'output_dataset_id','x_name','function_name','derivative_name','integral_name','x_unit','function_unit','derivative_unit','integral_unit'};
    for k=1:numel(required),if(!isfield(c,required{k})),error('demo.numeric.calculus rerender: cache missing %s',required{k});endif,endfor
    demo_numeric_calculus_render(outdir,c.output_dataset_id,c.x_name,c.function_name,c.derivative_name,c.integral_name,c.x_unit,c.function_unit,c.derivative_unit,c.integral_unit,cfg);
    gxtxt_progress_complete('done','Calculus graphs rerendered');
  catch err
    try gxtxt_progress_fail('failed','Calculus graph rerender failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif,endfor,endfunction
