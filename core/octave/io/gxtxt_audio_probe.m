function text=gxtxt_audio_probe(path,stream_index,options)
  if(nargin<2),stream_index='';endif
  if(nargin<3),options=struct();endif
  if(isstruct(stream_index))
    options=stream_index;
    stream_index=field_or(options,'stream_index','');
  endif
  input_format=field_or(options,'input_format','');
  sample_rate=field_or(options,'sample_rate','');
  channels=field_or(options,'channels','');
  here=fileparts(mfilename('fullpath'));
  root=fileparts(fileparts(fileparts(here)));
  bridge=fullfile(root,'core','tcl','audio_probe_v1_bridge.tcl');
  args={bridge,path,arg_text(stream_index),char(input_format),arg_text(sample_rate),arg_text(channels)};
  [in,out,pid]=popen2('tclsh',args);
  try fclose(in);catch;end_try_catch
  parts=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(out,pid,'Audio Probe'));
  try fclose(out);catch;end_try_catch
  try waitpid(pid);catch;end_try_catch
  if(strcmp(parts{1},'ERROR')),error('GXTXT:AudioDecode','%s',gxtxt_table_stream_v3_decode(parts{2}));endif
  text=gxtxt_table_stream_v3_decode(parts{2});
endfunction

function value=field_or(source,name,default)
  if(isfield(source,name)),value=source.(name);else value=default;endif
endfunction

function text=arg_text(value)
  if(ischar(value)),text=value;else text=num2str(value);endif
endfunction
