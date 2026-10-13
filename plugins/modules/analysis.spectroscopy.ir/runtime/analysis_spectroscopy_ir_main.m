function analysis_spectroscopy_ir_main(args)
% Dataset-native IR spectroscopy/reference matching with public numerical and plotting services.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.spectroscopy.ir';module_version='1.1.1';
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  root=framework_root();discover_numeric_api(cfg,module_id);discover_plot_service(root,module_id);
  runner=fullfile(fileparts(mfilename('fullpath')),'ir_pipeline.tcl');bridge=fullfile(root,'core','tcl','analysis_tcl_bridge_v1.tcl');
  gxtxt_progress_start('analysis','Running IR preprocessing, peak extraction and reference matching','indeterminate');
  try
    cmd=sprintf('tclsh %s %s %s %s',gxtxt_shell_quote_v1(bridge),gxtxt_shell_quote_v1(root),gxtxt_shell_quote_v1(runner),gxtxt_shell_quote_v1(config_path));
    [status,output]=system(cmd);if(status!=0),error('%s pipeline failed: %s',module_id,output);endif
    overlay_dataset=marker_value(output,'OVERLAY_DATASET=');if(isempty(overlay_dataset)),error('%s: pipeline returned no overlay Dataset',module_id);endif
    has_reference=strcmp(marker_value(output,'HAS_REFERENCE='),'1');
    gxtxt_progress_stage('plot','Creating persistent plot.dataset IR overlay','indeterminate');
    graph=create_overlay_plot(session,overlay_dataset,has_reference,module_id);copy_graph_artifact(graph,outdir,module_id);write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graph,has_reference);
    gxtxt_progress_complete('done',sprintf('IR analysis completed; persistent plot.dataset overlay uses %s',overlay_dataset));
    fprintf('%s',output);fprintf('[%s] version=%s overlay_dataset=%s reference=%d graph_variant=%s validation=PASS\n',module_id,module_version,overlay_dataset,has_reference,graph.variant_id);
  catch err
    try gxtxt_progress_fail('failed','IR spectroscopy analysis failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function discover_numeric_api(cfg,module_id)
  sec='public_api.NUMERIC_API_v1';provider=strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],''));if(!strcmp(provider,'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif
  if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.api_version'],'')),'1')),error('%s: unsupported runtime NUMERIC_API_v1 version',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));required={'vector_normalization','vector_similarity','grid_analysis','uniform_grid','common_range','descriptive_statistics','interpolation','resampling','differentiation','smoothing','peak_detection','baseline_estimation'};
  for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif;endfor
endfunction

function discover_plot_service(root,module_id)
  pd=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(pd,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif
  d=gxtxt_ini_read(pd);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.PLOT_DATASET_API_v2.capabilities',''));required={'series_kind_line','multi_dataset','axis_direction'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: PLOT_DATASET_API_v2 capability missing: %s',module_id,required{k});endif;endfor
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable',module_id);endif;addpath(fileparts(bridge));
endfunction

function R=create_overlay_plot(session,dataset_id,has_reference,module_id)
  axes=struct('x',struct('label','Wavenumber [cm^-1]','display_unit','cm^-1','scale','linear','direction','reverse'),'y_left',struct('label','Comparable relative intensity','display_unit','1','scale','linear'));
  s1=struct('id','experimental_ir','dataset_id',dataset_id,'x_variable_id','wavenumber','y_variable_id','experimental_intensity','axis','left','kind','line','label','Experimental IR','style',struct('line_width','2.2'));
  series={s1};
  if(has_reference)
    s2=struct('id','reference_candidate','dataset_id',dataset_id,'x_variable_id','wavenumber','y_variable_id','reference_intensity','axis','left','kind','line','label','Top-ranked reference candidate','style',struct('line_style','dashed','line_width','1.5'));
    series{end+1}=s2;
    title_text='IR spectrum and top-ranked reference candidate';
  else
    title_text='Processed IR spectrum';
  endif
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series});spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));if(!isfield(R,'artifact')||isempty(strtrim(R.artifact))),error('%s: plot.dataset returned no IR overlay artifact',module_id);endif;R.key='ir_overlay';
endfunction

function copy_graph_artifact(R,outdir,module_id)
  src=strtrim(R.artifact);if(isempty(src)||exist(src,'file')!=2),error('%s: plot.dataset IR overlay artifact missing',module_id);endif
  [ok,msg]=copyfile(src,fullfile(outdir,'01_ir_overlay.png'),'f');if(!ok),error('%s: cannot copy plot.dataset IR overlay: %s',module_id,msg);endif
endfunction

function write_graph_manifest(path,R,has_reference)
  fid=fopen(path,'w');if(fid<0),error('analysis.spectroscopy.ir: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=1\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n');
    fprintf(fid,'\n[graph.01]\nkey=ir_overlay\ngraph_id=%s\nvariant_id=%s\npng=01_ir_overlay.png\nprovider_artifact=%s\nreference_series=%d\naxis_direction=reverse\nrerender=Use the persisted plot.dataset variant\n',ini_escape(R.graph_id),ini_escape(R.variant_id),ini_escape(R.artifact),has_reference);
  unwind_protect_cleanup fclose(fid);end_unwind_protect
endfunction

function value=marker_value(output,marker)
  pos=strfind(output,marker);value='';if(isempty(pos)),return;endif;tail=output(pos(end)+length(marker):end);stop=find(tail==sprintf('\n'),1);if(!isempty(stop)),tail=tail(1:stop-1);endif;value=strtrim(tail);
endfunction
function root=framework_root(),runtime_dir=fileparts(mfilename('fullpath'));module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);root=fileparts(plugins_dir);endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif;endfor;endfunction
