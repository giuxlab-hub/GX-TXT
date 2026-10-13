function analysis_audio_decode_main(args)
% Decode an audio.waveform source through GX-TXT Audio Decode API v1 and
% publish a canonical large waveform dataset through Dataset Publication API v2.
% SPDX-License-Identifier: GPL-3.0-or-later

  module_id='analysis.audio_decode';
  module_version='2.0.1';
  decode_chunk_frames=65536;

  config_path=arg_value(args,'--config','');
  if(isempty(config_path)), error('%s: --config is required',module_id); endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)), error('%s: runtime.output_dir missing',module_id); endif
  if(isempty(session)), error('%s: runtime.session missing (Publication API v2 requires the current session path)',module_id); endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif

  A=struct(); P=struct(); audio_open=false; publication_open=false; publication_finalized=false;
  gxtxt_progress_start('prepare','Preparing audio decode','indeterminate');

  try
    % ---- resolve source -------------------------------------------------
    src=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));
    if(isempty(src)), src=strtrim(gxtxt_ini_get(cfg,'dataset.path','')); endif
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)), source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id','')); endif
    source_contract=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.contract',''));
    if(isempty(source_contract)), source_contract=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.kind','')); endif
    if(isempty(src) || exist(src,'file')!=2)
      error('%s: source audio file is missing: %s',module_id,src);
    endif
    if(isempty(source_dataset_id)), error('%s: primary source Dataset ID is missing',module_id); endif
    if(!isempty(source_contract) && !strcmp(source_contract,'audio.waveform'))
      error('%s: expected source contract audio.waveform, got %s',module_id,source_contract);
    endif

    amp_scale_raw=strtrim(gxtxt_ini_get(cfg,'config.amplitude_scale','1'));
    amp_scale=str2double(amp_scale_raw);
    if(!isfinite(amp_scale) || amp_scale==0)
      error('%s: invalid amplitude_scale "%s" (must be a nonzero finite number)',module_id,amp_scale_raw);
    endif
    amp_unit=strtrim(gxtxt_ini_get(cfg,'config.amplitude_unit','FS'));
    if(isempty(amp_unit)), amp_unit='FS'; endif

    % ---- CORE probe and decode policy ----------------------------------
    % Probe is a public Audio Decode API v1 operation. The module uses source
    % metadata only to choose the CORE transport format needed to preserve the
    % historical normalized-full-scale scientific meaning.
    probe_text=gxtxt_audio_probe(src);
    source_codec=tcl_dict_value_local(probe_text,'codec_name','unknown');
    source_sample_fmt=tcl_dict_value_local(probe_text,'sample_fmt','');
    source_bits=tcl_dict_value_local(probe_text,'bits_per_raw_sample','');
    if(isempty(source_bits) || strcmp(source_bits,'0'))
      source_bits=tcl_dict_value_local(probe_text,'bits_per_sample','');
    endif
    source_container=tcl_dict_value_local(probe_text,'container_format','');
    source_duration=tcl_dict_value_local(probe_text,'duration','');
    selected_stream=tcl_dict_value_local(probe_text,'selected_stream_index','0');
    ffmpeg_version=tcl_dict_value_local(probe_text,'ffmpeg_version','');
    ffprobe_version=tcl_dict_value_local(probe_text,'ffprobe_version','');

    decode_format=decode_format_local(source_codec,source_sample_fmt);
    dec_opts=struct('sample_format',decode_format,'chunk_frames',decode_chunk_frames, ...
                    'stream_index',str2double(selected_stream));

    gxtxt_progress_stage('decode','Opening CORE Audio Decode API v1','indeterminate');
    A=gxtxt_audio_decode_open(src,dec_opts); audio_open=true;
    fs=A.sample_rate; nch=A.channels;
    if(!isfinite(fs) || fs<=0), error('%s: decoder returned invalid sample rate',module_id); endif
    if(!isfinite(nch) || nch<1 || round(nch)!=nch), error('%s: decoder returned invalid channel count',module_id); endif
    nch=round(nch);

    % ---- Publication v2 / Storage Auto ---------------------------------
    pub_id=[source_dataset_id '.decoded'];
    required={'append_write','typed_numeric','implicit_axis'};
    preferred={'range_write','sequential_chunks'};
    popts=struct('storage','auto','capabilities_required',{required}, ...
                 'capabilities_preferred',{preferred},'replace_owned',true);

    gxtxt_progress_stage('publish','Opening Dataset Publication API v2 writer','indeterminate');
    P=gxtxt_publication_v2_open(session,module_id,pub_id,'timeseries.table',popts);
    publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'sample',0,true);
    P=gxtxt_publication_v2_declare_uniform(P,'time','sample',0,1/fs, ...
      struct('name','time_s','unit','s','dtype','float64','semantic_role','independent'));
    for c=1:nch
      vid=sprintf('channel_%d',c);
      vname=sprintf('ch%d',c);
      spec=struct('dtype','float64','dimension_ids','sample','name',vname, ...
                  'unit',amp_unit,'semantic_role','measured', ...
                  'coordinate_variable_ids','time','chunks',decode_chunk_frames);
      P=gxtxt_publication_v2_declare_variable(P,vid,spec);
    endfor

    % ---- bounded decode -> bounded publication -------------------------
    total_frames=0; chunks=0; max_chunk_frames=0;
    expected_frames=expected_frames_local(source_duration,fs);
    if(expected_frames>0)
      gxtxt_progress_stage('decode','Decoding and publishing audio chunks','determinate',expected_frames);
    else
      gxtxt_progress_stage('decode','Decoding and publishing audio chunks','indeterminate');
    endif

    while(!A.eof)
      [A,C]=gxtxt_audio_decode_next(A);
      if(C.frames>0)
        samples=scientific_samples_local(C.values,decode_format,amp_scale);
        if(rows(samples)!=C.frames || columns(samples)!=nch)
          error('%s: decoder chunk shape mismatch',module_id);
        endif
        items=cell(nch,2);
        for c=1:nch
          items{c,1}=sprintf('channel_%d',c);
          items{c,2}=samples(:,c);
        endfor
        P=gxtxt_publication_v2_append(P,'sample',items);
        total_frames+=C.frames; chunks+=1; max_chunk_frames=max(max_chunk_frames,C.frames);
        if(expected_frames>0)
          gxtxt_progress_update(min(total_frames,expected_frames),expected_frames,'decode', ...
            sprintf('Decoded %d frames in %d chunk(s)',total_frames,chunks));
        elseif(mod(chunks,8)==0)
          gxtxt_progress_stage('decode',sprintf('Decoded %d frames in %d chunk(s)',total_frames,chunks),'indeterminate');
        endif
      endif
    endwhile
    if(total_frames<1), error('%s: decoder produced zero audio frames',module_id); endif

    [A,audio_diag]=gxtxt_audio_decode_diagnostics(A);
    A=gxtxt_audio_decode_close(A); audio_open=false;
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);

    gxtxt_progress_stage('finalize','Finalizing canonical waveform dataset','indeterminate');
    [P,pub_result]=gxtxt_publication_v2_finalize(P);
    publication_finalized=true; publication_open=false;

    % Human-readable run report. Scientific identity and storage remain owned
    % by the canonical dataset registry and Publication v2.
    try
      write_info_local(fullfile(outdir,'decode_info.txt'),module_id,module_version,src,source_dataset_id,pub_id, ...
        source_container,source_codec,source_sample_fmt,source_bits,selected_stream,fs,nch,total_frames, ...
        decode_format,amp_unit,amp_scale,decode_chunk_frames,max_chunk_frames,chunks,P.provider, ...
        required,preferred,audio_diag,pub_diag,pub_result,ffmpeg_version,ffprobe_version);
    catch info_err
      fprintf(2,'[%s] warning: could not write decode_info.txt: %s\n',module_id,info_err.message);
    end_try_catch

    gxtxt_progress_complete('done',sprintf('Published %s (%d frames, %d channel(s))',pub_id,total_frames,nch));
    fprintf('[%s] version=%s source=%s published=%s frames=%d channels=%d fs=%.17g provider=%s\n', ...
            module_id,module_version,source_dataset_id,pub_id,total_frames,nch,fs,P.provider);
  catch err
    if(audio_open)
      try A=gxtxt_audio_decode_close(A); catch; end_try_catch
    endif
    if(publication_open && !publication_finalized)
      try P=gxtxt_publication_v2_abort(P); catch; end_try_catch
    endif
    try gxtxt_progress_fail('failed','Audio decode failed; see log for details'); catch; end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function fmt=decode_format_local(codec,sample_fmt)
  c=lower(strtrim(codec)); s=lower(strtrim(sample_fmt));
  source_float=!isempty(regexp(c,'^pcm_f','once')) || any(strcmp(s,{'flt','fltp','dbl','dblp'}));
  if(source_float), fmt='float32'; else fmt='int32'; endif
