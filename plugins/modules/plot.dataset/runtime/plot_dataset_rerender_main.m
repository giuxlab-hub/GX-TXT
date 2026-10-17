function plot_dataset_rerender_main(args)
% Rerender Scientific Dataset Plot; rebuild bounded 2-D preparation when needed.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('plot.dataset rerender: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('plot.dataset rerender: runtime.output_dir missing');endif
  gxtxt_progress_start('loading_cache','Loading Scientific Dataset Plot render cache','indeterminate');
  try
    rebuild_reason='';
    try
      cache=gxtxt_render_cache_load(outdir);
    catch load_err
      rebuild_reason=['unreadable cache: ' load_err.message];
    end_try_catch
    info=pd_runtime_info(cfg);presentation_lifetime=gxtxt_presentation_scope_v1(info.session);opts=read_opts(cfg);enabled=enabled_graphs(cfg);sources=pd_source_map(cfg,info,enabled);
    if(isempty(rebuild_reason))
      expected=struct('module_id','plot.dataset','module_version','3.18.0','source_fingerprint',gxtxt_render_cache_source_fingerprint(sources));rep=gxtxt_render_cache_validate(cache,expected);
      if(!rep.valid),rebuild_reason=['stale/incompatible cache: ' joincell(rep.errors,',')];elseif(!isfield(cache,'module')),rebuild_reason='cache.module is missing';endif
    endif
    if(!isempty(rebuild_reason))
      % Runtime and cache are derived from persistent plot state. Rebuilding
      % here is safer than omitting unmatched series or trapping the user behind
      % a disposable cache error; persistent PlotSpec/variants are never reset.
      gxtxt_progress_stage('rebuilding_cache',['Rebuilding Scientific Dataset Plot data (' rebuild_reason ')'],'indeterminate');
      plot_dataset_main({'--config',config_path});
      return;
    endif
    cache_dirty=false;
    for graph={'plot.dataset.xy','plot.dataset.xy_region'}
      g=graph{1};if(any(strcmp(enabled,g)))
        fld=cache_field(g);fp=pd_prep_fingerprint(info,cfg,opts,'2d',g);
        stale=!isfield(cache.module,fld)||!isfield(cache.meta,'prep2d')||!isfield(cache.meta.prep2d,fld)||!strcmp(cache.meta.prep2d.(fld),fp);
        if(stale)
          previous=struct();if(isfield(cache.module,fld)),previous=cache.module.(fld);endif
          P=pd_prepare_2d(info,cfg,opts,g,previous);cache.module.(fld)=P;cache.module.(['prepared_' fld])=true;
          if(!isfield(cache.meta,'prep2d')||!isstruct(cache.meta.prep2d)),cache.meta.prep2d=struct();endif
          cache.meta.prep2d.(fld)=fp;cache_dirty=true;
        endif
      endif
    endfor
    if(any(strcmp(enabled,'plot.dataset.xyz'))),if(!isfield(cache.module,'prepared_3d')||!cache.module.prepared_3d),error('plot.dataset rerender: 3D data are not present in cache. Run the module again.');endif;opts3d=pd_3d_options(cfg,opts);fp=pd_prep_fingerprint(info,cfg,opts3d,'3d');if(!isfield(cache.meta,'prep3d_fingerprint')||!strcmp(cache.meta.prep3d_fingerprint,fp)),error('plot.dataset rerender: 3D bindings/plot type/preparation settings changed. Run the module again.');endif;endif
    [cache.module,policy_changed]=pd_coordinate_capture(cache.module,cfg,enabled);cache_dirty=cache_dirty||policy_changed;
    for graph={'plot.dataset.xy','plot.dataset.xy_region'}
      if(any(strcmp(enabled,graph{1}))),fld=cache_field(graph{1});cache.module.(fld)=pd_attach_x_region_selection(cache.module.(fld),cfg,graph{1});endif
    endfor
    if(cache_dirty),gxtxt_render_cache_save(outdir,cache);endif
    % Summary is derived state too; rewrite it even when prepared data remains
    % reusable so diagnostics cannot describe a previous graph selection.
    pd_write_summary(fullfile(outdir,'plot_summary.txt'),info,opts,cache.module,enabled,cache.meta);
    gxtxt_progress_stage('rendering','Rerendering scientific dataset plots','indeterminate');plot_dataset_render(outdir,cfg,cache.module);pd_coordinate_receipt(outdir,cache.module,enabled);gxtxt_progress_complete('done','Scientific Dataset Plot rerendered');
  catch err;try gxtxt_progress_fail('failed','Scientific Dataset Plot rerender failed');catch;end_try_catch;rethrow(err);end_try_catch
endfunction
function fld=cache_field(graph),if(strcmp(graph,'plot.dataset.xy')),fld='plot2d_xy';else fld='plot2d_xy_region';endif;endfunction
function opts=read_opts(cfg),opts=struct();opts.reduction_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.reduction_mode','auto')));if(!any(strcmp(opts.reduction_mode,{'auto','none','stride','minmax'}))),opts.reduction_mode='auto';endif;opts.target_points=parse_int(gxtxt_ini_get(cfg,'config.target_points','6000'),6000,100);opts.auto_reduce_threshold=parse_int(gxtxt_ini_get(cfg,'config.auto_reduce_threshold','12000'),12000,100);opts.chunk_rows=parse_int(gxtxt_ini_get(cfg,'config.chunk_rows','5000'),5000,100);endfunction
function v=parse_int(s,d,minv),v=str2double(s);if(!isfinite(v)),v=d;endif;v=max(minv,round(v));endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function s=joincell(c,sep),if(isempty(c)),s='';return;endif;s=c{1};for i=2:numel(c),s=[s sep c{i}];endfor;endfunction
function out=enabled_graphs(cfg),s=strrep(gxtxt_ini_get(cfg,'graph_provider.enabled','plot.dataset.xy'),',',';');a=strsplit(s,';');out={};for i=1:numel(a),q=strtrim(a{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
