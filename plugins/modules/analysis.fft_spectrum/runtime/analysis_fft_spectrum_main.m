function analysis_fft_spectrum_main(args)
% FFT Spectrum & Error Analysis - dataset-native numerical/publication stage.
% Consumes one canonical uniformly sampled signal through Table Stream API v3,
% computes the established single-sided FFT/error metrics, and publishes a
% canonical spectrum.table through Dataset Publication API v2 / Storage Auto.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id='analysis.fft_spectrum';
  module_version='2.3.0';
  io_chunk_rows=65536;
  publication_chunk_rows=65536;

  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('%s: --config is required',module_id); endif
  cfg=gxtxt_ini_read(config_path);
  numeric_fn=fft_numeric_binding(cfg);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)), error('%s: runtime.output_dir missing',module_id); endif
  if(isempty(session)), error('%s: runtime.session missing',module_id); endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif
  statistical_scope=gxtxt_statistics_scope_v1(session);

  P=struct(); publication_open=false; publication_finalized=false;
  gxtxt_progress_start('prepare','Preparing dataset-native FFT spectrum analysis','indeterminate');

  try
    % ---- resolve canonical source + stable bindings ----------------------
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)), source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id','')); endif
    if(isempty(source_dataset_id)), error('%s: primary source Dataset ID is missing',module_id); endif

    ind_binding=binding_column(gxtxt_ini_get(cfg,'bindings.independent',''),'independent');
    sig_binding=binding_column(gxtxt_ini_get(cfg,'bindings.signal',''),'signal');
    if(isempty(ind_binding)||isempty(sig_binding))
      error('%s: independent and signal bindings are required',module_id);
    endif

    [ind_unit,~,ind_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',ind_binding);
    [sig_unit,~,sig_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',sig_binding);
    if(!isfield(ind_meta,'found') || !ind_meta.found)
      error('%s: independent binding could not be resolved: %s',module_id,ind_binding);
    endif
    if(!isfield(sig_meta,'found') || !sig_meta.found)
      error('%s: signal binding could not be resolved: %s',module_id,sig_binding);
    endif
    ind_id=strtrim(ind_meta.variable_id); sig_id=strtrim(sig_meta.variable_id);
    ind_name=strtrim(ind_meta.name); sig_name=strtrim(sig_meta.name);
    if(isempty(ind_id)||isempty(sig_id))
      error('%s: current framework runtime must expose stable variable IDs for the selected bindings',module_id);
    endif
    if(isempty(sig_unit)), sig_unit=''; endif

    % Metadata is obtained through the backend-neutral Table Stream facade.
    M=gxtxt_table_stream_open_source(cfg,'primary',{ind_id,sig_id},1, ...
      struct('start',0,'count',0,'require_direct',false));
    source_provider=M.storage_provider;
    source_row_count=M.row_count;
    source_schema=M.schema;
    M=gxtxt_table_stream_close(M);
    if(!isfinite(source_row_count)||source_row_count<1)
      error('%s: source dataset contains no samples',module_id);
    endif
    ind_schema=find_schema(source_schema,ind_id);
    sig_schema=find_schema(source_schema,sig_id);
    if(isempty(ind_schema)||isempty(sig_schema))
      error('%s: selected variables are missing from the canonical source schema',module_id);
    endif

    axis_kind=lower(strtrim(ind_schema.axis_kind));
    axis_origin=str2double(strtrim(ind_schema.axis_origin));
    axis_step=str2double(strtrim(ind_schema.axis_step));
    uniform_axis=strcmp(axis_kind,'uniform') && isfinite(axis_origin) && isfinite(axis_step) && axis_step>0;

    % ---- optional framework Dataset Selection ---------------------------
    selection=struct('enabled',false);
    try selection=gxtxt_selection_from_runtime(cfg,'selection'); catch selerr
      error('%s: invalid Dataset Selection: %s',module_id,selerr.message);
    end_try_catch
    if(selection.enabled)
      validate_selection(selection,source_dataset_id,ind_id,ind_name);
    endif

    % ---- configuration --------------------------------------------------
    window=lower(strtrim(gxtxt_ini_get(cfg,'config.window','hann')));
    if(!any(strcmp(window,{'rectangular','hann','hamming','blackman_harris','flat_top'}))), window='hann'; endif

    analysis_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.analysis_mode','full_record')));
    if(!any(strcmp(analysis_mode,{'full_record','fixed_block','temporal_set'}))), analysis_mode='full_record'; endif
    fft_length_cfg=lower(strtrim(gxtxt_ini_get(cfg,'config.fft_length','auto')));
    if(isempty(fft_length_cfg)), fft_length_cfg='auto'; endif
    block_position=lower(strtrim(gxtxt_ini_get(cfg,'config.block_position','center')));
    if(!any(strcmp(block_position,{'start','center','explicit'}))), block_position='center'; endif
    block_start_cfg=parse_nonnegative_int(gxtxt_ini_get(cfg,'config.block_start_sample','0'));

    fund_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.fundamental_mode','auto_peak')));
    fund_hz=str2double(strtrim(gxtxt_ini_get(cfg,'config.fundamental_hz','')));
    track_harm=parse_int(gxtxt_ini_get(cfg,'config.track_harmonics','10'),10,2);
    spur_search=lower(strtrim(gxtxt_ini_get(cfg,'config.spur_search','all_nonfundamental')));
    guard=parse_int(gxtxt_ini_get(cfg,'config.spur_exclude_bins','2'),2,0);
    detrend_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.detrend','mean')));

    if(strcmp(analysis_mode,'temporal_set'))
      C=struct('cfg',cfg,'session',session,'outdir',outdir,'module_id',module_id,'module_version',module_version, ...
        'source_dataset_id',source_dataset_id,'source_provider',source_provider,'source_row_count',source_row_count, ...
        'ind_id',ind_id,'ind_name',ind_name,'ind_unit',ind_unit,'sig_id',sig_id,'sig_name',sig_name,'sig_unit',sig_unit, ...
        'axis_kind',axis_kind,'axis_origin',axis_origin,'axis_step',axis_step,'uniform_axis',uniform_axis,'selection',selection, ...
        'window',window,'fund_mode',fund_mode,'fund_hz',fund_hz,'track_harm',track_harm,'spur_search',spur_search, ...
        'guard',guard,'detrend_mode',detrend_mode,'numeric_fn',numeric_fn,'io_chunk_rows',io_chunk_rows,'publication_chunk_rows',publication_chunk_rows);
      run_temporal_set_mode(C);
      return;
    endif

    % ---- dataset-native source read -------------------------------------
    % Uniform canonical coordinates are authoritative. This avoids reading or
    % materializing millions of time values (notably Audio decode 2.0.0 HDF5).
    if(uniform_axis)
      [record_start,record_count]=uniform_record_range(selection,axis_origin,axis_step,source_row_count);
      if(record_count<1), error('%s: selected X/time interval contains no samples',module_id); endif
      record_N=record_count;
      source_record_N=source_row_count;

      [block_start,block_count,effective_position]=resolve_block(analysis_mode,fft_length_cfg,block_position,block_start_cfg,record_N);
      absolute_start=record_start+block_start;
      absolute_count=block_count;
      gxtxt_progress_stage('load_dataset','Reading selected canonical signal range','determinate',absolute_count);
      [x,source_range_mode]=load_uniform_signal(cfg,sig_id,absolute_start,absolute_count,io_chunk_rows);
      if(any(!isfinite(x)))
        error(['%s: uniformly sampled FFT input contains non-finite signal values. ' ...
               'A contiguous global FFT cannot silently remove samples; select or clean a valid interval first.'],module_id);
      endif
      N=numel(x);
      block_end=block_start+N-1;
      block_axis_start=axis_origin+absolute_start*axis_step;
      block_axis_end=axis_origin+(absolute_start+N-1)*axis_step;
      dt=axis_step;
      fs=1.0/dt;
      nonuniform=0;
    else
      % Compatibility path for canonical tables whose independent coordinate
      % is explicit. It still uses Table Stream v3 and never opens CSV/HDF5.
      gxtxt_progress_stage('load_dataset','Reading canonical explicit-axis signal','indeterminate');
      [t_all,x_all,source_range_mode]=load_explicit_pairs(cfg,ind_id,sig_id,selection,io_chunk_rows);
      record_N=numel(x_all); source_record_N=source_row_count;
      if(record_N<1), error('%s: no finite samples remain after source/selection filtering',module_id); endif
      [block_start,block_count,effective_position]=resolve_block(analysis_mode,fft_length_cfg,block_position,block_start_cfg,record_N);
      idx=(block_start+1):(block_start+block_count);
      t=t_all(idx); x=x_all(idx); N=numel(x); block_end=block_start+N-1;
      block_axis_start=t(1); block_axis_end=t(end);
      if(N<2), error('%s: cannot infer sampling step from fewer than two explicit coordinate values',module_id); endif
      dt_all=diff(t); dt=fft_median(numeric_fn,dt_all);
      if(!isfinite(dt)||dt<=0), error('%s: cannot infer a positive sample step from the independent axis',module_id); endif
      nonuniform=any(abs(dt_all-dt)>1e-6*abs(dt));
      fs=1.0/dt;
    endif

    % Preserve the legacy progress lifecycle as well as the numerical path.
    gxtxt_progress_stage('transform','Computing FFT','indeterminate');
    R=compute_fft_spectrum(x,dt,window,fund_mode,fund_hz,track_harm,spur_search,guard,detrend_mode,numeric_fn);
    N=R.N; fs=R.fs; df=R.df; cg=R.coherent_gain; amp=R.amp; Nh=R.Nh;
    fbin=R.fund_bin; A0=R.fund_amp; f0=R.f0; mag_dbc=R.magnitude_dbc;
    harm_bins=R.harm_bins; harm_amp=R.harm_amp; harm_freq=R.harm_freq;
    thd_db=R.thd_db; thd_pct=R.thd_pct; sfdr_db=R.sfdr_db; worst_dbc=R.worst_dbc;
    worst_amp=R.worst_amp; worst_freq=R.worst_freq; sinad_db=R.sinad_db; enob=R.enob;
    noise_floor=R.noise_floor; noise_floor_dbc=R.noise_floor_dbc;
    freq_is_hz=is_seconds(ind_unit);
    freq_unit='Hz'; if(!freq_is_hz), freq_unit=inv_unit(ind_unit); endif
    freq_name='frequency_Hz'; if(!freq_is_hz), freq_name='frequency'; endif
    stat_provenance=struct('source_dataset_id',source_dataset_id,'source_independent_variable_id',ind_id,'source_signal_variable_id',sig_id,'analysis_mode',analysis_mode,'block_start_sample',block_start,'block_row_count',N);
    if(selection.enabled),stat_provenance.selection_id=selection.id;endif
    R=capture_fft_quality(R,freq_unit,sig_unit,stat_provenance);

    selection_id=''; if(selection.enabled), selection_id=selection.id; endif
    metrics=struct('fs',fs,'N',N,'df',df,'window',window,'coherent_gain',cg, ...
                   'analysis_mode',analysis_mode,'fft_length_cfg',fft_length_cfg, ...
                   'block_position',effective_position,'block_start',block_start,'block_end',block_end, ...
                   'record_N',record_N,'source_record_N',source_record_N, ...
                   'block_axis_start',block_axis_start,'block_axis_end',block_axis_end, ...
                   'selection_id',selection_id,'source_provider',source_provider,'source_range_mode',source_range_mode, ...
                   'uniform_axis',uniform_axis,'f0',f0,'fund_bin',fbin,'fund_amp',A0, ...
                   'thd_db',thd_db,'thd_pct',thd_pct,'sfdr_db',sfdr_db,'sinad_db',sinad_db,'enob',enob, ...
                   'worst_freq',worst_freq,'worst_amp',worst_amp,'noise_floor',noise_floor,'nonuniform',nonuniform);
    metrics.statistics=R.statistics;metrics.component_statistics=R.component_statistics;

    % ---- canonical spectrum publication v2 ------------------------------
    pub_id=[nz(source_dataset_id,'signal') '.spectrum'];
    required={'typed_numeric','implicit_axis','range_write'};
    preferred={'sequential_chunks'};
    popts=struct('storage','auto','capabilities_required',{required},'capabilities_preferred',{preferred},'replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{ind_id,sig_id}});
    popts.statistical_results=struct('quality',R.statistics);
    gxtxt_progress_stage('publish','Publishing canonical spectrum dataset','determinate',Nh);
    P=gxtxt_publication_v2_open(session,module_id,pub_id,'spectrum.table',popts);
    publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'frequency_bin',Nh,false);
    P=gxtxt_publication_v2_declare_uniform(P,'frequency','frequency_bin',0,df, ...
      struct('name',freq_name,'unit',freq_unit,'dtype','float64','semantic_role','independent'));
    publication_chunks=min(publication_chunk_rows,Nh);
    P=gxtxt_publication_v2_declare_variable(P,'amplitude', ...
      struct('dtype','float64','dimension_ids','frequency_bin','name','amplitude','unit',sig_unit, ...
             'semantic_role','measured','coordinate_variable_ids','frequency','chunks',publication_chunks));
    P=gxtxt_publication_v2_declare_variable(P,'magnitude_dbc', ...
      struct('dtype','float64','dimension_ids','frequency_bin','name','magnitude_dBc','unit','dB', ...
             'semantic_role','measured','coordinate_variable_ids','frequency','chunks',publication_chunks));

    for start0=0:publication_chunk_rows:(Nh-1)
      count=min(publication_chunk_rows,Nh-start0);
      r=(start0+1):(start0+count);
      P=gxtxt_publication_v2_write_range(P,'amplitude',start0,amp(r));
      P=gxtxt_publication_v2_write_range(P,'magnitude_dbc',start0,mag_dbc(r));
      gxtxt_progress_update(start0+count,Nh,'publish',sprintf('Published %d / %d spectrum bins',start0+count,Nh));
    endfor
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    [P,pub_result]=gxtxt_publication_v2_finalize(P);
    publication_finalized=true; publication_open=false;
    output_provider=P.provider;

    % ---- computed annotations -------------------------------------------
    ann={};
    ann{end+1}=struct('id','fundamental','type','vline','x',f0,'x_variable',freq_name,'x_unit',freq_unit,'label','Fundamental','style_hint','primary');
    for i=1:numel(harm_freq)
      ann{end+1}=struct('id',sprintf('harmonic_%d',i+1),'type','vline','x',harm_freq(i),'x_variable',freq_name,'x_unit',freq_unit,'label',sprintf('%dx harmonic',i+1),'style_hint','harmonic');
    endfor
    if(isfinite(worst_freq)&&worst_freq>0)
      ann{end+1}=struct('id','sfdr_spur','type','point','x',worst_freq,'x_variable',freq_name,'x_unit',freq_unit,'y',worst_dbc,'y_variable','magnitude_dBc','y_unit','dB','label','SFDR spur','style_hint','spur');
    endif
    if(isfinite(noise_floor_dbc))
      ann{end+1}=struct('id','noise_floor','type','hline','y',noise_floor_dbc,'y_variable','magnitude_dBc','y_unit','dB','label','Noise floor','style_hint','threshold');
    endif
    ann_rel='spectrum.annotations.ini';
    try
      gxtxt_data_annotations_write(outdir,ann_rel,pub_id,ann);
    catch aerr
      fprintf(2,'[%s] warning: computed annotations skipped: %s\n',module_id,aerr.message);
    end_try_catch

    % Remove a stale v1 CSV from a reused module output directory. v2 does
    % not create a spectrum CSV; compatibility materialization belongs to CORE.
    stale_csv=fullfile(outdir,'spectrum.csv');
    if(exist(stale_csv,'file')==2), unlink(stale_csv); endif

    write_metrics_ini(fullfile(outdir,'fft_metrics.ini'),metrics,harm_freq,harm_amp,A0,output_provider,module_version);
    write_report(fullfile(outdir,'fft_report.txt'),metrics,harm_freq,harm_amp,A0,sig_name,sig_id,pub_id,nonuniform,output_provider,module_version,pub_diag,pub_result);

    gxtxt_progress_complete('done',sprintf('Published %s (%d bins)',pub_id,Nh));
    fprintf('[%s] version=%s dataset=%s signal=%s mode=%s block=%d..%d N=%d fs=%g window=%s provider=%s published=%s\n', ...
            module_id,module_version,source_dataset_id,sig_id,analysis_mode,block_start,block_end,N,fs,window,output_provider,pub_id);
  catch err
    if(publication_open && !publication_finalized)
      try P=gxtxt_publication_v2_abort(P); catch; end_try_catch
    endif
    try gxtxt_progress_fail('failed','FFT spectrum analysis failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

% ======================================================================
function schema=find_schema(schema_list,variable_id)
  schema=[];
  for i=1:numel(schema_list)
    if(strcmp(strtrim(schema_list(i).variable_id),variable_id)), schema=schema_list(i); return; endif
  endfor
endfunction

function validate_selection(S,dataset_id,ind_id,ind_name)
  if(!strcmp(S.type,'x_range'))
    error('analysis.fft_spectrum: only x_range Dataset Selection is supported');
  endif
  if(!strcmp(strtrim(S.source_dataset_id),dataset_id))
    error('analysis.fft_spectrum: Dataset Selection belongs to a different source dataset');
  endif
  if(!isempty(strtrim(S.x_variable_id)))
    if(!strcmp(strtrim(S.x_variable_id),ind_id))
      error('analysis.fft_spectrum: Dataset Selection X variable does not match the FFT independent binding');
    endif
  elseif(!strcmp(strtrim(S.x_variable),ind_name))
    error('analysis.fft_spectrum: Dataset Selection X variable does not match the FFT independent binding');
  endif
endfunction

function [start0,count]=uniform_record_range(S,origin,step,total_count)
  start0=0; count=total_count;
  if(!S.enabled), return; endif
  lo=min(S.x_min,S.x_max); hi=max(S.x_min,S.x_max);
  tol=1e-10;
  first=ceil((lo-origin)/step-tol);
  last=floor((hi-origin)/step+tol);
  first=max(0,first); last=min(total_count-1,last);
  if(last<first), start0=0; count=0; else start0=first; count=last-first+1; endif
endfunction

function [start0,count,pos]=resolve_block(mode,fft_length_cfg,block_position,block_start_cfg,record_N)
  if(strcmp(mode,'full_record'))
    start0=0; count=record_N; pos='full'; return;
  endif
  count=parse_fft_length(fft_length_cfg);
  if(!isfinite(count))
    error(['analysis.fft_spectrum: Fixed-length block requires an explicit FFT length. ' ...
           'Choose 16384, 32768, 65536, ...; "auto" is reserved for Full record.']);
  endif
  if(record_N<count)
    error('analysis.fft_spectrum: requested FFT length %d exceeds the %d samples in the selected record',count,record_N);
  endif
  switch(block_position)
    case 'start'
      start0=0; pos='start';
    case 'center'
      start0=floor((record_N-count)/2); pos='center';
    case 'explicit'
      if(!isfinite(block_start_cfg)), error('analysis.fft_spectrum: explicit block position requires a non-negative 0-based start sample'); endif
      start0=block_start_cfg; pos='explicit';
    otherwise
      start0=0; pos='start';
  endswitch
  if(start0+count>record_N)
    error('analysis.fft_spectrum: selected block [%d..%d] exceeds the %d-sample selected record',start0,start0+count-1,record_N);
  endif
endfunction

function [x,range_mode]=load_uniform_signal(cfg,sig_id,start0,count,chunk_rows)
  S=gxtxt_table_stream_open_source(cfg,'primary',{sig_id},chunk_rows, ...
    struct('start',start0,'count',count,'require_direct',false));
  range_mode=S.range_mode;
  x=zeros(count,1); n=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows>0)
        v=double(C.values{1}(:));
        x(n+1:n+C.nrows)=v; n+=C.nrows;
        gxtxt_progress_update(n,count,'load_dataset',sprintf('Read %d / %d samples',n,count));
      endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(n!=count), error('analysis.fft_spectrum: source range returned %d samples; expected %d',n,count); endif
endfunction

function [t,x,range_mode]=load_explicit_pairs(cfg,ind_id,sig_id,selection,chunk_rows)
  S=gxtxt_table_stream_open_source(cfg,'primary',{ind_id,sig_id},chunk_rows,struct('start',0,'count',-1,'require_direct',false));
  range_mode=S.range_mode; tcells={}; xcells={}; total=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows<1), continue; endif
      tv=double(C.values{1}(:)); xv=double(C.values{2}(:));
      keep=isfinite(tv)&isfinite(xv);
      if(selection.enabled), keep=keep & gxtxt_selection_mask(selection,tv); endif
      if(any(keep))
        tcells{end+1}=tv(keep); xcells{end+1}=xv(keep); total+=sum(keep);
      endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(total<1), t=zeros(0,1); x=zeros(0,1); return; endif
  t=vertcat(tcells{:}); x=vertcat(xcells{:});
endfunction

function run_temporal_set_mode(C)
  T=gxtxt_temporal_set_from_runtime(C.cfg,'temporal_set');
  if(!T.enabled), error('%s: analysis_mode=temporal_set requires a configured Temporal Set',C.module_id); endif
  if(!strcmp(T.source_dataset_id,C.source_dataset_id))
    error('%s: Temporal Set %s belongs to Dataset %s, not the selected primary Dataset %s',C.module_id,T.id,T.source_dataset_id,C.source_dataset_id);
  endif
  if(!strcmp(T.temporal_variable_id,C.ind_id))
    error('%s: Temporal Set %s uses temporal variable %s, not the FFT independent binding %s',C.module_id,T.id,T.temporal_variable_id,C.ind_id);
  endif
  if(C.selection.enabled)
    error(['%s: analysis_mode=temporal_set cannot also apply config.selection. ' ...
           'Use the Temporal Set parent Dataset Selection when a parent interval is required.'],C.module_id);
  endif
  if(T.member_count<1), error('%s: Temporal Set %s resolves to no members',C.module_id,T.id); endif
  if(strcmp(T.axis_kind,'uniform')!=C.uniform_axis)
    error('%s: Temporal Set %s axis metadata is inconsistent with the selected Dataset runtime',C.module_id,T.id);
  endif

  stale_csv=fullfile(C.outdir,'spectrum.csv');
  if(exist(stale_csv,'file')==2), unlink(stale_csv); endif
  results=cell(1,T.member_count);
  gxtxt_progress_stage('temporal_members',sprintf('Processing %d Temporal Set members',T.member_count),'determinate',T.member_count);

  for member_index=1:T.member_count
    M=gxtxt_temporal_set_member(T,member_index);
    if(M.row_count<8)
      error('%s: Temporal Set %s member %s resolves to %d samples; FFT requires at least 8',C.module_id,T.id,M.member_id,M.row_count);
    endif
    if(C.uniform_axis)
      [x,source_range_mode]=load_uniform_signal(C.cfg,C.sig_id,M.row_start,M.row_count,C.io_chunk_rows);
      if(any(!isfinite(x)))
        error('%s: Temporal Set %s member %s contains non-finite signal values',C.module_id,T.id,M.member_id);
      endif
      dt=C.axis_step; nonuniform=0;
      block_axis_start=C.axis_origin+M.row_start*C.axis_step;
      block_axis_end=C.axis_origin+(M.row_start+M.row_count-1)*C.axis_step;
    else
      [t,x,source_range_mode]=load_explicit_range(C.cfg,C.ind_id,C.sig_id,M.row_start,M.row_count,C.io_chunk_rows);
      if(any(!isfinite(t))||any(!isfinite(x)))
        error('%s: Temporal Set %s member %s contains non-finite coordinate or signal values',C.module_id,T.id,M.member_id);
      endif
      if(numel(t)<2), error('%s: Temporal Set %s member %s is too short to infer sampling step',C.module_id,T.id,M.member_id); endif
      dt_all=diff(t); dt=fft_median(C.numeric_fn,dt_all);
      if(!isfinite(dt)||dt<=0), error('%s: Temporal Set %s member %s has no positive sampling step',C.module_id,T.id,M.member_id); endif
      nonuniform=any(abs(dt_all-dt)>1e-6*abs(dt));
      block_axis_start=t(1); block_axis_end=t(end);
    endif

    R=compute_fft_spectrum(x,dt,C.window,C.fund_mode,C.fund_hz,C.track_harm,C.spur_search,C.guard,C.detrend_mode,C.numeric_fn);
    temporal_unit=strtrim(T.temporal_unit); if(isempty(temporal_unit)), temporal_unit=C.ind_unit; endif
    freq_is_hz=is_seconds(temporal_unit);
    freq_unit='Hz'; if(!freq_is_hz), freq_unit=inv_unit(temporal_unit); endif
    freq_name='frequency_Hz'; if(!freq_is_hz), freq_name='frequency'; endif
    stat_provenance=struct('source_dataset_id',C.source_dataset_id,'source_independent_variable_id',C.ind_id,'source_signal_variable_id',C.sig_id,'analysis_mode','temporal_set','temporal_set_id',T.id,'temporal_member_id',M.member_id,'source_row_start',M.row_start,'source_row_count',M.row_count);
    R=capture_fft_quality(R,freq_unit,C.sig_unit,stat_provenance);
    pub_id=sprintf('%s.spectrum.%s.%s',C.source_dataset_id,T.id,M.member_id);

    provenance=sprintf('Temporal Set %s member %s index %d; source rows %d..%d; boundary=%s', ...
      T.id,M.member_id,member_index,M.row_start,M.row_start+M.row_count-1,T.boundary_policy);
    if(isfinite(M.time_start)&&isfinite(M.time_end))
      provenance=sprintf('%s; time [%.17g, %.17g) %s',provenance,M.time_start,M.time_end,temporal_unit);
    endif
    notes=''; if(!isempty(strtrim(M.label))), notes=['Temporal member label: ' one_line(M.label)]; endif
    required={'typed_numeric','implicit_axis','range_write'}; preferred={'sequential_chunks'};
    popts=struct('storage','auto','capabilities_required',{required},'capabilities_preferred',{preferred},'replace_owned',true, ...
      'producer_version',C.module_version,'source_dataset_ids',{{C.source_dataset_id}}, ...
      'source_variable_ids',{{C.ind_id,C.sig_id}},'source',C.source_dataset_id,'provenance',provenance,'notes',notes);

    popts.statistical_results=struct('quality',R.statistics);
    [output_provider,pub_diag,pub_result]=publish_spectrum(C,pub_id,R,freq_name,freq_unit,popts);
    write_spectrum_annotations(C.outdir,sprintf('spectrum.%s.%s.annotations.ini',T.id,M.member_id),pub_id,R,freq_name,freq_unit);

    metrics=struct('fs',R.fs,'N',R.N,'df',R.df,'window',C.window,'coherent_gain',R.coherent_gain, ...
      'analysis_mode','temporal_set','fft_length_cfg','member','block_position','member', ...
      'block_start',0,'block_end',R.N-1,'record_N',M.row_count,'source_record_N',C.source_row_count, ...
      'block_axis_start',block_axis_start,'block_axis_end',block_axis_end,'selection_id',T.parent_selection_id, ...
      'source_provider',C.source_provider,'source_range_mode',source_range_mode,'uniform_axis',C.uniform_axis, ...
      'f0',R.f0,'fund_bin',R.fund_bin,'fund_amp',R.fund_amp,'thd_db',R.thd_db,'thd_pct',R.thd_pct, ...
      'sfdr_db',R.sfdr_db,'sinad_db',R.sinad_db,'enob',R.enob,'worst_freq',R.worst_freq, ...
      'worst_amp',R.worst_amp,'noise_floor',R.noise_floor,'nonuniform',nonuniform);
    metrics.statistics=R.statistics;metrics.component_statistics=R.component_statistics;
    results{member_index}=struct('member',M,'metrics',metrics,'result',R,'pub_id',pub_id, ...
      'provider',output_provider,'pub_diag',pub_diag,'pub_result',pub_result);
    gxtxt_progress_update(member_index,T.member_count,'temporal_members', ...
      sprintf('Processed Temporal Set member %d / %d',member_index,T.member_count));
  endfor

  write_temporal_metrics_ini(fullfile(C.outdir,'fft_metrics.ini'),T,results,C.module_version);
  write_temporal_report(fullfile(C.outdir,'fft_report.txt'),T,results,C.sig_name,C.sig_id,C.module_version);
  gxtxt_progress_complete('done',sprintf('Published %d independent FFT spectra from Temporal Set %s',T.member_count,T.id));
  fprintf('[%s] version=%s dataset=%s signal=%s mode=temporal_set temporal_set=%s type=%s members=%d\n', ...
    C.module_id,C.module_version,C.source_dataset_id,C.sig_id,T.id,T.type,T.member_count);
endfunction

function [provider,pub_diag,pub_result]=publish_spectrum(C,pub_id,R,freq_name,freq_unit,popts)
  P=struct(); opened=false; finalized=false;
  try
    gxtxt_progress_stage('publish',sprintf('Publishing %s',pub_id),'determinate',R.Nh);
    P=gxtxt_publication_v2_open(C.session,C.module_id,pub_id,'spectrum.table',popts); opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'frequency_bin',R.Nh,false);
    P=gxtxt_publication_v2_declare_uniform(P,'frequency','frequency_bin',0,R.df, ...
      struct('name',freq_name,'unit',freq_unit,'dtype','float64','semantic_role','independent'));
    publication_chunks=min(C.publication_chunk_rows,R.Nh);
    P=gxtxt_publication_v2_declare_variable(P,'amplitude', ...
      struct('dtype','float64','dimension_ids','frequency_bin','name','amplitude','unit',C.sig_unit, ...
             'semantic_role','measured','coordinate_variable_ids','frequency','chunks',publication_chunks));
    P=gxtxt_publication_v2_declare_variable(P,'magnitude_dbc', ...
      struct('dtype','float64','dimension_ids','frequency_bin','name','magnitude_dBc','unit','dB', ...
             'semantic_role','measured','coordinate_variable_ids','frequency','chunks',publication_chunks));
    for start0=0:C.publication_chunk_rows:(R.Nh-1)
      count=min(C.publication_chunk_rows,R.Nh-start0); rr=(start0+1):(start0+count);
      P=gxtxt_publication_v2_write_range(P,'amplitude',start0,R.amp(rr));
      P=gxtxt_publication_v2_write_range(P,'magnitude_dbc',start0,R.magnitude_dbc(rr));
    endfor
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);
    [P,pub_result]=gxtxt_publication_v2_finalize(P); finalized=true; opened=false; provider=P.provider;
  catch err
    if(opened&&!finalized), try P=gxtxt_publication_v2_abort(P); catch; end_try_catch; endif
    rethrow(err);
  end_try_catch
