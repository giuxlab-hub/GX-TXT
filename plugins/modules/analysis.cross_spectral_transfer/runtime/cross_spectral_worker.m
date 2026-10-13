% GX-TXT cross-spectral process worker. Script form keeps argv handling explicit.
% SPDX-License-Identifier: GPL-3.0-or-later
args=argv();runtime_path='';item_id='';input_id='';output_id='';result_path='';row_start=NaN;row_count=NaN;nfft=NaN;dt_seconds=NaN;window_name='hann';detrend_mode='mean';
for ai=1:2:(numel(args)-1)
  k=args{ai};v=args{ai+1};switch k
    case '--runtime',runtime_path=v;case '--item-id',item_id=v;case '--input-id',input_id=v;case '--output-id',output_id=v;case '--row-start',row_start=str2double(v);case '--row-count',row_count=str2double(v);case '--nfft',nfft=str2double(v);case '--dt-seconds',dt_seconds=str2double(v);case '--window',window_name=v;case '--detrend',detrend_mode=v;case '--result',result_path=v;
  endswitch
endfor
if(isempty(runtime_path)||isempty(item_id)||isempty(input_id)||isempty(output_id)||isempty(result_path)),error('analysis.cross_spectral_transfer worker: incomplete argv');endif
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);addpath(runtime_dir);for d={'analysis','cache','graphics','io','units','util'},addpath(fullfile(package_root,'core','octave',d{1}));endfor
thread_hint=str2double(strtrim(getenv('GXTXT_PARALLEL_RECOMMENDED_INTERNAL_THREADS')));
if(isfinite(thread_hint)&&thread_hint>=1)
  thread_hint=max(1,round(thread_hint));
  try
    if(exist('fftw','builtin')||exist('fftw','file')),fftw('threads',thread_hint);endif
  catch
  end_try_catch
endif
cfg=gxtxt_ini_read(runtime_path);sec='public_api.NUMERIC_API_v1';if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],'')),'math.numeric')),error('analysis.cross_spectral_transfer worker: runtime NUMERIC_API_v1 provider discovery failed');endif;if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.api_version'],'')),'1')),error('analysis.cross_spectral_transfer worker: unsupported NUMERIC_API_v1 version');endif
numeric_entry=strtrim(gxtxt_ini_get(cfg,[sec '.octave_entrypoint'],''));numeric_function=strtrim(gxtxt_ini_get(cfg,[sec '.octave_function'],''));caps=strsplit(strrep(gxtxt_ini_get(cfg,[sec '.capabilities'],''),',',';'),';');for cap={'fft','frequency_grid','one_sided_transform','detrending','window_generation'},if(!any(strcmp(caps,cap{1}))),error('analysis.cross_spectral_transfer worker: NUMERIC_API_v1 capability missing: %s',cap{1});endif;endfor;if(isempty(numeric_entry)||isempty(numeric_function)||exist(numeric_entry,'file')!=2),error('analysis.cross_spectral_transfer worker: runtime NUMERIC_API_v1 Octave binding missing');endif;addpath(fileparts(numeric_entry));if(exist(numeric_function,'file')!=2),error('analysis.cross_spectral_transfer worker: NUMERIC_API_v1 unavailable');endif
S=gxtxt_table_stream_open_source(cfg,'primary',{input_id,output_id},65536,struct('start',row_start,'count',row_count,'require_direct',false,'numeric_transport','auto'));xc={};yc={};total=0;
unwind_protect
  while(true),[S,C]=gxtxt_table_stream_v3_next(S);if(C.nrows>0),vx=gxtxt_table_chunk_numeric(C,input_id);vy=gxtxt_table_chunk_numeric(C,output_id);xc{end+1}=double(vx(:));yc{end+1}=double(vy(:));total+=C.nrows;endif;if(C.eof),break;endif;endwhile
unwind_protect_cleanup
  S=gxtxt_table_stream_close(S);
end_unwind_protect
if(total!=row_count),error('analysis.cross_spectral_transfer worker: range returned %d rows; expected %d',total,row_count);endif
x=vertcat(xc{:});y=vertcat(yc{:});R=csx_compute_window(x,y,dt_seconds,nfft,window_name,detrend_mode,numeric_function);R.item_id=item_id;save('-binary',result_path,'R');