endfunction

function out=scientific_samples_local(values,decode_format,amp_scale)
  if(strcmp(decode_format,'int32'))
    out=double(values) / 2147483648.0;
  elseif(strcmp(decode_format,'float32'))
    out=double(values);
  else
    error('analysis.audio_decode: unsupported internal decode format %s',decode_format);
  endif
  if(amp_scale!=1), out*=amp_scale; endif
endfunction

function n=expected_frames_local(duration_text,fs)
  n=0; d=str2double(strtrim(duration_text));
  if(isfinite(d) && d>0 && isfinite(fs) && fs>0), n=max(1,round(d*fs)); endif
endfunction

function value=tcl_dict_value_local(text,key,def)
% Extract selected scalar fields from the public gxtxt_audio_probe Tcl-dict
% serialization. Values needed here are scalar tokens or one brace-quoted word
% sequence; nested fields are deliberately not interpreted by this module.
  value=def;
  pat=['(?:^|[[:space:]])' key '[[:space:]]+({[^}]*}|[^[:space:]]+)'];
  tok=regexp(text,pat,'tokens','once');
  if(isempty(tok)), return; endif
  value=tok{1};
  if(numel(value)>=2 && value(1)=='{' && value(end)=='}'), value=value(2:end-1); endif
endfunction

