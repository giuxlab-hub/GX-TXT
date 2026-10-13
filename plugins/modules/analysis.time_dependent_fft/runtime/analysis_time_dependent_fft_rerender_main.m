function analysis_time_dependent_fft_rerender_main(args)
% Cache-only rerender for time-dependent FFT plot/export presentation changes.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('analysis.time_dependent_fft rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('analysis.time_dependent_fft rerender: runtime.output_dir missing');endif
  cache_path=strtrim(gxtxt_ini_get(cfg,'render_cache_api.path',''));
  if(isempty(cache_path)),cache_path=outdir;endif
  cache=gxtxt_render_cache_load(cache_path);expected=struct('module_id','analysis.time_dependent_fft');
  rep=gxtxt_render_cache_validate(cache,expected);if(!rep.valid),error('analysis.time_dependent_fft rerender: stale/incompatible render cache: %s',joincell(rep.errors,','));endif
  if(!tdfft_cache_version_supported(cache))
    error('analysis.time_dependent_fft rerender: incompatible scientific cache version');
  endif
  if(!isfield(cache,'module')),error('analysis.time_dependent_fft rerender: render cache has no module payload');endif
  validate_scientific_cache(cfg,cache);
  variant_graph=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));variant_id=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));
  if(isempty(variant_graph)||isempty(variant_id))
    tdfft_split_export_from_dataset(outdir,cfg,cache.module);
  else
    d=fullfile(outdir,'window_exports');if(exist(d,'dir')==7),rmdir(d,'s');endif
    fid=fopen(fullfile(outdir,'split_export_index.txt'),'w');if(fid>=0),fputs(fid,'Plot variant rerender: no scientific per-window data export was repeated.\n');fclose(fid);endif
  endif
  analysis_time_dependent_fft_render(outdir,cfg,cache.module);
endfunction
function validate_scientific_cache(cfg,cache)
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  time_binding=strtrim(gxtxt_ini_get(cfg,'bindings.time',''));
  signal_binding=strtrim(gxtxt_ini_get(cfg,'bindings.signal',''));
  time_name=regexprep(time_binding,'^.*\.','');signal_name=regexprep(signal_binding,'^.*\.','');
  [~,~,time_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',time_name);
  [~,~,signal_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',signal_name);
  if(isempty(source_id)||!isfield(time_meta,'found')||!time_meta.found||!isfield(signal_meta,'found')||!signal_meta.found)
    error('analysis.time_dependent_fft rerender: scientific source or bindings are unavailable');
  endif
  T=gxtxt_temporal_set_from_runtime(cfg,'temporal_set');
  if(!T.enabled||!strcmp(T.type,'window_set'))
    error('analysis.time_dependent_fft rerender: Temporal Window Set is unavailable');
  endif
  nfft_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.nfft_mode','auto')));
  if(strcmp(nfft_mode,'auto')),nfft=T.resolved_window_rows;
  else nfft=str2double(gxtxt_ini_get(cfg,'config.nfft',''));endif
  if(!isfinite(nfft)||nfft<2||nfft!=fix(nfft))
    error('analysis.time_dependent_fft rerender: invalid scientific NFFT');
  endif
  source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));
  fingerprint=tdfft_scientific_fingerprint(source_id,tdfft_source_stamp(source_path), ...
    strtrim(time_meta.variable_id),strtrim(signal_meta.variable_id),T, ...
    lower(strtrim(gxtxt_ini_get(cfg,'config.window','hann'))), ...
    lower(strtrim(gxtxt_ini_get(cfg,'config.detrend','mean'))),nfft_mode,nfft, ...
    lower(strtrim(gxtxt_ini_get(cfg,'config.spectral_representation','amplitude'))));
  if(!isfield(cache.module,'scientific_fingerprint')||!strcmp(cache.module.scientific_fingerprint,fingerprint))
    error('analysis.time_dependent_fft rerender: scientific source/settings changed; rerun base FFT analysis');
  endif
endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
function s=joincell(c,sep),if(isempty(c)),s='';return;endif;s=c{1};for i=2:numel(c),s=[s sep c{i}];endfor;endfunction
