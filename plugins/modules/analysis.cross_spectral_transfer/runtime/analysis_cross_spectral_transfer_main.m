function analysis_cross_spectral_transfer_main(args)
% Cross-Spectral & Transfer Function Analysis - main scientific stage.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.cross_spectral_transfer';module_version='1.1.3';io_chunk_rows=65536;publication_chunk_rows=65536;
  this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime output/session information is missing',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  P=struct();publication_open=false;publication_finalized=false;tmpdir='';gxtxt_progress_start('prepare','Preparing cross-spectral analysis','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif
    time_binding=binding_name(gxtxt_ini_get(cfg,'bindings.time',''));input_binding=binding_name(gxtxt_ini_get(cfg,'bindings.input_signal',''));output_binding=binding_name(gxtxt_ini_get(cfg,'bindings.output_signal',''));
    if(isempty(time_binding)||isempty(input_binding)||isempty(output_binding)),error('%s: time, input and output bindings are required',module_id);endif
    [time_unit,~,time_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',time_binding);[input_unit,~,input_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',input_binding);[output_unit,~,output_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',output_binding);
    require_meta(time_meta,'time',module_id);require_meta(input_meta,'input',module_id);require_meta(output_meta,'output',module_id);
    time_id=strtrim(time_meta.variable_id);input_id=strtrim(input_meta.variable_id);output_id=strtrim(output_meta.variable_id);
    input_name=strtrim(input_meta.name);output_name=strtrim(output_meta.name);if(isempty(input_name)),input_name=input_id;endif;if(isempty(output_name)),output_name=output_id;endif

    S=gxtxt_table_stream_open_source(cfg,'primary',{time_id,input_id,output_id},1,struct('start',0,'count',0,'require_direct',false));source_provider=S.storage_provider;source_row_count=S.row_count;schema=S.schema;S=gxtxt_table_stream_close(S);
    time_schema=find_schema(schema,time_id);if(isempty(time_schema)),error('%s: bound time variable is absent from canonical schema',module_id);endif

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

    source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));scientific_fp=csx_scientific_fingerprint(source_dataset_id,csx_source_stamp(source_path),time_id,input_id,output_id,T,window_name,detrend_mode,nfft_mode,nfft);
    discover_numeric_service(cfg,module_id);discover_plot_service(package_root,module_id);
    axis_kind=lower(strtrim(time_schema.axis_kind));axis_origin=str2double(strtrim(time_schema.axis_origin));axis_step=str2double(strtrim(time_schema.axis_step));temporal_unit=strtrim(T.temporal_unit);
    if(isfield(time_meta,'value_kind')&&strcmpi(strtrim(time_meta.value_kind),'elapsed_time')),temporal_unit='s';elseif(isempty(temporal_unit)),temporal_unit=strtrim(time_unit);endif
    if(isempty(temporal_unit)),error('%s: temporal variable needs a physical elapsed-time unit',module_id);endif
    if(strcmp(axis_kind,'uniform'))
      if(!isfinite(axis_step)||axis_step<=0),error('%s: invalid uniform time axis',module_id);endif;dt_numeric=axis_step;timing_dev=0;
    else
      gxtxt_progress_stage('sampling_check','Validating explicit temporal sampling','indeterminate');Q=scan_explicit_timing(cfg,time_id,T.effective_row_start,T.effective_row_count,io_chunk_rows);dt_numeric=Q.mean_step;timing_dev=Q.relative_deviation;if(timing_dev>1e-6),error('%s: time variable is not uniformly sampled enough for FFT processing (relative deviation %.6g)',module_id,timing_dev);endif
    endif
    try dt_seconds=gxtxt_unit_convert(dt_numeric,temporal_unit,'s');catch e,error('%s: temporal unit %s cannot be converted to seconds: %s',module_id,temporal_unit,e.message);end_try_catch
    fs=1/dt_seconds;df=fs/nfft;

    members=cell(1,T.member_count);for i=1:T.member_count,members{i}=gxtxt_temporal_set_member(T,i);if(members{i}.row_count<2||members{i}.row_count>nfft),error('%s: invalid window %s row count %d for NFFT=%d',module_id,members{i}.member_id,members{i}.row_count,nfft);endif;endfor
    run_token=sprintf('%d_%d',getpid(),round(1e6*rem(now(),1)));tmpdir=fullfile(outdir,['.csx_' run_token]);mkdir(tmpdir);worker_script=fullfile(fileparts(mfilename('fullpath')),'cross_spectral_worker.m');octave_cmd=strtrim(gxtxt_ini_get(cfg,'runtime.octave_cmd','/usr/bin/octave-cli'));if(isempty(octave_cmd)),octave_cmd='/usr/bin/octave-cli';endif
    items=cell(1,T.member_count);result_paths=cell(1,T.member_count);for i=1:T.member_count,Q=members{i};result_paths{i}=fullfile(tmpdir,sprintf('window_%06d.mat',i));argv={octave_cmd,'--quiet','--no-gui',worker_script,'--runtime',config_path,'--item-id',Q.member_id,'--input-id',input_id,'--output-id',output_id,'--row-start',num2str(Q.row_start),'--row-count',num2str(Q.row_count),'--nfft',num2str(nfft),'--dt-seconds',num2str(dt_seconds,17),'--window',window_name,'--detrend',detrend_mode,'--result',result_paths{i}};items{i}=struct('id',Q.member_id,'argv',{argv});endfor
    pinfo=gxtxt_parallel_execution_info_v1();thread_hint=max(1,round(pinfo.recommended_internal_threads));popts=struct('workers',workers,'fail_fast',true,'run_id',['csx-' run_token],'environment',{{'OMP_NUM_THREADS',num2str(thread_hint);'OPENBLAS_NUM_THREADS',num2str(thread_hint);'MKL_NUM_THREADS',num2str(thread_hint);'NUMEXPR_NUM_THREADS',num2str(thread_hint)}});
    gxtxt_progress_stage('spectral_windows',sprintf('Processing %d paired spectral windows',T.member_count),'determinate',T.member_count);pr=gxtxt_parallel_execute_v1(items,popts);if(!strcmp(pr.state,'completed')),error('%s: one or more cross-spectral workers failed: %s',module_id,parallel_failure_summary(pr));endif
    if(numel(pr.results)!=T.member_count),error('%s: Parallel Execution returned an unexpected result count',module_id);endif
    for i=1:T.member_count,rr=pr.results{i};if(!strcmp(rr.id,members{i}.member_id)||!strcmp(rr.state,'success')),error('%s: deterministic Parallel Execution association failed at window %d',module_id,i);endif;endfor

    Sxx=zeros(Nh,1);Syy=zeros(Nh,1);Sxy=zeros(Nh,1);freq=[];for i=1:T.member_count,L=load(result_paths{i});if(!isfield(L,'R')||!strcmp(L.R.item_id,members{i}.member_id)),error('%s: worker result identity mismatch at window %d',module_id,i);endif;R=L.R;if(numel(R.Pxx)!=Nh||numel(R.Pyy)!=Nh||numel(R.Pxy)!=Nh||numel(R.frequency)!=Nh),error('%s: unexpected worker spectrum size',module_id);endif;if(isempty(freq)),freq=double(R.frequency(:));elseif(max(abs(freq-double(R.frequency(:))))>max(1e-12,abs(df)*1e-12)),error('%s: worker frequency-grid mismatch',module_id);endif;Sxx+=R.Pxx;Syy+=R.Pyy;Sxy+=R.Pxy;gxtxt_progress_update(i,T.member_count,'aggregate',sprintf('Aggregated window %d/%d',i,T.member_count));endfor
    Sxx/=T.member_count;Syy/=T.member_count;Sxy/=T.member_count;den=Sxx.*Syy;coh=zeros(size(den));ok=den>realmin;coh(ok)=min(1,max(0,(abs(Sxy(ok)).^2)./den(ok)));
    H1=NaN(size(Sxy));ok1=Sxx>realmin;H1(ok1)=Sxy(ok1)./Sxx(ok1);H2=NaN(size(Sxy));ok2=abs(Sxy)>realmin;H2(ok2)=Syy(ok2)./conj(Sxy(ok2));
    h1_phase_unwrapped_deg=unwrap(angle(H1))*180/pi;h2_phase_unwrapped_deg=unwrap(angle(H2))*180/pi;input_psd_db=10*log10(max(Sxx,realmin));output_psd_db=10*log10(max(Syy,realmin));

    transfer_unit=ratio_unit(output_unit,input_unit);input_psd_unit=psd_unit(input_unit);output_psd_unit=psd_unit(output_unit);cross_unit=cross_psd_unit(input_unit,output_unit);
    pub_id=[safe_id(source_dataset_id) '.cross_spectral.' safe_id(input_id) '.' safe_id(output_id) '.' safe_id(T.id)];provenance=sprintf('source_dataset=%s;time=%s;input=%s;output=%s;temporal_set=%s;window=%s;detrend=%s;nfft=%d;cross_convention=conj(X)*Y;module=%s@%s',source_dataset_id,time_id,input_id,output_id,T.id,window_name,detrend_mode,nfft,module_id,module_version);
    options=struct('storage','auto','capabilities_required',{{'typed_numeric','implicit_axis','range_write'}},'capabilities_preferred',{{'sequential_chunks'}},'replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{time_id,input_id,output_id}},'source',source_dataset_id,'provenance',provenance,'notes','Cross-spectral averages over Temporal Window Set members. Sxy=conj(X)*Y.');
    gxtxt_progress_stage('publish','Publishing cross-spectral Dataset','determinate',Nh);P=gxtxt_publication_v2_open(session,module_id,pub_id,'spectrum.table',options);publication_open=true;P=gxtxt_publication_v2_declare_dimension(P,'frequency_bin',Nh,false);P=gxtxt_publication_v2_declare_uniform(P,'frequency','frequency_bin',0,df,struct('name','frequency','unit','Hz','dtype','float64','semantic_role','independent'));
    vars={ ...
      'input_psd',Sxx,input_psd_unit;'output_psd',Syy,output_psd_unit;'cross_psd_real',real(Sxy),cross_unit;'cross_psd_imag',imag(Sxy),cross_unit;'cross_psd_magnitude',abs(Sxy),cross_unit;'cross_phase_deg',angle(Sxy)*180/pi,'deg'; ...
      'h1_real',real(H1),transfer_unit;'h1_imag',imag(H1),transfer_unit;'h1_magnitude',abs(H1),transfer_unit;'h1_gain_db',20*log10(max(abs(H1),realmin)),'dB';'h1_phase_deg',angle(H1)*180/pi,'deg'; ...
      'h2_real',real(H2),transfer_unit;'h2_imag',imag(H2),transfer_unit;'h2_magnitude',abs(H2),transfer_unit;'h2_gain_db',20*log10(max(abs(H2),realmin)),'dB';'h2_phase_deg',angle(H2)*180/pi,'deg';'h1_phase_unwrapped_deg',h1_phase_unwrapped_deg,'deg';'h2_phase_unwrapped_deg',h2_phase_unwrapped_deg,'deg';'input_psd_db',input_psd_db,'dB';'output_psd_db',output_psd_db,'dB';'coherence',coh,'1'};
    chunks=min(publication_chunk_rows,Nh);for vi=1:size(vars,1),P=gxtxt_publication_v2_declare_variable(P,vars{vi,1},struct('dtype','float64','dimension_ids','frequency_bin','name',vars{vi,1},'unit',vars{vi,3},'semantic_role','measured','coordinate_variable_ids','frequency','chunks',chunks));endfor
    for start0=0:publication_chunk_rows:(Nh-1),count=min(publication_chunk_rows,Nh-start0);rr=(start0+1):(start0+count);for vi=1:size(vars,1),P=gxtxt_publication_v2_write_range(P,vars{vi,1},start0,vars{vi,2}(rr));endfor;gxtxt_progress_update(start0+count,Nh,'publish',sprintf('Published %d/%d frequency bins',start0+count,Nh));endfor
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);output_provider=P.provider;[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    write_report(fullfile(outdir,'cross_spectral_report.txt'),module_version,source_dataset_id,time_id,input_id,output_id,input_name,output_name,T,window_name,detrend_mode,nfft,fs,df,source_provider,output_provider,pub_id,timing_dev,workers,pr,transfer_unit,input_psd_unit,output_psd_unit);
    gxtxt_progress_stage('plot','Creating persistent plot.dataset graphs','indeterminate');graphs=create_standard_graphs(session,pub_id,input_name,output_name,input_unit,output_unit,transfer_unit,module_id);write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);copy_graph_artifacts(graphs,outdir,module_id);if(exist(tmpdir,'dir')==7),rmdir(tmpdir,'s');endif;tmpdir='';gxtxt_progress_complete('done',sprintf('Published %s from %d averaged windows',pub_id,T.member_count));
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif;if(!isempty(tmpdir)&&exist(tmpdir,'dir')==7),try rmdir(tmpdir,'s');catch;end_try_catch;endif;try gxtxt_progress_fail('failed',err.message);catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function S=scan_explicit_timing(cfg,time_id,row_start,row_count,chunk_rows)
  st=gxtxt_table_stream_open_source(cfg,'primary',{time_id},chunk_rows,struct('start',row_start,'count',row_count,'require_direct',false,'numeric_transport','auto'));prev=NaN;sumd=0;nd=0;mind=Inf;maxd=-Inf;
  unwind_protect
    while(true),[st,ch]=gxtxt_table_stream_v3_next(st);if(ch.nrows>0),t=gxtxt_table_chunk_numeric(ch,time_id);t=t(:);if(any(!isfinite(t))),error('analysis.cross_spectral_transfer: explicit time contains non-finite values');endif;if(isfinite(prev)),d0=t(1)-prev;if(d0<=0),error('analysis.cross_spectral_transfer: time must be strictly increasing');endif;sumd+=d0;nd+=1;mind=min(mind,d0);maxd=max(maxd,d0);endif;d=diff(t);if(any(d<=0)),error('analysis.cross_spectral_transfer: time must be strictly increasing');endif;if(!isempty(d)),sumd+=sum(d);nd+=numel(d);mind=min(mind,min(d));maxd=max(maxd,max(d));endif;prev=t(end);endif;if(ch.eof),break;endif;endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(nd<1),error('analysis.cross_spectral_transfer: at least two time samples are required');endif;mean_step=sumd/nd;S=struct('mean_step',mean_step,'relative_deviation',max(abs([mind-mean_step,maxd-mean_step]))/max(abs(mean_step),realmin));
