function demo_numeric_interpolation_rerender_main(args)
% Cache-only rerender for demo.numeric.interpolation.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if (isempty(config_path)), error('demo.numeric.interpolation rerender: --config is required'); endif
  cfg=gxtxt_ini_read(config_path); outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if (isempty(outdir)), error('demo.numeric.interpolation rerender: runtime.output_dir missing'); endif
  try
    gxtxt_progress_start('loading_cache','Loading interpolation render cache','indeterminate');
    cache_path=fullfile(outdir,'render_cache.mat');
    if (exist(cache_path,'file')!=2), error('demo.numeric.interpolation rerender: render_cache.mat not found: %s',cache_path); endif
    c=load(cache_path);
    required={'output_dataset_id','source_dataset_id','x_id','y_id','x_name','y_name','x_unit','y_unit'};
    for k=1:numel(required)
      if (!isfield(c,required{k})), error('demo.numeric.interpolation rerender: cache missing %s',required{k}); endif
    endfor
    demo_numeric_interpolation_render(outdir,c.output_dataset_id,c.source_dataset_id,c.x_id,c.y_id,c.x_name,c.y_name,c.x_unit,c.y_unit,cfg);
    gxtxt_progress_complete('done','Interpolation graphs rerendered');
  catch err
    try gxtxt_progress_fail('failed','Interpolation graph rerender failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function v=arg_value(args,key,def)
  v=def; for k=1:numel(args)-1, if(strcmp(args{k},key)), v=args{k+1}; return; endif; endfor
endfunction
