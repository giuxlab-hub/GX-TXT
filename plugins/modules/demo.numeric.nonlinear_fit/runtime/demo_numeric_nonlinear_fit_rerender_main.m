function demo_numeric_nonlinear_fit_rerender_main(args)
% Rerender the nonlinear-fit graph without recalculating the fit.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('demo.numeric.nonlinear_fit rerender: --config is required'); endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if(isempty(outdir)), error('demo.numeric.nonlinear_fit rerender: runtime.output_dir missing'); endif
  cache_path=fullfile(outdir,'render_cache.mat');
  if(exist(cache_path,'file')!=2), error('demo.numeric.nonlinear_fit rerender: render_cache.mat is missing; run the module first'); endif
  S=load(cache_path);
  for name={'derived_id'}
    if(!isfield(S,name{1})), error('demo.numeric.nonlinear_fit rerender: render cache missing %s',name{1}); endif
  endfor
  demo_numeric_nonlinear_fit_render(outdir,cfg,S.derived_id);
endfunction

function value=arg_value(args,name,default_value)
  value=default_value;
  for i=1:(numel(args)-1), if(strcmp(args{i},name)), value=args{i+1}; return; endif, endfor
endfunction