function write_info_local(path,module_id,module_version,src,source_dataset_id,pub_id,container,codec,sample_fmt,bits,stream,fs,nch,N,decode_format,amp_unit,amp_scale,chunk_frames,max_chunk,chunks,provider,required,preferred,audio_diag,pub_diag,pub_result,ffmpeg_version,ffprobe_version)
  fid=fopen(path,'w'); if(fid<0), error('cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'GX-TXT Audio decode\n');
    fprintf(fid,'module_id=%s\n',module_id);
    fprintf(fid,'module_version=%s\n',module_version);
    fprintf(fid,'source_dataset_id=%s\n',source_dataset_id);
    fprintf(fid,'output_dataset_id=%s\n',pub_id);
    fprintf(fid,'source_file=%s\n',src);
    fprintf(fid,'source_container=%s\n',container);
    fprintf(fid,'source_codec=%s\n',codec);
    fprintf(fid,'source_sample_format=%s\n',sample_fmt);
    fprintf(fid,'source_bit_depth=%s\n',bits);
    fprintf(fid,'selected_audio_stream=%s\n',stream);
    fprintf(fid,'sample_rate_hz=%.17g\n',fs);
    fprintf(fid,'channels=%d\n',nch);
    fprintf(fid,'sample_count=%d\n',N);
    fprintf(fid,'duration_s=%.17g\n',N/fs);
    fprintf(fid,'audio_decode_api=1\n');
    fprintf(fid,'requested_decode_format=%s\n',decode_format);
    fprintf(fid,'module_output_dtype=float64\n');
    fprintf(fid,'amplitude_unit=%s\n',amp_unit);
    fprintf(fid,'amplitude_scale=%.17g\n',amp_scale);
    fprintf(fid,'time_axis=implicit_uniform\n');
    fprintf(fid,'time_origin_s=0\n');
    fprintf(fid,'time_step_s=%.17g\n',1/fs);
    fprintf(fid,'explicit_time_samples_stored=no\n');
    fprintf(fid,'decode_chunk_frames=%d\n',chunk_frames);
    fprintf(fid,'maximum_decoded_chunk_frames=%d\n',max_chunk);
    fprintf(fid,'chunks=%d\n',chunks);
    fprintf(fid,'publication_api=2\n');
    fprintf(fid,'storage_request=auto\n');
    fprintf(fid,'capabilities_required=%s\n',strjoin(required,';'));
    fprintf(fid,'capabilities_preferred=%s\n',strjoin(preferred,';'));
    fprintf(fid,'effective_storage_provider=%s\n',provider);
    fprintf(fid,'audio_diagnostics=%s\n',audio_diag);
    fprintf(fid,'publication_diagnostics=%s\n',pub_diag);
    fprintf(fid,'publication_result=%s\n',pub_result);
    fprintf(fid,'ffmpeg_version=%s\n',ffmpeg_version);
    fprintf(fid,'ffprobe_version=%s\n',ffprobe_version);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function v=arg_value(args,key,def)
  v=def;
  for i=1:numel(args)-1
    if(strcmp(args{i},key)), v=args{i+1}; return; endif
  endfor
endfunction
