function demo_numeric_peaks_rerender_main(args)
% Cache-only rerender for demo.numeric.peaks.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('demo.numeric.peaks rerender: --config is required');endif;cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('demo.numeric.peaks rerender: runtime.output_dir missing');endif
  try
    gxtxt_progress_start('loading_cache','Loading peak-detection render cache','indeterminate');cache_path=fullfile(outdir,'render_cache.mat');if(exist(cache_path,'file')!=2),error('demo.numeric.peaks rerender: render_cache.mat not found: %s',cache_path);endif;c=load(cache_path);required={'source_dataset_id','output_dataset_id','x_id','y_id','peak_count','x_name','y_name','x_unit','y_unit'};for k=1:numel(required),if(!isfield(c,required{k})),error('demo.numeric.peaks rerender: cache missing %s',required{k});endif,endfor
    demo_numeric_peaks_render(outdir,c.source_dataset_id,c.output_dataset_id,c.x_id,c.y_id,c.peak_count,c.x_name,c.y_name,c.x_unit,c.y_unit,cfg);gxtxt_progress_complete('done','Peak-detection graph rerendered');
  catch err
    try gxtxt_progress_fail('failed','Peak-detection graph rerender failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif,endfor,endfunction
