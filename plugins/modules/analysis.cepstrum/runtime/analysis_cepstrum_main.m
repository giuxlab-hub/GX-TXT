function analysis_cepstrum_main(args,framework_root)
% Dataset-native real-cepstrum analysis.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.cepstrum';module_version='1.1.1';
  P=struct();publication_open=false;publication_finalized=false;

  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif

  gxtxt_progress_start('prepare','Preparing cepstrum analysis','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary Dataset ID is missing',module_id);endif

    time_binding=binding_column(gxtxt_ini_get(cfg,'bindings.independent',''),'independent');
    signal_binding=binding_column(gxtxt_ini_get(cfg,'bindings.signal',''),'signal');
    if(isempty(time_binding)||isempty(signal_binding)),error('%s: Independent and Signal bindings are required',module_id);endif

    [time_unit,~,time_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',time_binding);
    [signal_unit,~,signal_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',signal_binding);
    if(!meta_found(time_meta)||!meta_found(signal_meta)),error('%s: selected bindings could not be resolved',module_id);endif
    time_id=strtrim(time_meta.variable_id);signal_id=strtrim(signal_meta.variable_id);
    time_name=strtrim(time_meta.name);signal_name=strtrim(signal_meta.name);
    if(isempty(time_id)||isempty(signal_id)||strcmp(time_id,signal_id)),error('%s: stable and distinct variable IDs are required',module_id);endif
    if(isempty(time_name)),time_name=time_id;endif
    if(isempty(signal_name)),signal_name=signal_id;endif
    try
      if(!gxtxt_unit_compatible(time_unit,'s')),error('%s: independent variable unit %s is not time-compatible',module_id,time_unit);endif
    catch e
      error('%s: independent variable unit %s cannot be used as time: %s',module_id,time_unit,e.message);
    end_try_catch

    window_name=choice(gxtxt_ini_get(cfg,'config.window','rectangular'),'rectangular',{'rectangular','hann','hamming','blackman_harris','flat_top'});
    detrend_mode=choice(gxtxt_ini_get(cfg,'config.detrend','mean'),'mean',{'none','mean','linear'});
    log_floor_db=parse_number(gxtxt_ini_get(cfg,'config.log_floor_db','-240'),module_id,'log_floor_db');
    min_frequency_hz=parse_number(gxtxt_ini_get(cfg,'config.min_frequency_hz','20'),module_id,'min_frequency_hz');
    max_frequency_hz=parse_number(gxtxt_ini_get(cfg,'config.max_frequency_hz','2000'),module_id,'max_frequency_hz');
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','cepstrum.result'));
    if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid output Dataset ID',module_id);endif
    if(strcmp(output_dataset_id,source_dataset_id)),error('%s: output Dataset ID must differ from source Dataset ID',module_id);endif

    numeric=discover_numeric_api(cfg,module_id);
    discover_plot_api(framework_root,module_id);

    gxtxt_progress_stage('load_dataset','Reading time-series Dataset','indeterminate');
    [t,x,source_provider]=read_pairs(cfg,time_id,signal_id);
    if(numel(x)<16),error('%s: at least 16 samples are required',module_id);endif
    if(any(!isfinite(t))||any(!isfinite(x))),error('%s: source contains non-finite time/signal values',module_id);endif
    if(any(diff(t)<=0)),error('%s: independent time coordinate must be strictly increasing',module_id);endif

    t_seconds=gxtxt_unit_convert(t,time_unit,'s');
    grid=feval(numeric.function_name,'grid_info',t_seconds,struct('rtol',1e-6,'atol',0));
    if(!isfield(grid,'strict_monotonic')||!grid.strict_monotonic),error('%s: independent time coordinate must be strictly increasing',module_id);endif
    if(!isfield(grid,'uniform')||!grid.uniform),error('%s: real cepstrum requires uniform sampling; public NUMERIC_API_v1 grid validation rejected the time grid',module_id);endif
    dt_seconds=double(grid.step);if(!isfinite(dt_seconds)||dt_seconds<=0),error('%s: cannot resolve a positive sample interval',module_id);endif
    interval_dev=double(grid.relative_max_step_deviation);

    gxtxt_progress_stage('transform','Computing real cepstrum','indeterminate');
    R=cepstrum_compute(x,dt_seconds,window_name,detrend_mode,log_floor_db,min_frequency_hz,max_frequency_hz,numeric.function_name);

    provenance=sprintf('%s %s; source=%s; time=%s; signal=%s; window=%s; detrend=%s; log_floor_db=%.12g; search_hz=[%.12g,%.12g]', ...
      module_id,module_version,source_dataset_id,time_id,signal_id,window_name,detrend_mode,log_floor_db,min_frequency_hz,max_frequency_hz);
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{time_id,signal_id}}, ...
      'source',source_dataset_id,'provenance',provenance, ...
      'notes','Real cepstrum derived from a uniformly sampled signal. Non-zero quefrency structure is invariant to constant amplitude scaling apart from numerical flooring effects.');

    nout=numel(R.quefrency);
    gxtxt_progress_stage('publish','Publishing cepstrum Dataset','determinate',nout);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'quefrency',0,true);
    P=gxtxt_publication_v2_declare_variable(P,'quefrency_s',struct('dtype','float64','dimension_ids','quefrency','name','quefrency','unit','s','semantic_role','independent','coordinate_role','data','axis_kind','none'));
    P=gxtxt_publication_v2_declare_variable(P,'real_cepstrum',struct('dtype','float64','dimension_ids','quefrency','name','real_cepstrum','unit','1','semantic_role','measured','coordinate_role','data','axis_kind','none'));
    P=gxtxt_publication_v2_append(P,'quefrency',{'quefrency_s',double(R.quefrency);'real_cepstrum',double(R.real_cepstrum)});
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);[P,pub_result]=gxtxt_publication_v2_finalize(P);
    publication_finalized=true;publication_open=false;

    write_metrics(fullfile(outdir,'cepstrum_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,time_id,signal_id,time_name,signal_name,time_unit,signal_unit,source_provider,interval_dev,R,P.provider);
    write_report(fullfile(outdir,'cepstrum_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,time_name,time_id,time_unit,signal_name,signal_id,signal_unit,interval_dev,R,pub_diag,pub_result);

    gxtxt_progress_stage('plot','Creating persistent plot.dataset graph','indeterminate');
    graph_result=create_cepstrum_graph(session,output_dataset_id,R,module_id);
    copy_plot_artifact(graph_result.artifact,fullfile(outdir,'01_real_cepstrum.png'),module_id);
    write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graph_result);

    gxtxt_progress_complete('done',sprintf('Published %s; dominant cepstral periodicity %.9g s (%.9g Hz)',output_dataset_id,R.peak_quefrency_s,R.estimated_frequency_hz));
    fprintf('[%s] version=%s source=%s output=%s q_peak_s=%.12g f_est_hz=%.12g validation=PASS\n',module_id,module_version,source_dataset_id,output_dataset_id,R.peak_quefrency_s,R.estimated_frequency_hz);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    try gxtxt_progress_fail('failed','Cepstrum analysis failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function [t,x,provider]=read_pairs(cfg,time_id,signal_id)
  S=gxtxt_table_stream_open_source(cfg,'primary',{time_id,signal_id},65536,struct('start',0,'count',-1,'require_direct',false));
  provider=S.storage_provider;tc={};xc={};
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows>0),tc{end+1}=double(C.values{1}(:));xc{end+1}=double(C.values{2}(:));endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(isempty(tc)),t=zeros(0,1);x=zeros(0,1);else,t=vertcat(tc{:});x=vertcat(xc{:});endif
endfunction

function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('analysis.cepstrum: invalid %s binding',role);endif;endfunction
function v=choice(raw,def,allowed),v=lower(strtrim(raw));if(!any(strcmp(v,allowed))),v=def;endif;endfunction
function v=parse_number(raw,id,name),v=str2double(strtrim(raw));if(!isfinite(v)),error('%s: %s must be finite',id,name);endif;endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif,endfor,endfunction

function discover_plot_api(root,module_id)
  descriptor=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(descriptor,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif
  d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge is unavailable',module_id);endif
endfunction
function api=discover_numeric_api(cfg,module_id)
  sec='public_api.NUMERIC_API_v1';provider=strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],''));if(!strcmp(provider,'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif
  if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.api_version'],'')),'1')),error('%s: unsupported runtime NUMERIC_API_v1 version',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));required={'grid_analysis','fft','ifft','detrending','window_generation','polynomial_fit'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
  entry_path=strtrim(gxtxt_ini_get(cfg,[sec '.octave_entrypoint'],''));fn=strtrim(gxtxt_ini_get(cfg,[sec '.octave_function'],''));if(isempty(entry_path)||isempty(fn)||exist(entry_path,'file')!=2),error('%s: runtime NUMERIC_API_v1 Octave binding is unavailable',module_id);endif
  addpath(fileparts(entry_path));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif
  api=struct('function_name',fn,'provider',provider);
endfunction
function result=create_cepstrum_graph(session,dataset_id,R,module_id)
  if(exist('gxtxt_plot_dataset_v2','file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge is unavailable',module_id);endif
  xmax=max(4*R.peak_quefrency_s,R.search_qmin_s+20*R.dt_seconds);xmax=min(max(R.quefrency),xmax);
  axes=struct('x',struct('label','Quefrency [s]','display_unit','s','scale','linear','min',R.search_qmin_s,'max',xmax),'y_left',struct('label','Real cepstrum','scale','linear'));
  series=struct('id','real_cepstrum','dataset_id',dataset_id,'x_variable_id','quefrency_s','y_variable_id','real_cepstrum','axis','left','kind','line','label','Real cepstrum');
  annotation=struct('type','reference_line','axis','x','value',R.peak_quefrency_s,'label',sprintf('Detected period %.6g s',R.peak_quefrency_s),'line_style','dashed');
  panel=struct('id','main','title','Real cepstrum','axes',axes,'series',{{series}},'annotations',{{annotation}});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','Real cepstrum','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  result=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
endfunction
function copy_plot_artifact(source,destination,module_id)
  if(isempty(strtrim(source))||exist(source,'file')!=2),error('%s: plot.dataset did not return a readable graph artifact',module_id);endif
  [ok,msg]=copyfile(source,destination,'f');if(!ok||exist(destination,'file')!=2),error('%s: cannot copy plot.dataset graph artifact: %s',module_id,msg);endif
endfunction
function write_graph_manifest(path,result)
  fid=fopen(path,'w');if(fid<0),error('analysis.cepstrum: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=1\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n');
    fprintf(fid,'\n[graph.01]\nkey=real_cepstrum\ngraph_id=%s\nvariant_id=%s\npng=01_real_cepstrum.png\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',ini_escape(result.graph_id),ini_escape(result.variant_id),ini_escape(result.artifact));
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif,endfor,endfunction

function write_metrics(path,id,ver,src,outid,tid,sid,tname,sname,tunit,sunit,src_provider,interval_dev,R,out_provider)
  fh=fopen(path,'w');if(fh<0),error('%s: cannot write metrics',id);endif
  unwind_protect
    fprintf(fh,'; GX-TXT analysis.cepstrum metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n',id,ver);
    fprintf(fh,'\n[source]\ndataset_id=%s\ntime_variable_id=%s\nsignal_variable_id=%s\ntime_name=%s\nsignal_name=%s\ntime_unit=%s\nsignal_unit=%s\nstorage_provider=%s\n',src,tid,sid,ini_escape(tname),ini_escape(sname),ini_escape(tunit),ini_escape(sunit),src_provider);
    fprintf(fh,'\n[analysis]\nsamples=%d\nsample_rate_hz=%.17g\nsample_interval_s=%.17g\nrelative_interval_deviation=%.17g\nwindow=%s\ndetrend=%s\nlog_floor_db=%.17g\n',R.N,R.fs,R.dt_seconds,interval_dev,R.window_name,R.detrend_mode,R.log_floor_db);
    fprintf(fh,'search_min_frequency_hz=%.17g\nsearch_max_frequency_hz=%.17g\nsearch_qmin_s=%.17g\nsearch_qmax_s=%.17g\npeak_quefrency_s=%.17g\nestimated_frequency_hz=%.17g\npeak_value=%.17g\n',R.search_min_frequency_hz,R.search_max_frequency_hz,R.search_qmin_s,R.search_qmax_s,R.peak_quefrency_s,R.estimated_frequency_hz,R.peak_value);
    fprintf(fh,'\n[output]\ndataset_id=%s\nstorage_provider=%s\n',outid,out_provider);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction

function write_report(path,id,ver,src,outid,tname,tid,tunit,sname,sid,sunit,interval_dev,R,pub_diag,pub_result)
  fh=fopen(path,'w');if(fh<0),error('%s: cannot write report',id);endif
  unwind_protect
    fprintf(fh,'GX-TXT Cepstrum Analysis\n========================\n\n');
    fprintf(fh,'Plugin: %s %s\nSource Dataset: %s\nTime: %s (%s) [%s]\nSignal: %s (%s) [%s]\n',id,ver,src,tname,tid,tunit,sname,sid,sunit);
    fprintf(fh,'Samples: %d\nSample rate: %.12g Hz\nRelative sample-interval deviation: %.6g\nWindow: %s\nDetrend: %s\nLog-magnitude floor: %.6g dB relative to spectral peak\n',R.N,R.fs,interval_dev,R.window_name,R.detrend_mode,R.log_floor_db);
    fprintf(fh,'\nFundamental-period search\n-------------------------\nFrequency interval: %.12g .. %.12g Hz\nQuefrency interval: %.12g .. %.12g s\nDetected quefrency peak: %.12g s\nEquivalent frequency: %.12g Hz\nPeak value: %.12g\n',R.search_min_frequency_hz,R.search_max_frequency_hz,R.search_qmin_s,R.search_qmax_s,R.peak_quefrency_s,R.estimated_frequency_hz,R.peak_value);
    fprintf(fh,'\nDefinition\n----------\nThe real cepstrum is computed as real(IFFT(log(max(abs(FFT(x*w)), floor)))).\n');
    fprintf(fh,'The reported dominant periodicity is the maximum positive-quefrency cepstral peak inside the configured search interval. Cepstral peaks can also occur at integer multiples of the fundamental period, so the search interval remains part of the scientific configuration.\n');
    fprintf(fh,'\nPublished Dataset\n-----------------\nDataset ID: %s\nContract: table.generic\nColumns: quefrency_s, real_cepstrum\n',outid);
    fprintf(fh,'\nPublication diagnostics: %s\nPublication result: %s\n',pub_diag,pub_result);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction
