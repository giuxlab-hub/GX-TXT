% GX-TXT Time-Dependent FFT process worker.
% Reads only one resolved Temporal Set window and writes one temporary result.
% SPDX-License-Identifier: GPL-3.0-or-later

this_file=mfilename('fullpath');
runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);
addpath(runtime_dir);for d={'analysis','io','units','util'},addpath(fullfile(package_root,'core','octave',d{1}));endfor
args=argv();

% Parse the argv-style request inline. This worker is executed by Octave as a
% script, so it must not depend on script-local functions being visible before
% the end of the file has been parsed/executed.
runtime_path='';item_id='';time_id='';signal_id='';row_start=0;row_count=-1;nfft=-1;
window_name='hann';detrend_mode='mean';representation='amplitude';dt_seconds=NaN;
axis_kind='';axis_origin=NaN;axis_step=NaN;result_path='';timing_tolerance=1e-6;
i=1;
while(i<=numel(args))
  key=args{i};
  if(i==numel(args)),error('analysis.time_dependent_fft worker: missing value for argument %s',key);endif
  value=args{i+1};
  switch(key)
    case '--runtime'
      runtime_path=value;
    case '--item-id'
      item_id=value;
    case '--time-id'
      time_id=value;
    case '--signal-id'
      signal_id=value;
    case '--row-start'
      row_start=str2double(value);
    case '--row-count'
      row_count=str2double(value);
    case '--nfft'
      nfft=str2double(value);
    case '--window'
      window_name=value;
    case '--detrend'
      detrend_mode=value;
    case '--representation'
      representation=value;
    case '--dt-seconds'
      dt_seconds=str2double(value);
    case '--axis-kind'
      axis_kind=lower(strtrim(value));
    case '--axis-origin'
      axis_origin=str2double(value);
    case '--axis-step'
      axis_step=str2double(value);
    case '--result'
      result_path=value;
    case '--timing-tolerance'
      timing_tolerance=str2double(value);
    otherwise
      error('analysis.time_dependent_fft worker: unknown argument %s',key);
  endswitch
  i+=2;
endwhile
if(!isfinite(row_start)||row_start!=fix(row_start)),row_start=0;endif
if(!isfinite(row_count)||row_count!=fix(row_count)),row_count=-1;endif
if(!isfinite(nfft)||nfft!=fix(nfft)),nfft=-1;endif

if(isempty(runtime_path)||isempty(item_id)||isempty(signal_id)||isempty(result_path)),error('analysis.time_dependent_fft worker: incomplete request');endif
if(row_start<0||row_count<2),error('analysis.time_dependent_fft worker: invalid source range');endif

% Respect the generic internal-thread recommendation exported by CORE Parallel
% Execution. No FFT-specific worker-count policy is implemented here.
thread_hint=str2double(strtrim(getenv('GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS')));
cfg=gxtxt_ini_read(runtime_path);
numeric_api=tdfft_numeric_api(cfg);
if(isfinite(thread_hint)&&thread_hint>=1)
  feval(numeric_api,'configure_fft_threads',max(1,round(thread_hint)));
endif
vars={signal_id};if(!strcmp(axis_kind,'uniform')),vars={time_id,signal_id};endif
S=gxtxt_table_stream_open_source(cfg,'primary',vars,min(65536,row_count),struct('start',row_start,'count',row_count,'require_direct',false,'numeric_transport','auto'));
x=zeros(row_count,1);t=[];if(!strcmp(axis_kind,'uniform')),t=zeros(row_count,1);endif
pos=1;
unwind_protect
  while(true)
    [S,ch]=gxtxt_table_stream_v3_next(S);
    if(ch.nrows>0)
      xv=gxtxt_table_chunk_numeric(ch,signal_id);n=numel(xv);
      if(pos+n-1>row_count),error('analysis.time_dependent_fft worker: source returned too many samples');endif
      x(pos:pos+n-1)=xv(:);
      if(!strcmp(axis_kind,'uniform')),tv=gxtxt_table_chunk_numeric(ch,time_id);t(pos:pos+n-1)=tv(:);endif
      pos+=n;
    endif
    if(ch.eof),break;endif
  endwhile
unwind_protect_cleanup
  S=gxtxt_table_stream_close(S);
end_unwind_protect
if(pos-1!=row_count),error('analysis.time_dependent_fft worker: expected %d samples, received %d',row_count,pos-1);endif
if(any(!isfinite(x))),error('analysis.time_dependent_fft worker: signal window contains non-finite samples');endif

if(strcmp(axis_kind,'uniform'))
  if(!isfinite(axis_origin)||!isfinite(axis_step)||axis_step<=0),error('analysis.time_dependent_fft worker: invalid uniform time axis metadata');endif
  time_center=axis_origin+(row_start+(row_count-1)/2.0)*axis_step;
else
  if(any(!isfinite(t))),error('analysis.time_dependent_fft worker: temporal window contains non-finite coordinates');endif
  G=feval(numeric_api,'grid_info',t,struct('rtol',timing_tolerance,'atol',0,'nonfinite','error'));
  if(!G.strict_monotonic||!strcmp(G.direction,'increasing')),error('analysis.time_dependent_fft worker: temporal coordinates must be strictly increasing');endif
  % Preserve the original mean-relative FFT timing criterion.
  % The public grid diagnostic also offers median-based metrics with a different scale.
  dm=double(G.step_mean);
  rel=max(abs([double(G.step_min)-dm,double(G.step_max)-dm]))/max(abs(dm),realmin);
  if(rel>timing_tolerance),error('analysis.time_dependent_fft worker: temporal window is not uniformly sampled (relative deviation %.6g)',rel);endif
  time_center=0.5*(t(1)+t(end));
endif

F=tdfft_compute_frame(x,dt_seconds,nfft,window_name,detrend_mode,representation,numeric_api);
R=F;R.item_id=item_id;R.time_center=time_center;R.row_start=row_start;R.row_count=row_count;
save('-binary',result_path,'R');
fprintf('GX-TXT time-dependent FFT worker completed: %s\n',item_id);
