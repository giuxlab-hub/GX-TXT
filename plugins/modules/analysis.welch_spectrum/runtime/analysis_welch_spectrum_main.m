function analysis_welch_spectrum_main(args)
% Welch PSD & Averaged Spectrum - main scientific stage.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.welch_spectrum';module_version='1.2.0';io_chunk_rows=65536;publication_chunk_rows=65536;batch_size=8;
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime output/session information is missing',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  P=struct();publication_open=false;publication_finalized=false;tmpdir='';gxtxt_progress_start('prepare','Preparing Welch averaged spectrum','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif
    time_binding=binding_name(gxtxt_ini_get(cfg,'bindings.time',''));signal_binding=binding_name(gxtxt_ini_get(cfg,'bindings.signal',''));
    if(isempty(time_binding)||isempty(signal_binding)),error('%s: time and signal bindings are required',module_id);endif
    [time_unit,~,time_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',time_binding);[signal_unit,~,signal_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',signal_binding);
    require_meta(time_meta,'time',module_id);require_meta(signal_meta,'signal',module_id);time_id=strtrim(time_meta.variable_id);signal_id=strtrim(signal_meta.variable_id);signal_name=strtrim(signal_meta.name);if(isempty(signal_name)),signal_name=signal_id;endif

    S=gxtxt_table_stream_open_source(cfg,'primary',{time_id,signal_id},1,struct('start',0,'count',0,'require_direct',false));source_provider=S.storage_provider;schema=S.schema;S=gxtxt_table_stream_close(S);time_schema=find_schema(schema,time_id);if(isempty(time_schema)),error('%s: bound time variable is absent from canonical schema',module_id);endif
    T=gxtxt_temporal_set_from_runtime(cfg,'temporal_set');if(!T.enabled||!strcmp(T.type,'window_set')),error('%s: an existing Temporal Window Set is required',module_id);endif
    if(!strcmp(T.source_dataset_id,source_dataset_id)||!strcmp(T.temporal_variable_id,time_id)),error('%s: Temporal Set does not match the selected Dataset/time variable',module_id);endif
    if(T.member_count<1),error('%s: Temporal Window Set resolves to no windows',module_id);endif

    window_name=lower(strtrim(gxtxt_ini_get(cfg,'config.window','hann')));allowed={'rectangular','hann','hamming','blackman','blackman_harris','flat_top'};if(!any(strcmp(window_name,allowed))),error('%s: unsupported FFT window: %s',module_id,window_name);endif
    detrend_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.detrend','mean')));if(!any(strcmp(detrend_mode,{'none','mean','linear'}))),error('%s: unsupported detrend mode: %s',module_id,detrend_mode);endif
    nfft_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.nfft_mode','auto')));if(!any(strcmp(nfft_mode,{'auto','explicit'}))),error('%s: unsupported NFFT mode',module_id);endif
    workers=normalize_workers(gxtxt_ini_get(cfg,'config.workers','auto'));run_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.run_mode','auto')));if(!any(strcmp(run_mode,{'auto','recalculate','render_only'}))),error('%s: invalid run mode',module_id);endif
    nominal_rows=T.resolved_window_rows;if(nominal_rows<2),error('%s: Temporal Set window must contain at least 2 samples',module_id);endif
    if(strcmp(nfft_mode,'auto')),nfft=nominal_rows;else nfft=parse_positive_integer(gxtxt_ini_get(cfg,'config.nfft',''));if(!isfinite(nfft)||nfft<nominal_rows),error('%s: explicit NFFT must be >= %d',module_id,nominal_rows);endif;endif
    Nh=floor(nfft/2)+1;

    source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));scientific_fp=welch_scientific_fingerprint(source_dataset_id,welch_source_stamp(source_path),time_id,signal_id,T,window_name,detrend_mode,nfft_mode,nfft);
    cache_params=struct('scientific_fingerprint',scientific_fp);expected_meta=gxtxt_render_cache_standard_meta(module_id,module_version,'',struct(),cache_params);expected_cache=struct('module_id',module_id,'module_version',module_version,'source_fingerprint',expected_meta.source_fingerprint,'parameter_fingerprint',expected_meta.parameter_fingerprint);

    variant_graph=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));variant_id=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));
    if(!isempty(variant_graph)&&!isempty(variant_id))
      base_outdir=fullfile(session,'analysis',module_id);base_cache_path=gxtxt_render_cache_path(base_outdir);if(exist(base_cache_path,'file')!=2),error('%s: plot variant requires a current base analysis cache',module_id);endif
      base_cache=gxtxt_render_cache_load(base_cache_path);rep=gxtxt_render_cache_validate(base_cache,expected_cache);if(!rep.valid||!isfield(base_cache,'module')||!strcmp(base_cache.module.scientific_fingerprint,scientific_fp)),error('%s: plot variant cannot reuse stale scientific cache',module_id);endif
      gxtxt_render_cache_save(outdir,base_cache);copy_if_exists(base_outdir,outdir,'welch_spectrum_report.txt');analysis_welch_spectrum_render(outdir,cfg,base_cache.module);gxtxt_progress_complete('done','Rendered Welch plot variant without spectral recomputation');return;
    endif

    cache_path=gxtxt_render_cache_path(outdir);cache_ok=false;cached=struct();if(exist(cache_path,'file')==2),try cached=gxtxt_render_cache_load(cache_path);rep=gxtxt_render_cache_validate(cached,expected_cache);cache_ok=rep.valid&&isfield(cached,'module')&&strcmp(cached.module.scientific_fingerprint,scientific_fp)&&exist(fullfile(outdir,'welch_spectrum_report.txt'),'file')==2;catch;cache_ok=false;end_try_catch;endif
    if(!strcmp(run_mode,'recalculate')&&cache_ok),gxtxt_progress_stage('render','Reusing compatible Welch result','indeterminate');analysis_welch_spectrum_render(outdir,cfg,cached.module);gxtxt_progress_complete('done','Rendered from existing Welch cache');return;endif
    if(strcmp(run_mode,'render_only')),error('%s: Render only requested but no compatible scientific cache is available',module_id);endif

    axis_kind=lower(strtrim(time_schema.axis_kind));axis_step=str2double(strtrim(time_schema.axis_step));temporal_unit=strtrim(T.temporal_unit);
    if(isfield(time_meta,'value_kind')&&strcmpi(strtrim(time_meta.value_kind),'elapsed_time')),temporal_unit='s';elseif(isempty(temporal_unit)),temporal_unit=strtrim(time_unit);endif
    if(isempty(temporal_unit)),error('%s: temporal variable needs a physical elapsed-time unit',module_id);endif
    if(strcmp(axis_kind,'uniform'))
      if(!isfinite(axis_step)||axis_step<=0),error('%s: invalid uniform time axis',module_id);endif;dt_numeric=axis_step;timing_dev=0;
    else
      gxtxt_progress_stage('sampling_check','Validating explicit temporal sampling','indeterminate');Q=scan_explicit_timing(cfg,time_id,T.effective_row_start,T.effective_row_count,io_chunk_rows);dt_numeric=Q.mean_step;timing_dev=Q.relative_deviation;if(timing_dev>1e-6),error('%s: time variable is not uniformly sampled enough for FFT processing (relative deviation %.6g)',module_id,timing_dev);endif
    endif
    try dt_seconds=gxtxt_unit_convert(dt_numeric,temporal_unit,'s');catch e,error('%s: temporal unit %s cannot be converted to seconds: %s',module_id,temporal_unit,e.message);end_try_catch
    fs=1/dt_seconds;df=fs/nfft;freq=(0:Nh-1)'*df;

    members=cell(1,T.member_count);for i=1:T.member_count,members{i}=gxtxt_temporal_set_member(T,i);if(members{i}.row_count<2||members{i}.row_count>nfft),error('%s: invalid window %s row count %d for NFFT=%d',module_id,members{i}.member_id,members{i}.row_count,nfft);endif;endfor
    run_token=sprintf('%d_%d',getpid(),round(1e6*rem(now(),1)));tmpdir=fullfile(outdir,['.welch_' run_token]);mkdir(tmpdir);worker_script=fullfile(fileparts(mfilename('fullpath')),'welch_spectrum_worker.m');octave_cmd=strtrim(gxtxt_ini_get(cfg,'runtime.octave_cmd','/usr/bin/octave-cli'));if(isempty(octave_cmd)),octave_cmd='/usr/bin/octave-cli';endif
    batch_count=ceil(T.member_count/batch_size);items=cell(1,batch_count);result_paths=cell(1,batch_count);batch_ids=cell(1,batch_count);
    for bi=1:batch_count
      first=(bi-1)*batch_size+1;last=min(T.member_count,bi*batch_size);batch_ids{bi}=sprintf('batch_%06d',bi);manifest=fullfile(tmpdir,[batch_ids{bi} '.tsv']);fid=fopen(manifest,'w');if(fid<0),error('%s: cannot create batch manifest',module_id);endif;unwind_protect
        for wi=first:last,Q=members{wi};fprintf(fid,'%s\t%d\t%d\n',Q.member_id,Q.row_start,Q.row_count);endfor
      unwind_protect_cleanup
        fclose(fid);
      end_unwind_protect
      result_paths{bi}=fullfile(tmpdir,[batch_ids{bi} '.mat']);argv={octave_cmd,'--quiet','--no-gui',worker_script,'--runtime',config_path,'--batch-id',batch_ids{bi},'--signal-id',signal_id,'--manifest',manifest,'--nfft',num2str(nfft),'--dt-seconds',num2str(dt_seconds,17),'--window',window_name,'--detrend',detrend_mode,'--result',result_paths{bi}};items{bi}=struct('id',batch_ids{bi},'argv',{argv});
    endfor
    pinfo=gxtxt_parallel_execution_info_v1();thread_hint=max(1,round(pinfo.recommended_internal_threads));popts=struct('workers',workers,'fail_fast',true,'run_id',['welch-' run_token],'environment',{{'OMP_NUM_THREADS',num2str(thread_hint);'OPENBLAS_NUM_THREADS',num2str(thread_hint);'MKL_NUM_THREADS',num2str(thread_hint);'NUMEXPR_NUM_THREADS',num2str(thread_hint)}});
    gxtxt_progress_stage('periodograms',sprintf('Processing %d windows in %d deterministic batches',T.member_count,batch_count),'determinate',batch_count);pr=gxtxt_parallel_execute_v1(items,popts);if(!strcmp(pr.state,'completed')),error('%s: one or more Welch workers failed: %s',module_id,parallel_failure_summary(pr));endif
    if(numel(pr.results)!=batch_count),error('%s: Parallel Execution returned an unexpected result count',module_id);endif
    sum_psd=zeros(Nh,1);sum_amp=zeros(Nh,1);window_count=0;sample_total=0;enbw_sum=0;
    for bi=1:batch_count
      rr=pr.results{bi};if(!strcmp(rr.id,batch_ids{bi})||!strcmp(rr.state,'success')),error('%s: deterministic Parallel Execution association failed at batch %d',module_id,bi);endif
      L=load(result_paths{bi});if(!isfield(L,'B')||!strcmp(L.B.batch_id,batch_ids{bi})),error('%s: worker batch identity mismatch',module_id);endif;B=L.B;if(numel(B.sum_psd)!=Nh||numel(B.sum_amplitude)!=Nh),error('%s: unexpected worker spectrum size',module_id);endif
      sum_psd+=B.sum_psd;sum_amp+=B.sum_amplitude;window_count+=B.window_count;sample_total+=B.sample_total;enbw_sum+=B.enbw_sum_hz;gxtxt_progress_update(bi,batch_count,'aggregate',sprintf('Aggregated batch %d/%d',bi,batch_count));
    endfor
    if(window_count!=T.member_count),error('%s: aggregated window count mismatch',module_id);endif
    numeric_fn=welch_numeric_api(cfg);
    R=feval(numeric_fn,'welch_aggregate',sum_psd,sum_amp,struct('window_count',window_count,'frequency_step_hz',df,'enbw_sum_hz',enbw_sum));
    evidence=struct('producer_module',module_id,'producer_version',module_version,'source_dataset_id',source_dataset_id,'time_variable_id',time_id,'signal_variable_id',signal_id,'temporal_set_id',T.id,'window_name',window_name,'detrend_mode',detrend_mode,'nfft',nfft,'window_rows',T.resolved_window_rows,'step_rows',T.resolved_step_rows,'partial_policy',T.partial_policy);
    statistics=gxtxt_statistics_v1('from_numeric','math.numeric.welch_spectrum','welch_aggregate',R,struct('y_unit',signal_unit),struct(),evidence);
    fields=gxtxt_statistics_v1('numeric_fields',statistics);
    psd=R.psd;mean_amplitude=R.mean_amplitude;asd=R.asd;psd_db=R.psd_db;mean_enbw_hz=fields.mean_enbw_hz.value;

    psd_unit=statistics.context.psd_unit;asd_unit=statistics.context.asd_unit;pub_id=[safe_id(source_dataset_id) '.welch.' safe_id(signal_id) '.' safe_id(T.id)];provenance=sprintf('source_dataset=%s;time=%s;signal=%s;temporal_set=%s;window=%s;detrend=%s;nfft=%d;averaging=arithmetic_periodogram_mean;module=%s@%s',source_dataset_id,time_id,signal_id,T.id,window_name,detrend_mode,nfft,module_id,module_version);
    options=struct('storage','auto','capabilities_required',{{'typed_numeric','implicit_axis','range_write'}},'capabilities_preferred',{{'sequential_chunks'}},'replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{time_id,signal_id}},'source',source_dataset_id,'provenance',provenance,'notes','Welch-style arithmetic average of one-sided normalized periodograms over Temporal Window Set members.');
    options.statistical_results=struct('spectrum',statistics);
    gxtxt_progress_stage('publish','Publishing Welch spectrum Dataset','determinate',Nh);P=gxtxt_publication_v2_open(session,module_id,pub_id,'spectrum.table',options);publication_open=true;P=gxtxt_publication_v2_declare_dimension(P,'frequency_bin',Nh,false);P=gxtxt_publication_v2_declare_uniform(P,'frequency','frequency_bin',0,df,struct('name','frequency','unit','Hz','dtype','float64','semantic_role','independent'));
    vars={'psd',psd,psd_unit;'asd',asd,asd_unit;'mean_amplitude',mean_amplitude,signal_unit;'psd_db',psd_db,'dB'};chunks=min(publication_chunk_rows,Nh);for vi=1:size(vars,1),P=gxtxt_publication_v2_declare_variable(P,vars{vi,1},struct('dtype','float64','dimension_ids','frequency_bin','name',vars{vi,1},'unit',vars{vi,3},'semantic_role','measured','coordinate_variable_ids','frequency','chunks',chunks));endfor
    for start0=0:publication_chunk_rows:(Nh-1),count=min(publication_chunk_rows,Nh-start0);rr=(start0+1):(start0+count);for vi=1:size(vars,1),P=gxtxt_publication_v2_write_range(P,vars{vi,1},start0,vars{vi,2}(rr));endfor;gxtxt_progress_update(start0+count,Nh,'publish',sprintf('Published %d/%d frequency bins',start0+count,Nh));endfor
    output_provider=P.provider;[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    overlap_fraction=1-(T.resolved_step_rows/T.resolved_window_rows);write_report(fullfile(outdir,'welch_spectrum_report.txt'),module_version,source_dataset_id,time_id,signal_id,signal_name,signal_unit,T,window_name,detrend_mode,nfft,fs,df,source_provider,output_provider,pub_id,timing_dev,workers,pr,batch_count,batch_size,statistics,overlap_fraction);
    meta=gxtxt_render_cache_standard_meta(module_id,module_version,'',struct(),cache_params);D=struct('scientific_fingerprint',scientific_fp,'dataset_id',pub_id,'source_dataset_id',source_dataset_id,'time_variable_id',time_id,'signal_variable_id',signal_id,'signal_name',signal_name,'signal_unit',signal_unit,'psd_unit',psd_unit,'asd_unit',asd_unit,'window_count',window_count,'nfft',nfft,'fs',fs,'df',df,'frequency',freq,'psd',psd,'asd',asd,'mean_amplitude',mean_amplitude,'psd_db',psd_db,'window_name',window_name,'detrend_mode',detrend_mode,'temporal_set_id',T.id,'enbw_hz',mean_enbw_hz,'statistical_result',statistics);cache=struct('meta',meta,'module',D);gxtxt_render_cache_save(outdir,cache);
    analysis_welch_spectrum_render(outdir,cfg,D);if(exist(tmpdir,'dir')==7),rmdir(tmpdir,'s');endif;tmpdir='';gxtxt_progress_complete('done',sprintf('Published %s from %d averaged windows',pub_id,window_count));
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif;if(!isempty(tmpdir)&&exist(tmpdir,'dir')==7),try rmdir(tmpdir,'s');catch;end_try_catch;endif;try gxtxt_progress_fail('failed',err.message);catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function S=scan_explicit_timing(cfg,time_id,row_start,row_count,chunk_rows)
  st=gxtxt_table_stream_open_source(cfg,'primary',{time_id},chunk_rows,struct('start',row_start,'count',row_count,'require_direct',false,'numeric_transport','auto'));prev=NaN;sumd=0;nd=0;mind=Inf;maxd=-Inf;
  unwind_protect
    while(true),[st,ch]=gxtxt_table_stream_v3_next(st);if(ch.nrows>0),t=gxtxt_table_chunk_numeric(ch,time_id);t=t(:);if(any(!isfinite(t))),error('analysis.welch_spectrum: explicit time contains non-finite values');endif;if(isfinite(prev)),d0=t(1)-prev;if(d0<=0),error('analysis.welch_spectrum: time must be strictly increasing');endif;sumd+=d0;nd+=1;mind=min(mind,d0);maxd=max(maxd,d0);endif;d=diff(t);if(any(d<=0)),error('analysis.welch_spectrum: time must be strictly increasing');endif;if(!isempty(d)),sumd+=sum(d);nd+=numel(d);mind=min(mind,min(d));maxd=max(maxd,max(d));endif;prev=t(end);endif;if(ch.eof),break;endif;endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(nd<1),error('analysis.welch_spectrum: at least two time samples are required');endif;mean_step=sumd/nd;S=struct('mean_step',mean_step,'relative_deviation',max(abs([mind-mean_step,maxd-mean_step]))/max(abs(mean_step),realmin));
endfunction
function s=binding_name(s),s=strtrim(s);p=strfind(s,'.');if(!isempty(p)),s=s(p(end)+1:end);endif;endfunction
function require_meta(m,label,module_id),if(!isfield(m,'found')||!m.found||!isfield(m,'variable_id')||isempty(strtrim(m.variable_id))),error('%s: %s binding could not be resolved to a stable variable ID',module_id,label);endif;endfunction
function s=find_schema(schema,id),s=[];for i=1:numel(schema),if(strcmp(strtrim(schema(i).variable_id),id)),s=schema(i);return;endif;endfor;endfunction
function v=parse_positive_integer(raw),v=str2double(strtrim(raw));if(!isfinite(v)||v<1||v!=fix(v)),v=NaN;endif;endfunction
function w=normalize_workers(raw),w=lower(strtrim(raw));if(any(strcmp(w,{'auto','serial'}))),return;endif;n=str2double(w);if(!isfinite(n)||n<1||n!=fix(n)),error('analysis.welch_spectrum: workers must be auto, serial, or a positive integer');endif;w=sprintf('%d',n);endfunction
function s=parallel_failure_summary(pr),parts={};for i=1:numel(pr.results),r=pr.results{i};if(!strcmp(r.state,'success')),parts{end+1}=sprintf('%s:%s:%s',r.id,r.state,r.stderr);endif;endfor;if(isempty(parts)),s=pr.state;else s=strjoin(parts,' | ');endif;endfunction
function s=safe_id(s),s=regexprep(strtrim(s),'[^A-Za-z0-9_.-]','_');if(isempty(s)),s='signal';endif;endfunction
function copy_if_exists(src,dst,name),p=fullfile(src,name);if(exist(p,'file')==2),copyfile(p,fullfile(dst,name));endif;endfunction
function write_report(path,version,ds,time_id,signal_id,signal_name,signal_unit,T,window,detrend,nfft,fs,df,source_provider,output_provider,pub_id,timing_dev,workers,pr,batch_count,batch_size,statistics,overlap)
  fid=fopen(path,'w');if(fid<0),error('analysis.welch_spectrum: cannot write report');endif;unwind_protect
    fprintf(fid,'Welch PSD & Averaged Spectrum\n==============================\n');fprintf(fid,'Module version: %s\nSource Dataset: %s\nTime variable: %s\nSignal: %s (%s)\nSignal unit: %s\n',version,ds,time_id,signal_name,signal_id,signal_unit);fprintf(fid,'Temporal Set: %s\nResolved windows: %d\nResolved window rows: %d\nResolved step rows: %d\nOverlap fraction: %.8g\nPartial policy: %s\n',T.id,T.member_count,T.resolved_window_rows,T.resolved_step_rows,overlap,T.partial_policy);fprintf(fid,'FFT window: %s\nDetrend: %s\nNFFT: %d\nSample rate: %.17g Hz\nFrequency step: %.17g Hz\n',window,detrend,nfft,fs,df);fprintf(fid,'%s\n',gxtxt_statistics_v1('report',statistics,{'welch_window_count','welch_mean_enbw','welch_peak_frequency','welch_peak_psd','welch_integrated_power','welch_zero_level_bins'}));fprintf(fid,'Averaging: arithmetic mean of normalized one-sided periodograms\nPSD normalization: |FFT(x*w)|^2 / (Fs*sum(w^2)), interior one-sided bins doubled\nAmplitude normalization: |FFT(x*w)| / sum(w), interior one-sided bins doubled\n');fprintf(fid,'Source provider: %s\nOutput provider: %s\nPublished Dataset: %s\nExplicit-time relative interval deviation: %.6g\nWorkers requested: %s\nParallel state: %s\nParallel batches: %d\nWindows per batch (maximum): %d\n',source_provider,output_provider,pub_id,timing_dev,workers,pr.state,batch_count,batch_size);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