endfunction

function write_spectrum_annotations(outdir,ann_rel,pub_id,R,freq_name,freq_unit)
  ann={};
  ann{end+1}=struct('id','fundamental','type','vline','x',R.f0,'x_variable',freq_name,'x_unit',freq_unit,'label','Fundamental','style_hint','primary');
  for i=1:numel(R.harm_freq)
    ann{end+1}=struct('id',sprintf('harmonic_%d',i+1),'type','vline','x',R.harm_freq(i),'x_variable',freq_name,'x_unit',freq_unit,'label',sprintf('%dx harmonic',i+1),'style_hint','harmonic');
  endfor
  if(isfinite(R.worst_freq)&&R.worst_freq>0)
    ann{end+1}=struct('id','sfdr_spur','type','point','x',R.worst_freq,'x_variable',freq_name,'x_unit',freq_unit,'y',R.worst_dbc,'y_variable','magnitude_dBc','y_unit','dB','label','SFDR spur','style_hint','spur');
  endif
  if(isfinite(R.noise_floor_dbc))
    ann{end+1}=struct('id','noise_floor','type','hline','y',R.noise_floor_dbc,'y_variable','magnitude_dBc','y_unit','dB','label','Noise floor','style_hint','threshold');
  endif
  try gxtxt_data_annotations_write(outdir,ann_rel,pub_id,ann); catch aerr
    fprintf(2,'[analysis.fft_spectrum] warning: computed annotations skipped for %s: %s\n',pub_id,aerr.message);
  end_try_catch
