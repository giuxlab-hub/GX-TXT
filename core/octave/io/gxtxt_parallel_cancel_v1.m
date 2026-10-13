function changed = gxtxt_parallel_cancel_v1(run_id)
% Request cancellation of an active CORE Parallel Execution API v1 run.
% A caller that needs external cancellation should supply options.run_id to
% gxtxt_parallel_execute_v1 and pass that same stable run ID here.
  if(nargin!=1),error('GXTXT:ParallelExecution','gxtxt_parallel_cancel_v1 requires run_id');endif
  run_id=text_local(run_id);
  client=client_path_local();
  [in,out,pid]=popen2('tclsh',{client});
  if(pid<0),error('GXTXT:ParallelExecution','Cannot start Parallel Execution transport client');endif
  unwind_protect
    ready=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(out,pid,'Parallel Execution'));
    if(numel(ready)>=2&&strcmp(ready{1},'ERROR')),error('GXTXT:ParallelExecution','%s',gxtxt_table_stream_v3_decode(ready{2}));endif
    if(numel(ready)!=8||!strcmp(ready{1},'READY')),error('GXTXT:ParallelExecution','Invalid Parallel Execution binding READY response');endif
    encoded=char(matlab.net.base64encode(uint8(char(run_id))));encoded=encoded(:)';
    fprintf(in,'CANCEL\t%s\n',encoded);fflush(in);
    p=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(out,pid,'Parallel Execution cancellation'));
    if(numel(p)>=2&&strcmp(p{1},'ERROR')),error('GXTXT:ParallelExecution','%s',gxtxt_table_stream_v3_decode(p{2}));endif
    if(numel(p)!=3||!strcmp(p{1},'CANCELRESULT')),error('GXTXT:ParallelExecution','Invalid Parallel Execution cancellation response');endif
    changed=logical(str2double(p{3}));
  unwind_protect_cleanup
    try fclose(in);catch;end_try_catch
    try fclose(out);catch;end_try_catch
    try waitpid(pid);catch;end_try_catch
  end_unwind_protect
endfunction
function out=text_local(v)
  if(ischar(v)),out=v;elseif(isstring(v)&&isscalar(v)),out=char(v);else,error('GXTXT:ParallelExecution','run_id must be scalar text');endif
  if(isempty(strtrim(out))),error('GXTXT:ParallelExecution','run_id must not be empty');endif
endfunction
function client=client_path_local()
  here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(here)));
  client=fullfile(root,'core','tcl','parallel_execution_octave_client_v1.tcl');
  if(exist(client,'file')!=2),error('GXTXT:ParallelExecution','Parallel Execution standard_octave transport client is missing');endif
endfunction
