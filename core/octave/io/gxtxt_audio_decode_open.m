function A=gxtxt_audio_decode_open(path,options)
  if(nargin<2),options=struct();endif
  format=field_or(options,'sample_format','float32');
  frames=field_or(options,'chunk_frames',4096);
  stream=field_or(options,'stream_index','');
  input_format=field_or(options,'input_format','');
  sample_rate=field_or(options,'sample_rate','');
  channels=field_or(options,'channels','');
  here=fileparts(mfilename('fullpath'));
  root=fileparts(fileparts(fileparts(here)));
  bridge=fullfile(root,'core','tcl','audio_decode_v1_bridge.tcl');
  args={bridge,path,char(format),arg_text(frames),arg_text(stream),char(input_format),arg_text(sample_rate),arg_text(channels)};
  [in,out,pid]=popen2('tclsh',args);
  parts=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(out,pid,'Audio Decode'));
  if(strcmp(parts{1},'ERROR')),error('GXTXT:AudioDecode','%s',gxtxt_table_stream_v3_decode(parts{2}));endif
  hints=struct('input_format',char(input_format),'sample_rate',sample_rate,'channels',channels);
  A=struct('api_version',1,'bridge_in',in,'bridge_out',out,'bridge_pid',pid,'core_pid',str2double(parts{2}),'stream_index',str2double(parts{3}),'sample_rate',str2double(parts{4}),'channels',str2double(parts{5}),'codec',gxtxt_table_stream_v3_decode(parts{6}),'channel_layout',gxtxt_table_stream_v3_decode(parts{7}),'sample_format',gxtxt_table_stream_v3_decode(parts{8}),'input_hints',hints,'closed',false,'eof',false);
endfunction

function value=field_or(source,name,default)
  if(isfield(source,name)),value=source.(name);else value=default;endif
endfunction

function text=arg_text(value)
  if(ischar(value)),text=value;else text=num2str(value);endif
endfunction