endfunction

function [t,x,range_mode]=load_explicit_range(cfg,ind_id,sig_id,start0,count,chunk_rows)
  S=gxtxt_table_stream_open_source(cfg,'primary',{ind_id,sig_id},chunk_rows,struct('start',start0,'count',count,'require_direct',false));
  range_mode=S.range_mode; tcells={}; xcells={}; total=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S); if(C.nrows<1), continue; endif
      tcells{end+1}=double(C.values{1}(:)); xcells{end+1}=double(C.values{2}(:)); total+=C.nrows;
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(total!=count), error('analysis.fft_spectrum: source range returned %d rows; expected %d',total,count); endif
  if(total<1), t=zeros(0,1); x=zeros(0,1); else t=vertcat(tcells{:}); x=vertcat(xcells{:}); endif
endfunction

function write_temporal_metrics_ini(path,T,results,module_version)
  fid=fopen(path,'w'); if(fid<0), error('analysis.fft_spectrum: cannot write Temporal Set metrics'); endif
  unwind_protect
    fprintf(fid,'; GX-TXT analysis.fft_spectrum Temporal Set metrics\n[fft]\n');
    fprintf(fid,'module_version=%s\nanalysis_mode=temporal_set\ntemporal_set_id=%s\ntemporal_set_type=%s\nmember_count=%d\n', ...
      module_version,T.id,T.type,T.member_count);
    fprintf(fid,'source_dataset_id=%s\ntemporal_variable_id=%s\nparent_selection_id=%s\nboundary_policy=%s\n', ...
      T.source_dataset_id,T.temporal_variable_id,T.parent_selection_id,T.boundary_policy);
    for i=1:numel(results)
      E=results{i}; M=E.member; m=E.metrics; R=E.result;
      fprintf(fid,'\n[member.%d]\n',i);
      fprintf(fid,'member_id=%s\nlabel=%s\npublished_dataset_id=%s\n',M.member_id,ini_escape(M.label),E.pub_id);
      fprintf(fid,'row_start=%d\nrow_count=%d\ntime_start=%s\ntime_end=%s\n',M.row_start,M.row_count,num_text(M.time_start),num_text(M.time_end));
      fprintf(fid,'fs=%.10g\nN=%d\ndelta_f=%.10g\nwindow=%s\ncoherent_gain=%.10g\n',m.fs,m.N,m.df,m.window,m.coherent_gain);
      fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',m.statistics,struct('fundamental_hz','spectrum_reference_frequency','fundamental_amp','spectrum_reference_amplitude')));
      fprintf(fid,'fundamental_bin=%d\n',m.fund_bin);
      fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',m.statistics,struct('thd_db','amplitude_thd_level','thd_pct','amplitude_thd_percent','sfdr_db','amplitude_sfdr_level','sinad_db','amplitude_sinad_level','enob','amplitude_nominal_bits')));
      write_component_ini(fid,m.component_statistics,sprintf('member.%d.',i));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_temporal_report(path,T,results,sig,sig_id,module_version)
  fid=fopen(path,'w'); if(fid<0), error('analysis.fft_spectrum: cannot write Temporal Set report'); endif
  unwind_protect
    fprintf(fid,'FFT Spectrum & Error Analysis — Temporal Set\n============================================\n');
    fprintf(fid,'module version     : %s\nsignal             : %s (%s)\n',module_version,sig,sig_id);
    fprintf(fid,'Temporal Set       : %s (%s)\nsource Dataset     : %s\ntemporal variable  : %s\n',T.id,T.type,T.source_dataset_id,T.temporal_variable_id);
    if(!isempty(T.parent_selection_id)), fprintf(fid,'parent Selection   : %s\n',T.parent_selection_id); endif
    fprintf(fid,'members            : %d\nboundary policy    : %s\n\n',T.member_count,T.boundary_policy);
    for i=1:numel(results)
      E=results{i}; M=E.member; m=E.metrics;
      fprintf(fid,'Member %d — %s',i,M.member_id); if(!isempty(M.label)), fprintf(fid,' — %s',one_line(M.label)); endif; fprintf(fid,'\n');
      fprintf(fid,'  source rows       : %d .. %d (%d samples)\n',M.row_start,M.row_start+M.row_count-1,M.row_count);
      if(isfinite(M.time_start)&&isfinite(M.time_end)), fprintf(fid,'  temporal interval : [%.10g, %.10g) %s\n',M.time_start,M.time_end,T.temporal_unit); endif
      fprintf(fid,'  published dataset : %s\n  fs / df            : %.10g / %.10g\n',E.pub_id,m.fs,m.df);
      fprintf(fid,'%s\n',gxtxt_statistics_v1('report',m.statistics,{'spectrum_reference_frequency','amplitude_thd_level','amplitude_sfdr_level','amplitude_sinad_level'}));
      write_component_report(fid,m.component_statistics);
    endfor
    fprintf(fid,'Each Temporal Set member is transformed independently. Separated regions are never concatenated.\n');
    fprintf(fid,'Variable-length segment members therefore retain independent frequency grids as separate spectrum.table datasets.\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function s=one_line(s)
  s=strrep(char(s),sprintf('\r'),' '); s=strrep(s,sprintf('\n'),' ');
endfunction
function s=ini_escape(s)
  s=strrep(char(s),'\\','\\\\'); s=strrep(s,sprintf('\r'),'\\n'); s=strrep(s,sprintf('\n'),'\\n');
endfunction
function s=num_text(v)
  if(isfinite(v)), s=sprintf('%.17g',v); else s=''; endif
endfunction

function R=compute_fft_spectrum(x,dt,window,fund_mode,fund_hz,track_harm,spur_search,guard,detrend_mode,numeric_fn)
  options=struct('window',window,'fundamental_mode',fund_mode,'track_harmonics',track_harm,'spur_search',spur_search,'guard_bins',guard,'detrend',detrend_mode);
  if(strcmp(fund_mode,'explicit')),options.fundamental_hz=fund_hz;endif
  R=feval(numeric_fn,'fft_spectrum_quality',x,dt,options);
endfunction

function R=capture_fft_quality(R,frequency_unit,amplitude_unit,provenance)
  context=struct('x_unit',frequency_unit,'y_unit',amplitude_unit);
  R.statistics=gxtxt_statistics_v1('from_numeric','math.numeric.fft_spectrum_quality','fft_spectrum_quality',R,context,struct(),provenance);
  R.component_statistics={};count=numel(R.component_order);
  mapping=gxtxt_statistics_v1('numeric_field_map','harmonic_components');
  common=struct('fundamental_amplitude',R.fundamental_amplitude,'component_method',R.component_method,'component_level_floor',R.component_level_floor);
  for start=1:512:count
    selected=start:min(count,start+511);columns=struct();ids=cell(numel(selected),1);
    for key=fieldnames(mapping)'
      name=key{1};if(!strcmp(name,'fundamental_amplitude')),columns.(name)=R.(name)(selected);endif
    endfor
    for k=1:numel(selected),ids{k}=sprintf('H%d',R.component_order(selected(k)));endfor
    R.component_statistics{end+1}=gxtxt_statistics_v1('from_numeric_columns','math.numeric.harmonic_components','harmonic_components',ids,columns,common,context,provenance);
  endfor
endfunction
function write_component_ini(fid,tables,prefix)
  mapping=struct('order','harmonic_order','frequency_hz','harmonic_frequency','amp','harmonic_amplitude','dbc','harmonic_level_db');
  for k=1:numel(tables)
    rows=gxtxt_statistics_v1('table_csv_rows',tables{k},mapping);
    for j=1:numel(rows.records)
      fields=strsplit(rows.records{j},',','collapsedelimiters',false);
      fprintf(fid,'\n[%sharmonic.%s]\norder=%s\nfrequency_hz=%s\namp=%s\ndbc=%s\n',prefix,fields{1},fields{1},fields{2},fields{3},fields{4});
    endfor
  endfor
endfunction
function write_component_report(fid,tables)
  for k=1:numel(tables)
    fprintf(fid,'%s\n',gxtxt_statistics_v1('table_report',tables{k},tables{k}.row_ids,{'harmonic_order','harmonic_frequency','harmonic_amplitude','harmonic_level_db'}));
  endfor
endfunction

function write_metrics_ini(path,m,hf,ha,A0,provider,module_version)
  fid=fopen(path,'w'); if(fid<0), error('analysis.fft_spectrum: cannot write metrics'); endif
  unwind_protect
    fprintf(fid,'; GX-TXT analysis.fft_spectrum metrics\n[fft]\n');
    fprintf(fid,'module_version=%s\nfs=%.10g\nN=%d\ndelta_f=%.10g\nwindow=%s\ncoherent_gain=%.10g\n',module_version,m.fs,m.N,m.df,m.window,m.coherent_gain);
    fprintf(fid,'analysis_mode=%s\nfft_length_config=%s\nblock_position=%s\n',m.analysis_mode,m.fft_length_cfg,m.block_position);
    fprintf(fid,'block_start_sample=%d\nblock_end_sample=%d\nblock_axis_start=%.10g\nblock_axis_end=%.10g\n',m.block_start,m.block_end,m.block_axis_start,m.block_axis_end);
    fprintf(fid,'record_samples=%d\nsource_record_samples=%d\n',m.record_N,m.source_record_N);
    fprintf(fid,'dataset_selection_id=%s\nsource_storage_provider=%s\nsource_range_mode=%s\nsource_uniform_axis=%d\n',m.selection_id,m.source_provider,m.source_range_mode,m.uniform_axis);
    fprintf(fid,'publication_api=2\nstorage_request=auto\neffective_storage_provider=%s\n',provider);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',m.statistics,struct('fundamental_hz','spectrum_reference_frequency','fundamental_amp','spectrum_reference_amplitude')));
    fprintf(fid,'fundamental_bin=%d\n',m.fund_bin);
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',m.statistics,struct('thd_db','amplitude_thd_level','thd_pct','amplitude_thd_percent','sfdr_db','amplitude_sfdr_level','sinad_db','amplitude_sinad_level','enob','amplitude_nominal_bits')));
    fprintf(fid,'%s\n',gxtxt_statistics_v1('ini_report',m.statistics,struct('worst_spur_hz','amplitude_spur_frequency','worst_spur_amp','amplitude_spur','noise_floor','amplitude_noise_median')));
    fprintf(fid,'nonuniform_sampling=%d\n',m.nonuniform);
    write_component_ini(fid,m.component_statistics,'');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report(path,m,hf,ha,A0,sig,sig_id,pub_id,nonuniform,provider,module_version,pub_diag,pub_result)
  fid=fopen(path,'w'); if(fid<0), error('analysis.fft_spectrum: cannot write report'); endif
  unwind_protect
    fprintf(fid,'FFT Spectrum & Error Analysis\n=============================\n');
    fprintf(fid,'module version     : %s\n',module_version);
    fprintf(fid,'signal             : %s (%s)\n',sig,sig_id);
    fprintf(fid,'published dataset  : %s (spectrum.table)\n',pub_id);
    fprintf(fid,'source provider    : %s (%s)\n',m.source_provider,m.source_range_mode);
    fprintf(fid,'output provider    : %s (Storage Auto)\n',provider);
    if(!isempty(m.selection_id)), fprintf(fid,'Dataset Selection  : %s\n',m.selection_id); endif
    fprintf(fid,'window             : %s\n',m.window);
    fprintf(fid,'analysis mode      : %s\n',m.analysis_mode);
    fprintf(fid,'FFT length config  : %s\n',m.fft_length_cfg);
    fprintf(fid,'block position     : %s\n',m.block_position);
    fprintf(fid,'block samples      : %d .. %d (0-based within selected record)\n',m.block_start,m.block_end);
    fprintf(fid,'block axis range   : %.10g .. %.10g\n',m.block_axis_start,m.block_axis_end);
    fprintf(fid,'selected samples   : %d\n',m.record_N);
    fprintf(fid,'source samples     : %d\n',m.source_record_N);
    fprintf(fid,'samples N (FFT)    : %d\n',m.N);
    fprintf(fid,'sample rate fs     : %.6g\n',m.fs);
    fprintf(fid,'resolution df      : %.6g\n',m.df);
    fprintf(fid,'uniform axis meta  : %s\n',yesno(m.uniform_axis));
    if(nonuniform), fprintf(fid,'WARNING            : non-uniform sampling detected; fs taken from the median step.\n'); endif
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',m.statistics,{'spectrum_reference_frequency','spectrum_reference_amplitude'}));
    fprintf(fid,'%s\n',gxtxt_statistics_v1('report',m.statistics,{'amplitude_thd_level','amplitude_thd_percent','amplitude_sfdr_level','amplitude_sinad_level','amplitude_nominal_bits','amplitude_noise_median'}));
    write_component_report(fid,m.component_statistics);
    fprintf(fid,'\npublication diagnostics: %s\n',pub_diag);
    fprintf(fid,'publication result     : %s\n',pub_result);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function tf=is_seconds(u)
  u=lower(strtrim(u));
  tf=any(strcmp(u,{'s','sec','second','seconds'}));
endfunction
function u=inv_unit(u0)
  u0=strtrim(u0); if(isempty(u0)), u='1/unit'; else u=['1/' u0]; endif
endfunction
function s=yesno(v), if(v), s='yes'; else s='no'; endif; endfunction
function s=nz(s,def), s=strtrim(s); if(isempty(s)), s=def; endif; endfunction
function v=arg_value(args,key,def), v=def; for k=1:numel(args)-1, if(strcmp(args{k},key)), v=args{k+1}; return; endif; endfor; endfunction
function col=binding_column(v,role)
  col=strtrim(v); if(isempty(col)||strcmp(col,'auto')), col=''; return; endif
  dot=find(col=='.',1);
  if(!isempty(dot)), src=strtrim(col(1:dot-1)); if(!strcmp(src,'primary')), error('analysis.fft_spectrum: binding %s must refer to primary.*, got %s',role,col); endif; col=strtrim(col(dot+1:end)); endif
endfunction
function n=parse_int(s,def,minv), n=str2double(s); if(!isfinite(n)||n<minv), n=def; else n=round(n); endif; endfunction
function n=parse_nonnegative_int(s)
  n=str2double(strtrim(s));
  if(!isfinite(n)||n<0||abs(n-round(n))>1e-9), n=NaN; else n=round(n); endif
endfunction
function n=parse_fft_length(s)
  s=lower(strtrim(s));
  if(isempty(s)||strcmp(s,'auto')||strcmp(s,'full')), n=NaN; return; endif
  n=str2double(s);
  if(!isfinite(n)||n<8||abs(n-round(n))>1e-9), n=NaN; else n=round(n); endif
endfunction

function fn=fft_numeric_binding(cfg)
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(gxtxt_ini_get(cfg,[prefix 'module_id'],''));version=strtrim(gxtxt_ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_entrypoint'],''));fn=strtrim(gxtxt_ini_get(cfg,[prefix 'octave_function'],''));
  caps=strsplit(strrep(gxtxt_ini_get(cfg,[prefix 'capabilities'],''),',',';'),';');caps=cellfun(@strtrim,caps,'UniformOutput',false);
  required={'fft','detrending','window_generation','descriptive_statistics'};
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(fn)||exist(entry,'file')!=2||!all(ismember(required,caps)))
    error('analysis.fft_spectrum: public NUMERIC_API_v1 transform binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2),error('analysis.fft_spectrum: public numeric Octave function is unavailable');endif
endfunction

function v=fft_median(numeric_fn,x)
  s=feval(numeric_fn,'statistics',double(x(:)),struct());v=s.median;
endfunction
