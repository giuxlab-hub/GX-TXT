function analysis_time_dependent_fft_main(args)
% Dataset-native time-dependent FFT analysis over a GX-TXT Temporal Window Set.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id='analysis.time_dependent_fft';
  module_version='1.3.3';
  io_chunk_rows=65536;
  timing_tolerance=1e-6;

  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  octave_cmd=strtrim(gxtxt_ini_get(cfg,'runtime.octave_cmd','octave-cli'));
  if(isempty(outdir)),error('%s: runtime.output_dir missing',module_id);endif
  if(isempty(session)),error('%s: runtime.session missing',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif

  tmpdir='';P=struct();publication_open=false;publication_finalized=false;
  gxtxt_progress_start('prepare','Preparing time-dependent FFT analysis','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif

    time_binding=binding_variable(gxtxt_ini_get(cfg,'bindings.time',''),'time');
    signal_binding=binding_variable(gxtxt_ini_get(cfg,'bindings.signal',''),'signal');
    if(isempty(time_binding)||isempty(signal_binding)),error('%s: time and signal bindings are required',module_id);endif

    [time_unit,~,time_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',time_binding);
    [signal_unit,~,signal_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',signal_binding);
    source_dataset_metadata=gxtxt_analysis_source_dataset_metadata(cfg,'primary');
    if(!isfield(time_meta,'found')||!time_meta.found),error('%s: time binding could not be resolved: %s',module_id,time_binding);endif
    if(!isfield(signal_meta,'found')||!signal_meta.found),error('%s: signal binding could not be resolved: %s',module_id,signal_binding);endif
    time_id=strtrim(time_meta.variable_id);signal_id=strtrim(signal_meta.variable_id);
    if(isempty(time_id)||isempty(signal_id)),error('%s: stable Variable IDs are required',module_id);endif

    M=gxtxt_table_stream_open_source(cfg,'primary',{time_id,signal_id},1,struct('start',0,'count',0,'require_direct',false));
    source_provider=M.storage_provider;source_row_count=M.row_count;schema=M.schema;M=gxtxt_table_stream_close(M);
    time_schema=find_schema(schema,time_id);signal_schema=find_schema(schema,signal_id);
    if(isempty(time_schema)||isempty(signal_schema)),error('%s: selected variables are missing from the canonical schema',module_id);endif

    T=gxtxt_temporal_set_from_runtime(cfg,'temporal_set');
    if(!T.enabled),error('%s: an existing Temporal Window Set is required',module_id);endif
    if(!strcmp(T.type,'window_set')),error('%s: only Temporal Set window_set resources are supported',module_id);endif
    if(!strcmp(T.source_dataset_id,source_dataset_id)),error('%s: Temporal Set %s belongs to Dataset %s, not %s',module_id,T.id,T.source_dataset_id,source_dataset_id);endif
    if(!strcmp(T.temporal_variable_id,time_id)),error('%s: Temporal Set %s uses temporal variable %s, not bound variable %s',module_id,T.id,T.temporal_variable_id,time_id);endif
    if(T.member_count<1),error('%s: Temporal Window Set %s resolves to no windows',module_id,T.id);endif
    % The compact peak and mean cache retains at least one value per window.
    % Reject an impossible budget before allocating jobs or publishing data.
    if(T.member_count>4000000)
      error('%s: %d windows exceed the 4,000,000-value display-cache budget; choose a coarser Temporal Set',module_id,T.member_count);
    endif

    window_name=lower(strtrim(gxtxt_ini_get(cfg,'config.window','hann')));
    allowed_windows={'rectangular','hann','hamming','blackman','blackman_harris','flat_top'};
    if(!any(strcmp(window_name,allowed_windows))),error('%s: unsupported FFT window: %s',module_id,window_name);endif
    detrend_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.detrend','mean')));
    if(!any(strcmp(detrend_mode,{'none','mean','linear'}))),error('%s: unsupported detrend mode: %s',module_id,detrend_mode);endif
    nfft_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.nfft_mode','auto')));
    if(!any(strcmp(nfft_mode,{'auto','explicit'}))),error('%s: unsupported NFFT mode: %s',module_id,nfft_mode);endif
    representation=lower(strtrim(gxtxt_ini_get(cfg,'config.spectral_representation','amplitude')));
    if(!any(strcmp(representation,{'amplitude','psd','amplitude_db'}))),error('%s: unsupported spectral representation: %s',module_id,representation);endif
    workers=normalize_workers(gxtxt_ini_get(cfg,'config.workers','auto'));
    run_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.run_mode','auto')));
    if(!any(strcmp(run_mode,{'auto','recalculate','render_only'}))),error('%s: invalid run mode: %s',module_id,run_mode);endif

    nominal_window_rows=T.resolved_window_rows;
    if(nominal_window_rows<2),error('%s: resolved Temporal Set window size must be at least 2 samples',module_id);endif
    if(strcmp(nfft_mode,'auto'))
      nfft=nominal_window_rows;
    else
      nfft=parse_positive_integer(gxtxt_ini_get(cfg,'config.nfft',''));
      if(!isfinite(nfft)||nfft<nominal_window_rows),error('%s: explicit NFFT must be an integer >= resolved full window size (%d)',module_id,nominal_window_rows);endif
    endif
    bin_count=floor(nfft/2)+1;

    % Plot-only reuse is keyed only by scientific inputs. Plot/export settings and worker count do not invalidate it.
    source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));source_stamp=tdfft_source_stamp(source_path);
    scientific_fp=tdfft_scientific_fingerprint(source_dataset_id,source_stamp,time_id,signal_id,T,window_name,detrend_mode,nfft_mode,nfft,representation);
    sources=struct(); % Do not hash the potentially huge canonical Dataset merely to decide whether plotting can reuse cached spectra.
    cache_params=struct('scientific_fingerprint',scientific_fp);
    expected_meta=gxtxt_render_cache_standard_meta(module_id,module_version,'',sources,cache_params);
    expected_cache=struct('module_id',module_id,'source_fingerprint',expected_meta.source_fingerprint,'parameter_fingerprint',expected_meta.parameter_fingerprint);
    % Plot Module API v1 variants are presentation-only for this module.
    % CORE schedules a variant as its own standard_octave job and gives it an isolated output directory.
    % Reuse the already-computed base scientific cache instead of launching FFT workers again.
    variant_graph=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));
    variant_id=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));
    if(!isempty(variant_graph)&&!isempty(variant_id))
      base_outdir=fullfile(session,'analysis',module_id);
      base_cache_path=gxtxt_render_cache_path(base_outdir);
      if(exist(base_cache_path,'file')!=2)
        error('%s: plot variant %s/%s requires a current base FFT cache; run the base analysis once first',module_id,variant_graph,variant_id);
      endif
      base_cache=gxtxt_render_cache_load(base_cache_path);
      vrep=gxtxt_render_cache_validate(base_cache,expected_cache);
      variant_cache_ok=vrep.valid && tdfft_cache_version_supported(base_cache) && isfield(base_cache,'module') && isfield(base_cache.module,'scientific_fingerprint') && strcmp(base_cache.module.scientific_fingerprint,scientific_fp);
      if(!variant_cache_ok)
        reason='scientific fingerprint mismatch';if(!vrep.valid),reason=strjoin(vrep.errors,',');endif
        error('%s: plot variant %s/%s cannot reuse the base FFT cache (%s); run the base analysis once with the current scientific settings',module_id,variant_graph,variant_id,reason);
      endif
      gxtxt_progress_stage('variant_render',sprintf('Rendering variant %s/%s from base FFT cache',variant_graph,variant_id),'indeterminate');
      gxtxt_render_cache_save(outdir,base_cache);
      copy_required_base_output(base_outdir,outdir,'time_dependent_fft_report.txt');
      copy_required_base_output(base_outdir,outdir,'plot_dataset_recipe.txt');
      remove_tree_if_present(fullfile(outdir,'window_exports'));
      write_simple_text(fullfile(outdir,'split_export_index.txt'),'Plot variant render: no scientific per-window data export was repeated.\n');
      analysis_time_dependent_fft_render(outdir,cfg,base_cache.module);
      gxtxt_progress_complete('done',sprintf('Rendered plot variant %s/%s without FFT recomputation',variant_graph,variant_id));
      return;
    endif
    cache_path=gxtxt_render_cache_path(outdir);cache_ok=false;cache_reason='cache_missing';cached=struct();
    if(exist(cache_path,'file')==2)
      try
        cached=gxtxt_render_cache_load(cache_path);rep=gxtxt_render_cache_validate(cached,expected_cache);
        cache_ok=rep.valid && tdfft_cache_version_supported(cached) && isfield(cached,'module') && isfield(cached.module,'scientific_fingerprint') && strcmp(cached.module.scientific_fingerprint,scientific_fp) && ...
          exist(fullfile(outdir,'time_dependent_fft_report.txt'),'file')==2 && exist(fullfile(outdir,'plot_dataset_recipe.txt'),'file')==2;
        if(!rep.valid),cache_reason=strjoin(rep.errors,',');elseif(!cache_ok),cache_reason='cache_payload_or_required_outputs_missing';else cache_reason='valid';endif
      catch cacheerr
        cache_ok=false;cache_reason=cacheerr.message;
      end_try_catch
    endif
    if(!strcmp(run_mode,'recalculate') && cache_ok)
      gxtxt_progress_stage('render','Reusing compatible FFT result; rendering without recomputation','indeterminate');
      tdfft_split_export_from_dataset(outdir,cfg,cached.module);
      analysis_time_dependent_fft_render(outdir,cfg,cached.module);
      gxtxt_progress_complete('done',sprintf('Reused cached FFT result: %d windows x %d display-cache bins',cached.module.window_count,cached.module.plot_cache.bin_count));
      return;
    endif
    if(strcmp(run_mode,'render_only'))
      error('%s: Render only requested but no compatible FFT cache is available (%s). Run once with Auto or Recalculate.',module_id,cache_reason);
    endif

    numeric_api=tdfft_numeric_api(cfg);
    axis_kind=lower(strtrim(time_schema.axis_kind));
    axis_origin=str2double(strtrim(time_schema.axis_origin));
    axis_step=str2double(strtrim(time_schema.axis_step));
    temporal_numeric_unit=strtrim(T.temporal_unit);
    if(isfield(time_meta,'value_kind')&&strcmpi(strtrim(time_meta.value_kind),'elapsed_time'))
      temporal_numeric_unit='s';
    elseif(isempty(temporal_numeric_unit))
      temporal_numeric_unit=strtrim(time_unit);
    endif
    if(isempty(temporal_numeric_unit)),error('%s: temporal variable needs a physical elapsed-time unit',module_id);endif

    if(strcmp(axis_kind,'uniform'))
      if(!isfinite(axis_origin)||!isfinite(axis_step)||axis_step<=0),error('%s: invalid canonical uniform time axis',module_id);endif
      dt_numeric=axis_step;timing_relative_deviation=0;
    else
      gxtxt_progress_stage('sampling_check','Validating explicit temporal sampling','indeterminate');
      S=scan_explicit_timing(cfg,time_id,T.effective_row_start,T.effective_row_count,io_chunk_rows,numeric_api);
      dt_numeric=S.mean_step;timing_relative_deviation=S.relative_deviation;
      if(timing_relative_deviation>timing_tolerance)
        error('%s: time variable is not uniformly sampled enough for FFT processing (relative interval deviation %.6g > %.6g)',module_id,timing_relative_deviation,timing_tolerance);
      endif
    endif
    try
      dt_seconds=gxtxt_unit_convert(dt_numeric,temporal_numeric_unit,'s');
    catch uniterr
      error('%s: temporal unit %s cannot be converted to seconds: %s',module_id,temporal_numeric_unit,uniterr.message);
    end_try_catch
    if(!isfinite(dt_seconds)||dt_seconds<=0),error('%s: resolved sample spacing in seconds is invalid',module_id);endif
    fs=1.0/dt_seconds;
    frequency_grid=feval(numeric_api,'frequency_grid',fs,nfft,struct('representation','one_sided','ordering','fft'));
    df=double(frequency_grid.df);

    members=cell(1,T.member_count);
    for i=1:T.member_count
      members{i}=gxtxt_temporal_set_member(T,i);
      if(members{i}.row_count<2),error('%s: Temporal Set member %s contains fewer than 2 samples',module_id,members{i}.member_id);endif
      if(members{i}.row_count>nfft),error('%s: Temporal Set member %s (%d samples) exceeds NFFT=%d',module_id,members{i}.member_id,members{i}.row_count,nfft);endif
    endfor

    run_token=sprintf('%d_%d',getpid(),round(1e6*rem(now(),1)));
    tmpdir=fullfile(outdir,['.tdfft_' run_token]);mkdir(tmpdir);
    worker_script=fullfile(fileparts(mfilename('fullpath')),'time_dependent_fft_worker.m');
    items=cell(1,T.member_count);result_paths=cell(1,T.member_count);
    for i=1:T.member_count
      Q=members{i};result_paths{i}=fullfile(tmpdir,sprintf('frame_%06d.bin',i));
      argv={octave_cmd,'--quiet','--no-gui',worker_script, ...
        '--runtime',config_path,'--item-id',Q.member_id,'--time-id',time_id,'--signal-id',signal_id, ...
        '--row-start',num2str(Q.row_start),'--row-count',num2str(Q.row_count),'--nfft',num2str(nfft), ...
        '--window',window_name,'--detrend',detrend_mode,'--representation',representation, ...
        '--dt-seconds',num2str(dt_seconds,17),'--axis-kind',axis_kind,'--axis-origin',num_text(axis_origin), ...
        '--axis-step',num_text(axis_step),'--timing-tolerance',num2str(timing_tolerance,17),'--result',result_paths{i}};
      items{i}=struct('id',Q.member_id,'argv',{argv});
    endfor

    par_info=gxtxt_parallel_execution_info_v1();
    thread_hint=max(1,round(par_info.recommended_internal_threads));
    par_options=struct('workers',workers,'fail_fast',true,'run_id',['tdfft-' run_token], ...
      'environment',{{'OMP_NUM_THREADS',num2str(thread_hint);'OPENBLAS_NUM_THREADS',num2str(thread_hint);'MKL_NUM_THREADS',num2str(thread_hint);'NUMEXPR_NUM_THREADS',num2str(thread_hint)}});
    gxtxt_progress_stage('fft_windows',sprintf('Processing %d Temporal Set windows',T.member_count),'determinate',T.member_count);
    parallel_result=gxtxt_parallel_execute_v1(items,par_options);
    if(strcmp(parallel_result.state,'cancelled')),error('%s: Parallel Execution run was cancelled',module_id);endif
    if(!strcmp(parallel_result.state,'completed'))
      error('%s: one or more Temporal Set FFT workers failed: %s',module_id,parallel_failure_summary(parallel_result));
    endif
    if(numel(parallel_result.results)!=T.member_count),error('%s: Parallel Execution returned an unexpected result count',module_id);endif
    for i=1:T.member_count
      rr=parallel_result.results{i};
      if(!strcmp(rr.id,members{i}.member_id)||!strcmp(rr.state,'success'))
        error('%s: deterministic work-item association failed at window %d',module_id,i);
      endif
    endfor

    pub_id=[safe_id(source_dataset_id) '.tdfft.' safe_id(signal_id) '.' safe_id(T.id)];
    provenance=sprintf('source_dataset=%s;time_variable=%s;signal_variable=%s;temporal_set=%s;temporal_type=window_set;window=%s;detrend=%s;nfft=%d;representation=%s;time_convention=sample_coordinate_midpoint;module=%s@%s', ...
      source_dataset_id,time_id,signal_id,T.id,window_name,detrend_mode,nfft,representation,module_id,module_version);
    notes=sprintf('Rectangular long-form time-frequency grid: X=time, Y=frequency, Z=spectral_value. Temporal segmentation is resolved by CORE Temporal Set API v1. Partial included windows are zero-padded to common NFFT=%d.',nfft);
    popts=struct('storage','auto','capabilities_required',{{'append_write'}}, ...
      'capabilities_preferred',{{'human_readable','sequential_chunks'}},'producer_version',module_version, ...
      'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{time_id,signal_id}}, ...
      'source',source_dataset_id,'provenance',provenance,'notes',notes,'replace_owned',true);
    P=gxtxt_publication_v2_open(session,module_id,pub_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'time_frequency_point',0,true);
    P=gxtxt_publication_v2_declare_variable(P,'time',struct('dtype','float64','dimension_ids',{{'time_frequency_point'}},'name','time','unit',temporal_numeric_unit,'semantic_role','independent','coordinate_role','coordinate','axis_kind','explicit'));
    P=gxtxt_publication_v2_declare_variable(P,'frequency',struct('dtype','float64','dimension_ids',{{'time_frequency_point'}},'name','frequency','unit','Hz','semantic_role','independent','coordinate_role','coordinate','axis_kind','explicit'));
    [value_unit,value_name]=representation_metadata(representation,signal_unit);
    P=gxtxt_publication_v2_declare_variable(P,'spectral_value',struct('dtype','float64','dimension_ids',{{'time_frequency_point'}},'name',value_name,'unit',value_unit,'semantic_role','measured','coordinate_role','data','axis_kind','none','coordinate_variable_ids',{{'time','frequency'}}));
    P=gxtxt_publication_v2_declare_variable(P,'window_index',struct('dtype','int32','dimension_ids',{{'time_frequency_point'}},'name','window_index','unit','','semantic_role','index','coordinate_role','auxiliary','axis_kind','none'));

    freq=double(frequency_grid.frequency(:));clear frequency_grid;
    % Build a compact visualization cache while full-resolution worker values are already in memory.
    % This avoids rereading the potentially huge long-form Dataset merely to draw pixels/vertices.
    plot_cache_max_values=4000000;plot_cache_target_bins=min(bin_count,4096);
    if(T.member_count>0),plot_cache_target_bins=min(plot_cache_target_bins,max(1,floor(plot_cache_max_values/T.member_count)));endif
    plot_plan=tdfft_reduction_plan(bin_count,plot_cache_target_bins,df);
    plot_peak=zeros(T.member_count,plot_plan.target_bins);plot_mean=zeros(T.member_count,plot_plan.target_bins);
    gxtxt_progress_stage('publish','Publishing canonical time-frequency Dataset','determinate',T.member_count);
    frame_sample_counts=zeros(T.member_count,1);time_centers=zeros(T.member_count,1);
    for i=1:T.member_count
      loaded=load(result_paths{i});if(!isfield(loaded,'R')),error('%s: worker result %d is invalid',module_id,i);endif
      R=loaded.R;
      if(!strcmp(R.item_id,members{i}.member_id)),error('%s: worker result identity mismatch at window %d',module_id,i);endif
      if(numel(R.values)!=bin_count),error('%s: worker result %s has %d bins, expected %d',module_id,R.item_id,numel(R.values),bin_count);endif
      if(any(!isfinite(R.values))),error('%s: worker result %s contains non-finite spectral values',module_id,R.item_id);endif
      time_centers(i)=R.time_center;frame_sample_counts(i)=R.sample_count;
      [pv,mv]=tdfft_reduce_values(R.values(:),plot_plan,numeric_api);plot_peak(i,:)=pv(:)';plot_mean(i,:)=mv(:)';
      block_time=repmat(R.time_center,bin_count,1);block_index=repmat(int32(i-1),bin_count,1);
      items_append={ 'time',block_time; 'frequency',freq; 'spectral_value',R.values(:); 'window_index',block_index };
      P=gxtxt_publication_v2_append(P,'time_frequency_point',items_append);
      gxtxt_progress_update(i,T.member_count,'publish',sprintf('Published window %d/%d',i,T.member_count));
    endfor
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    output_provider=P.provider;
    [P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;

    write_report(fullfile(outdir,'time_dependent_fft_report.txt'),module_id,module_version,source_dataset_id,time_id,signal_id,T, ...
      window_name,detrend_mode,nfft_mode,nfft,representation,value_unit,temporal_numeric_unit,fs,df,bin_count,source_provider, ...
      timing_relative_deviation,workers,parallel_result,par_info,output_provider,pub_id,pub_diag,pub_result,provenance,frame_sample_counts,time_centers,source_dataset_metadata);
    write_plot_recipe(fullfile(outdir,'plot_dataset_recipe.txt'),pub_id,representation,value_name,value_unit);

    member_ids=cell(T.member_count,1);for i=1:T.member_count,member_ids{i}=members{i}.member_id;endfor
    meta=gxtxt_render_cache_standard_meta(module_id,module_version,'',sources,cache_params);
    plot_cache=struct('frequency',plot_plan.frequency(:),'peak',plot_peak,'mean',plot_mean,'bin_count',plot_plan.target_bins, ...
      'source_bin_count',bin_count,'policy','common-frequency grouped peak+mean','max_values',plot_cache_max_values);
    module_cache=struct('dataset_id',pub_id,'source_dataset_id',source_dataset_id,'time_variable_id',time_id,'signal_variable_id',signal_id, ...
      'temporal_set_id',T.id,'window_count',T.member_count,'bin_count',bin_count,'nfft',nfft,'fs',fs,'df',df, ...
      'time_centers',time_centers(:),'member_ids',{member_ids},'time_unit',temporal_numeric_unit,'value_unit',value_unit,'value_name',value_name, ...
      'representation',representation,'window_name',window_name,'detrend_mode',detrend_mode,'scientific_fingerprint',scientific_fp,'plot_cache',plot_cache);
    cache=struct('meta',meta,'module',module_cache);gxtxt_render_cache_save(outdir,cache);

    gxtxt_progress_stage('render','Preparing requested plots/exports from cached FFT results','indeterminate');
    tdfft_split_export_from_results(outdir,cfg,module_cache,result_paths);
    analysis_time_dependent_fft_render(outdir,cfg,module_cache);
    if(exist(tmpdir,'dir')==7),rmdir(tmpdir,'s');endif;tmpdir='';
    gxtxt_progress_complete('done',sprintf('Published %s: %d windows x %d frequency bins',pub_id,T.member_count,bin_count));
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    if(!isempty(tmpdir)&&exist(tmpdir,'dir')==7),try rmdir(tmpdir,'s');catch;end_try_catch;endif
    try gxtxt_progress_fail('failed',err.message);catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function S=scan_explicit_timing(cfg,time_id,row_start,row_count,chunk_rows,numeric_api)
  st=gxtxt_table_stream_open_source(cfg,'primary',{time_id},chunk_rows,struct('start',row_start,'count',row_count,'require_direct',false,'numeric_transport','auto'));
  prev=NaN;acc=[];
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_v3_next(st);
      if(ch.nrows>0)
        t=gxtxt_table_chunk_numeric(ch,time_id);t=t(:);
        if(any(!isfinite(t))),error('analysis.time_dependent_fft: explicit temporal coordinate contains non-finite values');endif
        if(isfinite(prev)),d0=t(1)-prev;if(d0<=0),error('analysis.time_dependent_fft: temporal coordinates must be strictly increasing');endif;acc=feval(numeric_api,'reduce_accumulate',acc,d0);endif
        d=diff(t);if(any(d<=0)),error('analysis.time_dependent_fft: temporal coordinates must be strictly increasing');endif
        if(!isempty(d)),acc=feval(numeric_api,'reduce_accumulate',acc,d);endif
        prev=t(end);
      endif
      if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(isempty(acc)||acc.count<1),error('analysis.time_dependent_fft: at least two temporal samples are required');endif
  mean_step=acc.mean;relative_deviation=max(abs([acc.min-mean_step,acc.max-mean_step]))/max(abs(mean_step),realmin);
  S=struct('mean_step',mean_step,'min_step',acc.min,'max_step',acc.max,'relative_deviation',relative_deviation);
endfunction

function [unit,name]=representation_metadata(rep,signal_unit)
  su=strtrim(signal_unit);if(isempty(su)),su='1';endif
  switch(rep)
    case 'amplitude',unit=su;name='amplitude';
    case 'psd',unit=[su '^2/Hz'];name='power_spectral_density';
    case 'amplitude_db',unit='dB';name='amplitude_db_re_1_unit';
  endswitch
endfunction

function write_report(path,module_id,module_version,source_dataset_id,time_id,signal_id,T,window_name,detrend_mode,nfft_mode,nfft,representation,value_unit,time_unit,fs,df,bin_count,source_provider,timing_dev,workers,pr,pi,output_provider,pub_id,pub_diag,pub_result,provenance,counts,times,source_metadata)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write report',module_id);endif
  unwind_protect
    fprintf(fid,'GX-TXT Time-Dependent FFT\n==========================\n');
    fprintf(fid,'Module: %s %s\nPublished Dataset: %s\nSource Dataset: %s\nTime variable: %s\nSignal variable: %s\n',module_id,module_version,pub_id,source_dataset_id,time_id,signal_id);
    fprintf(fid,'Temporal Set: %s (window_set, %d members)\nGenerator basis: %s\nWindow size / step: %.17g / %.17g\nResolved rows: %d / %d\nPartial policy: %s\nParent Selection: %s\n',T.id,T.member_count,T.generator_basis,T.window_size,T.step,T.resolved_window_rows,T.resolved_step_rows,T.partial_policy,T.parent_selection_id);
    fprintf(fid,'FFT window: %s\nDetrend: %s\nNFFT mode: %s\nNFFT: %d\nFrequency bins: %d\nSample rate: %.17g Hz\nFrequency step: %.17g Hz\n',window_name,detrend_mode,nfft_mode,nfft,bin_count,fs,df);
    fprintf(fid,'Representation: %s\nSpectral unit: %s\nTime numeric unit: %s\nTime coordinate convention: midpoint of first and last sample coordinates in each resolved window\n',representation,value_unit,time_unit);
    fprintf(fid,'Source storage provider: %s\nSource Dataset Metadata entries visible through public runtime: %d\nExplicit-axis timing relative deviation: %.17g\n',source_provider,source_metadata.count,timing_dev);
    fprintf(fid,'Requested workers: %s\nEffective workers: %d\nParallel fallback: %s\nRecommended internal threads: %d\nParallel state: %s\n',workers,pr.worker_count,pr.fallback_reason,pi.recommended_internal_threads,pr.state);
    fprintf(fid,'Output provider selected by Storage Auto: %s\nOutput logical shape: %d windows x %d frequency bins (%d table rows)\n',output_provider,T.member_count,bin_count,T.member_count*bin_count);
    fprintf(fid,'Scientific provenance: %s\nPublication diagnostics: %s\nPublication result: %s\n',provenance,one_line(pub_diag),one_line(pub_result));
    fprintf(fid,'\nWindow summary\n');
    for i=1:numel(counts),Q=gxtxt_temporal_set_member(T,i);fprintf(fid,'%6d  %s  row_start=%d  samples=%d  time=%.17g\n',i,Q.member_id,Q.row_start,counts(i),times(i));endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_plot_recipe(path,pub_id,rep,value_name,value_unit)
  fid=fopen(path,'w');if(fid<0),error('analysis.time_dependent_fft: cannot write plot recipe');endif
  unwind_protect
    fprintf(fid,'GX-TXT plot.dataset recipe for Time-Dependent FFT\n==================================================\n');
    fprintf(fid,'Dataset: %s\n3D graph: Scientific dataset 3D\nX variable: time\nY variable: frequency\nZ variable: spectral_value\n',pub_id);
    fprintf(fid,'Recommended plot types: surface, mesh, contour3\nSpectral representation: %s\nZ label: %s [%s]\n',rep,value_name,value_unit);
    fprintf(fid,'The output is a complete rectangular long-form grid, so no interpolation is required.\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function s=parallel_failure_summary(R)
  parts={}; failed=0;
  for i=1:numel(R.results)
    q=R.results{i};
    if(strcmp(q.state,'success')||strcmp(q.state,'not_executed')),continue;endif
    failed+=1;
    if(numel(parts)>=8),continue;endif
    detail=one_line(q.stderr);
    if(isempty(detail)&&isfield(q,'error')),detail=one_line(q.error);endif
    if(isempty(detail)&&isfield(q,'error_code')),detail=one_line(q.error_code);endif
    parts{end+1}=sprintf('%s:%s:%s',q.id,q.state,detail);
  endfor
  if(isempty(parts)),s=R.state;else s=sprintf('%d failed work item(s): %s',failed,strjoin(parts,' | '));endif
endfunction
function s=one_line(s),s=strrep(char(s),sprintf('\r'),' ');s=strrep(s,sprintf('\n'),' ');endfunction
function s=num_text(v),if(isfinite(v)),s=sprintf('%.17g',v);else s='nan';endif;endfunction
function id=safe_id(s),id=regexprep(strtrim(s),'[^A-Za-z0-9_.-]','_');if(isempty(id)),id='dataset';endif;endfunction
function n=parse_positive_integer(s),n=str2double(strtrim(s));if(!isfinite(n)||n<1||n!=fix(n)),n=NaN;endif;endfunction
function w=normalize_workers(raw),w=lower(strtrim(raw));if(isempty(w)),w='auto';endif;if(any(strcmp(w,{'auto','serial'}))),return;endif;n=str2double(w);if(!isfinite(n)||n<1||n!=fix(n)),error('analysis.time_dependent_fft: workers must be auto, serial, or a positive integer');endif;w=num2str(n);endfunction
function v=arg_value(args,key,def),v=def;for i=1:numel(args)-1,if(strcmp(args{i},key)),v=args{i+1};return;endif;endfor;endfunction
function name=binding_variable(v,role),name=strtrim(v);if(isempty(name)||strcmp(name,'auto')),name='';return;endif;dot=find(name=='.',1);if(!isempty(dot)),src=strtrim(name(1:dot-1));if(!strcmp(src,'primary')),error('analysis.time_dependent_fft: binding %s must refer to primary.*, got %s',role,name);endif;name=strtrim(name(dot+1:end));endif;endfunction
function s=find_schema(schema,id),s=[];for i=1:numel(schema),if(strcmp(schema(i).variable_id,id)),s=schema(i);return;endif;endfor;endfunction

function copy_required_base_output(srcdir,dstdir,name)
  src=fullfile(srcdir,name);dst=fullfile(dstdir,name);
  if(exist(src,'file')!=2),error('analysis.time_dependent_fft: base output required by plot variant is missing: %s',src);endif
  [ok,msg]=copyfile(src,dst,'f');if(!ok),error('analysis.time_dependent_fft: cannot copy base output %s: %s',name,msg);endif
endfunction

function remove_tree_if_present(path)
  if(exist(path,'dir')==7),[ok,msg]=rmdir(path,'s');if(!ok),error('analysis.time_dependent_fft: cannot remove %s: %s',path,msg);endif;endif
endfunction

function write_simple_text(path,text)
  fid=fopen(path,'w');if(fid<0),error('analysis.time_dependent_fft: cannot write %s',path);endif
  unwind_protect fputs(fid,text);unwind_protect_cleanup fclose(fid);end_unwind_protect
endfunction
