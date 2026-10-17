function plot_dataset_main(args)
% Scientific Dataset Plot main run.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('plot.dataset: --config is required');endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));if(isempty(outdir)),error('plot.dataset: runtime.output_dir missing');endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing scientific dataset plot','indeterminate');
  try
    info=pd_runtime_info(cfg);presentation_lifetime=gxtxt_presentation_scope_v1(info.session);opts=read_opts(cfg);enabled=pd_enabled_graphs_local(cfg);module_cache=struct('prepared_3d',false,'info',info);
    meta2=struct();
    for graph={'plot.dataset.xy','plot.dataset.xy_region'}
      g=graph{1};if(any(strcmp(enabled,g)))
        fld=cache_field(g);P=pd_prepare_2d(info,cfg,opts,g);module_cache.(fld)=P;module_cache.(['prepared_' fld])=true;meta2.(fld)=pd_prep_fingerprint(info,cfg,opts,'2d',g);
      endif
    endfor
    if(any(strcmp(enabled,'plot.dataset.xyz')))
      if(isempty(info.x)||isempty(info.y)||isempty(info.z)),error('plot.dataset: enabled 3D graph requires X, Y and Z bindings');endif
      if(isempty(info.source_path)),error('plot.dataset: enabled 3D graph requires the primary dataset source');endif
      ptype=lower(strtrim(gxtxt_ini_get(cfg,'plot.plot.dataset.xyz.plot_type','scatter3')));opts3d=pd_3d_options(cfg,opts);module_cache.plot3d=pd_prepare_3d(info,cfg,opts3d,ptype,config_path);module_cache.prepared_3d=true;
    endif
    [module_cache,~]=pd_coordinate_capture(module_cache,cfg,enabled);
    for graph={'plot.dataset.xy','plot.dataset.xy_region'}
      if(any(strcmp(enabled,graph{1}))),fld=cache_field(graph{1});module_cache.(fld)=pd_attach_x_region_selection(module_cache.(fld),cfg,graph{1});endif
    endfor
    sources=pd_source_map(cfg,info,enabled);meta=gxtxt_render_cache_standard_meta('plot.dataset','3.18.0','',sources,struct());meta.prep2d=meta2;meta.prep3d_fingerprint='';
    if(module_cache.prepared_3d),meta.prep3d_fingerprint=pd_prep_fingerprint(info,cfg,opts3d,'3d');endif
    cache=struct('meta',meta,'module',module_cache);gxtxt_render_cache_save(outdir,cache);pd_write_summary(fullfile(outdir,'plot_summary.txt'),info,opts,module_cache,enabled,meta);
    gxtxt_progress_stage('rendering','Rendering scientific dataset plots','indeterminate');plot_dataset_render(outdir,cfg,module_cache);pd_coordinate_receipt(outdir,module_cache,enabled);gxtxt_progress_complete('done','Scientific Dataset Plot completed');
  catch err;try gxtxt_progress_fail('failed','Scientific Dataset Plot failed; see log for details');catch;end_try_catch;rethrow(err);end_try_catch
endfunction
function fld=cache_field(graph),if(strcmp(graph,'plot.dataset.xy')),fld='plot2d_xy';else fld='plot2d_xy_region';endif;endfunction
function opts=read_opts(cfg),opts=struct();opts.reduction_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.reduction_mode','auto')));if(!any(strcmp(opts.reduction_mode,{'auto','none','stride','minmax'}))),opts.reduction_mode='auto';endif;opts.target_points=parse_int(gxtxt_ini_get(cfg,'config.target_points','6000'),6000,100);opts.auto_reduce_threshold=parse_int(gxtxt_ini_get(cfg,'config.auto_reduce_threshold','12000'),12000,100);opts.chunk_rows=parse_int(gxtxt_ini_get(cfg,'config.chunk_rows','5000'),5000,100);endfunction
function v=parse_int(s,d,minv),v=str2double(s);if(!isfinite(v)),v=d;endif;v=max(minv,round(v));endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function out=pd_enabled_graphs_local(cfg),s=strrep(gxtxt_ini_get(cfg,'graph_provider.enabled','plot.dataset.xy'),',',';');a=strsplit(s,';');out={};for i=1:numel(a),q=strtrim(a{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
