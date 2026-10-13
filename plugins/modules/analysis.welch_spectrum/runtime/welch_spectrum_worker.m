% GX-TXT Welch batch process worker.
% One worker item processes a deterministic batch of Temporal Set windows.
% SPDX-License-Identifier: GPL-3.0-or-later
args=argv();runtime_path='';batch_id='';signal_id='';manifest_path='';result_path='';nfft=NaN;dt_seconds=NaN;window_name='hann';detrend_mode='mean';
for ai=1:2:(numel(args)-1)
  k=args{ai};v=args{ai+1};switch k
    case '--runtime',runtime_path=v;case '--batch-id',batch_id=v;case '--signal-id',signal_id=v;case '--manifest',manifest_path=v;case '--nfft',nfft=str2double(v);case '--dt-seconds',dt_seconds=str2double(v);case '--window',window_name=v;case '--detrend',detrend_mode=v;case '--result',result_path=v;
  endswitch
endfor
if(isempty(runtime_path)||isempty(batch_id)||isempty(signal_id)||isempty(manifest_path)||isempty(result_path)),error('analysis.welch_spectrum worker: incomplete argv');endif
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);addpath(runtime_dir);for d={'analysis','cache','graphics','io','units','util'},addpath(fullfile(package_root,'core','octave',d{1}));endfor
thread_hint=str2double(strtrim(getenv('GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS')));if(isfinite(thread_hint)&&thread_hint>=1),try if(exist('fftw','builtin')||exist('fftw','file')),fftw('threads',max(1,round(thread_hint)));endif;catch;end_try_catch;endif
cfg=gxtxt_ini_read(runtime_path);numeric_fn=welch_numeric_api(cfg);fid=fopen(manifest_path,'r');if(fid<0),error('analysis.welch_spectrum worker: cannot open batch manifest');endif
rows={};unwind_protect
  while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)),continue;endif;p=strsplit(line,char(9));if(numel(p)!=3),error('analysis.welch_spectrum worker: malformed batch manifest');endif;rows{end+1}=struct('id',p{1},'start',str2double(p{2}),'count',str2double(p{3}));endwhile
unwind_protect_cleanup
  fclose(fid);
end_unwind_protect
if(isempty(rows)),error('analysis.welch_spectrum worker: empty batch');endif
sum_psd=[];sum_amp=[];count=0;sample_total=0;enbw_sum=0;
for ri=1:numel(rows)
  q=rows{ri};S=gxtxt_table_stream_open_source(cfg,'primary',{signal_id},65536,struct('start',q.start,'count',q.count,'require_direct',false,'numeric_transport','auto'));parts={};nr=0;
  unwind_protect
    while(true),[S,C]=gxtxt_table_stream_v3_next(S);if(C.nrows>0),v=gxtxt_table_chunk_numeric(C,signal_id);parts{end+1}=double(v(:));nr+=C.nrows;endif;if(C.eof),break;endif;endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(nr!=q.count),error('analysis.welch_spectrum worker: range %s returned %d rows; expected %d',q.id,nr,q.count);endif
  x=vertcat(parts{:});R=welch_compute_segment(x,dt_seconds,nfft,window_name,detrend_mode,numeric_fn);
  if(isempty(sum_psd)),sum_psd=zeros(size(R.psd));sum_amp=zeros(size(R.amplitude));endif
  if(numel(R.psd)!=numel(sum_psd)),error('analysis.welch_spectrum worker: inconsistent spectral grid');endif
  sum_psd+=R.psd;sum_amp+=R.amplitude;count+=1;sample_total+=R.sample_count;enbw_sum+=R.enbw_hz;
endfor
B=struct('batch_id',batch_id,'window_count',count,'sample_total',sample_total,'sum_psd',sum_psd,'sum_amplitude',sum_amp,'enbw_sum_hz',enbw_sum,'nfft',nfft,'bin_count',numel(sum_psd));save('-binary',result_path,'B');
