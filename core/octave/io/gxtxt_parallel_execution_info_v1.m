function info = gxtxt_parallel_execution_info_v1()
% Discover the active CORE Parallel Execution API v1 standard_octave binding.
  client = client_path_local();
  [in,out,pid]=popen2('tclsh',{client});
  if(pid<0),error('GXTXT:ParallelExecution','Cannot start Parallel Execution transport client');endif
  unwind_protect
    p=gxtxt_table_stream_v3_parts(gxtxt_persistent_bridge_readline(out,pid,'Parallel Execution'));
    if(numel(p)>=2&&strcmp(p{1},'ERROR')),error('GXTXT:ParallelExecution','%s',gxtxt_table_stream_v3_decode(p{2}));endif
    if(numel(p)!=8||!strcmp(p{1},'READY')),error('GXTXT:ParallelExecution','Invalid Parallel Execution binding discovery response');endif
    info=struct('api_name','Parallel Execution API','api_version',str2double(p{2}), ...
      'standard_octave_binding',true,'enabled',logical(str2double(p{3})), ...
      'default_workers',str2double(p{4}),'max_workers',str2double(p{5}), ...
      'recommended_internal_threads',str2double(p{6}), ...
      'nested_policy',gxtxt_table_stream_v3_decode(p{7}), ...
      'analysis_run_id',gxtxt_table_stream_v3_decode(p{8}),'result_order','input');
  unwind_protect_cleanup
    try fclose(in);catch;end_try_catch
    try fclose(out);catch;end_try_catch
    try waitpid(pid);catch;end_try_catch
  end_unwind_protect
endfunction
function client=client_path_local()
  here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(here)));
  client=fullfile(root,'core','tcl','parallel_execution_octave_client_v1.tcl');
  if(exist(client,'file')!=2),error('GXTXT:ParallelExecution','Parallel Execution standard_octave transport client is missing');endif
endfunction