endfunction
function s=binding_name(s),s=strtrim(s);p=strfind(s,'.');if(!isempty(p)),s=s(p(end)+1:end);endif;endfunction
function require_meta(m,label,module_id),if(!isfield(m,'found')||!m.found||!isfield(m,'variable_id')||isempty(strtrim(m.variable_id))),error('%s: %s binding could not be resolved to a stable variable ID',module_id,label);endif;endfunction
function s=find_schema(schema,id),s=[];for i=1:numel(schema),if(strcmp(strtrim(schema(i).variable_id),id)),s=schema(i);return;endif;endfor;endfunction
function v=parse_positive_integer(raw),v=str2double(strtrim(raw));if(!isfinite(v)||v<1||v!=fix(v)),v=NaN;endif;endfunction
function w=normalize_workers(raw),w=lower(strtrim(raw));if(any(strcmp(w,{'auto','serial'}))),return;endif;n=str2double(w);if(!isfinite(n)||n<1||n!=fix(n)),error('analysis.cross_spectral_transfer: workers must be auto, serial, or a positive integer');endif;w=sprintf('%d',n);endfunction
function s=parallel_failure_summary(pr),parts={};for i=1:numel(pr.results),r=pr.results{i};if(!strcmp(r.state,'success')),parts{end+1}=sprintf('%s:%s:%s',r.id,r.state,r.stderr);endif;endfor;if(isempty(parts)),s=pr.state;else s=strjoin(parts,' | ');endif;endfunction
function s=safe_id(s),s=regexprep(strtrim(s),'[^A-Za-z0-9_.-]','_');if(isempty(s)),s='signal';endif;endfunction
function u=psd_unit(s),s=strtrim(s);if(isempty(s)),s='1';endif;u=[s '^2/Hz'];endfunction
function u=cross_psd_unit(a,b),a=strtrim(a);b=strtrim(b);if(isempty(a)),a='1';endif;if(isempty(b)),b='1';endif;u=[a '*' b '/Hz'];endfunction
function u=ratio_unit(out,in),out=strtrim(out);in=strtrim(in);if(isempty(out)),out='1';endif;if(isempty(in)),in='1';endif;if(strcmp(out,in)),u='1';else u=[out '/' in];endif;endfunction
function copy_if_exists(src,dst,name),p=fullfile(src,name);if(exist(p,'file')==2),copyfile(p,fullfile(dst,name));endif;endfunction
function write_report(path,version,ds,time_id,input_id,output_id,input_name,output_name,T,window,detrend,nfft,fs,df,source_provider,output_provider,pub_id,timing_dev,workers,pr,transfer_unit,input_psd_unit,output_psd_unit)
  fid=fopen(path,'w');if(fid<0),error('analysis.cross_spectral_transfer: cannot write report');endif;unwind_protect
    fprintf(fid,'Cross-Spectral & Transfer Function Analysis\n===========================================\n');fprintf(fid,'Module version: %s\nSource Dataset: %s\nTime variable: %s\nInput X: %s (%s)\nOutput Y: %s (%s)\n',version,ds,time_id,input_name,input_id,output_name,output_id);fprintf(fid,'Temporal Set: %s (%d windows)\nFFT window: %s\nDetrend: %s\nNFFT: %d\nSample rate: %.17g Hz\nFrequency step: %.17g Hz\n',T.id,T.member_count,window,detrend,nfft,fs,df);fprintf(fid,'Cross-spectrum convention: Sxy = mean(conj(X) * Y)\nH1 = Sxy / Sxx\nH2 = Syy / conj(Sxy)\nCoherence = |Sxy|^2 / (Sxx*Syy)\n');fprintf(fid,'Transfer unit: %s\nInput PSD unit: %s\nOutput PSD unit: %s\nSource provider: %s\nOutput provider: %s\nPublished Dataset: %s\nExplicit-time relative interval deviation: %.6g\nWorkers requested: %s\nParallel state: %s\n',transfer_unit,input_psd_unit,output_psd_unit,source_provider,output_provider,pub_id,timing_dev,workers,pr.state);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function discover_numeric_service(cfg,module_id)
  sec='public_api.NUMERIC_API_v1';if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],'')),'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif;if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.api_version'],'')),'1')),error('%s: unsupported runtime NUMERIC_API_v1 version',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));for q={'fft','frequency_grid','one_sided_transform','detrending','window_generation'},if(!any(strcmp(caps,q{1}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,q{1});endif;endfor
  entry=strtrim(gxtxt_ini_get(cfg,[sec '.octave_entrypoint'],''));fn=strtrim(gxtxt_ini_get(cfg,[sec '.octave_function'],''));if(isempty(entry)||isempty(fn)||exist(entry,'file')!=2),error('%s: runtime NUMERIC_API_v1 Octave binding unavailable',module_id);endif
endfunction
function discover_plot_service(root,module_id)
  pd=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(pd,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif;d=gxtxt_ini_read(pd);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif;bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable',module_id);endif;addpath(fileparts(bridge));
endfunction
function G=create_standard_graphs(session,dataset_id,input_name,output_name,input_unit,output_unit,transfer_unit,module_id)
  G={};
  G{end+1}=create_plot(session,dataset_id,'transfer_gain','Transfer magnitude','h1_gain_db','H1 gain','dB',{},module_id);
  G{end+1}=create_plot(session,dataset_id,'transfer_phase','Transfer phase','h1_phase_deg','H1 phase','deg',{},module_id);
  G{end+1}=create_plot(session,dataset_id,'coherence','Magnitude-squared coherence','coherence','Coherence','1',{},module_id);
  if(strcmp(strtrim(input_unit),strtrim(output_unit)))
    extra={{'input_psd_db',input_name},{'output_psd_db',output_name}};G{end+1}=create_plot(session,dataset_id,'input_output_psd','Input / output power spectral density','','','dB',extra,module_id);
  endif
endfunction
function R=create_plot(session,dataset_id,key,title_text,yvar,ylabel,yunit,extra,module_id)
  axes=struct('x',struct('label','Frequency [Hz]','display_unit','Hz','scale','linear'),'y_left',struct('label',axis_label(ylabel,yunit),'scale','linear'));
  series={};if(!isempty(yvar)),series{end+1}=struct('id',key,'dataset_id',dataset_id,'x_variable_id','frequency','y_variable_id',yvar,'axis','left','kind','line','label',ylabel);endif
  for i=1:numel(extra),q=extra{i};series{end+1}=struct('id',q{1},'dataset_id',dataset_id,'x_variable_id','frequency','y_variable_id',q{1},'axis','left','kind','line','label',q{2});endfor
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series});spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));R.key=key;
endfunction
function copy_graph_artifacts(G,outdir,module_id)
  for i=1:numel(G),src=strtrim(G{i}.artifact);if(isempty(src)||exist(src,'file')!=2),error('%s: plot.dataset graph artifact missing for %s',module_id,G{i}.key);endif;dst=fullfile(outdir,sprintf('%02d_%s.png',i,G{i}.key));[ok,msg]=copyfile(src,dst,'f');if(!ok),error('%s: cannot copy plot.dataset artifact: %s',module_id,msg);endif;endfor
endfunction
function write_graph_manifest(path,G)
  fid=fopen(path,'w');if(fid<0),error('analysis.cross_spectral_transfer: cannot write automatic graph manifest');endif;unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(G));for i=1:numel(G),fprintf(fid,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%02d_%s.png\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',i,G{i}.key,ini_escape(G{i}.graph_id),ini_escape(G{i}.variant_id),i,G{i}.key,ini_escape(G{i}.artifact));endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function s=axis_label(name,unit),if(isempty(strtrim(unit))||strcmp(unit,'1')),s=name;else s=sprintf('%s [%s]',name,unit);endif;endfunction
function s=ini_escape(s),s=strrep(strrep(char(s),sprintf('\r'),' '),sprintf('\n'),' ');endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
