function gxtxt_ir_identify_rerender_main(args)
% Rerender persistent public Plot Variants from canonical diagnostic Datasets.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('gxtxt.ir_identify rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=gxtxt_ini_get(cfg,'runtime.output_dir','');
  if(isempty(outdir)),error('gxtxt.ir_identify rerender: runtime.output_dir missing');endif
  cache_path=arg_value(args,'--cache',fullfile(outdir,'render_cache.mat'));
  try
    gxtxt_progress_start('loading_cache','Loading IR protocol graph identities','indeterminate');
    if(exist(cache_path,'file')!=2),error('gxtxt.ir_identify rerender: cache missing');endif
    C=load(cache_path);
    required={'ids','rank_labels','rank_scores','expected_values','frame_annotations','best_name','identification_status'};
    for k=1:numel(required)
      if(!isfield(C,required{k})),error('gxtxt.ir_identify rerender: cache missing %s',required{k});endif
    endfor
    gxtxt_ir_identify_render(outdir,cfg,C.ids,C.rank_labels,C.rank_scores,C.expected_values, ...
      C.frame_annotations,C.best_name,C.identification_status);
    gxtxt_progress_complete('done','IR protocol graphs rerendered');
  catch err
    try gxtxt_progress_fail('failed','IR protocol rerender failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function v=arg_value(args,key,def)
  v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif,endfor
endfunction
