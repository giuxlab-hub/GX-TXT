function result = gxtxt_parallel_execute_v1(items, options)
% GX-TXT Parallel Execution API v1 binding for standard_octave.
% Execute independent stable-ID process work items through the active CORE
% Parallel Execution coordinator.
%
% items: struct array or cell array of structs with fields
%   id    required stable caller-supplied identifier
%   argv  required cell array: executable followed by arguments
%
% options fields (all optional):
%   workers      'auto' | 'serial' | positive integer
%   fail_fast    scalar boolean
%   run_id       optional caller-supplied Parallel Execution run identity
%   environment  struct or N-by-2 cell array applied to every worker
%
% Results preserve CORE input-order association independently of completion
% order. Worker scheduling, limits, cancellation, nesting and cleanup are CORE
% responsibilities; this helper is only the standard_octave binding.

  if (nargin < 2), options = struct(); endif
  normalized = normalize_items_local(items);
  opt = normalize_options_local(options);
  client = client_path_local();
  [bridge_in, bridge_out, bridge_pid] = popen2('tclsh', {client});
  if (bridge_pid < 0), error('GXTXT:ParallelExecution','Cannot start Parallel Execution transport client'); endif
  closed = false;
  unwind_protect
    ready = parse_ready_local(gxtxt_persistent_bridge_readline(bridge_out, bridge_pid, 'Parallel Execution'));
    write_request_local(bridge_in, normalized, opt);
    fflush(bridge_in);
    result = read_result_local(bridge_out, bridge_pid, ready);
    try fclose(bridge_in); catch; end_try_catch
    try fclose(bridge_out); catch; end_try_catch
    try waitpid(bridge_pid); catch; end_try_catch
    closed = true;
  unwind_protect_cleanup
    if (!closed)
      % Closing the transport causes CORE to cancel any active run owned by this
      % request, so interrupted Octave callers cannot orphan worker processes.
      try fclose(bridge_in); catch; end_try_catch
      try fclose(bridge_out); catch; end_try_catch
      try waitpid(bridge_pid); catch; end_try_catch
    endif
  end_unwind_protect
endfunction

function client = client_path_local()
  here = fileparts(mfilename('fullpath'));
  root = fileparts(fileparts(fileparts(here)));
  client = fullfile(root,'core','tcl','parallel_execution_octave_client_v1.tcl');
  if (exist(client,'file') != 2)
    error('GXTXT:ParallelExecution','Parallel Execution standard_octave transport client is missing');
  endif
endfunction

function ready = parse_ready_local(line)
  p = gxtxt_table_stream_v3_parts(line);
  if (numel(p) >= 2 && strcmp(p{1},'ERROR'))
    error('GXTXT:ParallelExecution','%s',gxtxt_table_stream_v3_decode(p{2}));
  endif
  if (numel(p) != 8 || !strcmp(p{1},'READY'))
    error('GXTXT:ParallelExecution','Invalid Parallel Execution binding READY response');
  endif
  ready = struct( ...
    'api_version', str2double(p{2}), ...
    'enabled', logical(str2double(p{3})), ...
    'default_workers', str2double(p{4}), ...
    'max_workers', str2double(p{5}), ...
    'recommended_internal_threads', str2double(p{6}), ...
    'nested_policy', gxtxt_table_stream_v3_decode(p{7}), ...
    'analysis_run_id', gxtxt_table_stream_v3_decode(p{8}));
endfunction

function items = normalize_items_local(source)
  if (isempty(source)), items = {}; return; endif
  if (isstruct(source))
    items = cell(1,numel(source));
    for i=1:numel(source), items{i}=source(i); endfor
  elseif (iscell(source))
    items = source(:)';
  else
    error('GXTXT:ParallelExecution','items must be a struct array or cell array of structs');
  endif
  seen = {};
  for i = 1:numel(items)
    item = items{i};
    if (!isstruct(item) || !isfield(item,'id') || !isfield(item,'argv'))
      error('GXTXT:ParallelExecution','Work item %d requires id and argv fields',i);
    endif
    id = text_local(item.id,'work-item id');
    if (isempty(strtrim(id))), error('GXTXT:ParallelExecution','Work item %d has an empty id',i); endif
    if (any(strcmp(seen,id))), error('GXTXT:ParallelExecution','Duplicate work-item id: %s',id); endif
    seen{end+1} = id;
    argv = cellstr_list_local(item.argv,'argv');
    if (isempty(argv)), error('GXTXT:ParallelExecution','Work item %s has an empty argv',id); endif
    items{i} = struct('id',id,'argv',{argv});
  endfor
endfunction

function opt = normalize_options_local(source)
  if (!isstruct(source)), error('GXTXT:ParallelExecution','options must be a struct'); endif
  opt = struct();
  opt.workers = field_local(source,'workers','auto');
  if (isnumeric(opt.workers) && isscalar(opt.workers))
    if (!isfinite(opt.workers) || opt.workers < 1 || fix(opt.workers) != opt.workers)
      error('GXTXT:ParallelExecution','workers must be auto, serial, or a positive integer');
    endif
    opt.workers = sprintf('%d',opt.workers);
  else
    opt.workers = lower(strtrim(text_local(opt.workers,'workers')));
    if (!(strcmp(opt.workers,'auto') || strcmp(opt.workers,'serial')))
      n = str2double(opt.workers);
      if (!isfinite(n) || n < 1 || fix(n) != n)
        error('GXTXT:ParallelExecution','workers must be auto, serial, or a positive integer');
      endif
      opt.workers = sprintf('%d',n);
    endif
  endif
  opt.fail_fast = bool_local(field_local(source,'fail_fast',false),'fail_fast');
  opt.run_id = text_local(field_local(source,'run_id',''),'run_id');
  opt.environment = environment_local(field_local(source,'environment',{}));
endfunction

function env = environment_local(value)
  env = cell(0,2);
  if (isempty(value)), return; endif
  if (isstruct(value))
    names = fieldnames(value);
    env = cell(numel(names),2);
    for i=1:numel(names)
      env{i,1}=names{i}; env{i,2}=text_local(value.(names{i}),['environment.' names{i}]);
    endfor
  elseif (iscell(value) && columns(value)==2)
    env = value;
    for i=1:rows(env)
      env{i,1}=text_local(env{i,1},'environment name');
      env{i,2}=text_local(env{i,2},'environment value');
    endfor
  else
    error('GXTXT:ParallelExecution','environment must be a struct or N-by-2 cell array');
  endif
  for i=1:rows(env)
    if (isempty(regexp(env{i,1},'^[A-Za-z_][A-Za-z0-9_]*$','once')))
      error('GXTXT:ParallelExecution','Invalid worker environment variable name: %s',env{i,1});
    endif
  endfor
endfunction

function write_request_local(fid, items, opt)
  fprintf(fid,'BEGIN\t%s\t%d\t%s\t%d\t%d\n', ...
    opt.workers, opt.fail_fast, b64_local(opt.run_id), numel(items), rows(opt.environment));
  write_environment_local(fid,opt.environment);
  for i=1:numel(items)
    item=items{i};
    fprintf(fid,'ITEM\t%s\t%d\n',b64_local(item.id),numel(item.argv));
    for j=1:numel(item.argv)
      fprintf(fid,'ARG\t%s\n',b64_local(item.argv{j}));
    endfor
    fprintf(fid,'ENDITEM\n');
  endfor
  fprintf(fid,'EXEC\n');
endfunction

function write_environment_local(fid, env)
  for i=1:rows(env)
    fprintf(fid,'ENV\t%s\t%s\n',b64_local(env{i,1}),b64_local(env{i,2}));
  endfor
endfunction

function result = read_result_local(fid,pid,ready)
  result = struct();
  result.api_version = ready.api_version;
  result.policy = ready;
  result.results = {};
  result.completion_order = {};
  saw_summary = false;
  expected_results = -1;
  while (true)
    line = parallel_readline_local(fid,pid);
    p = gxtxt_table_stream_v3_parts(line);
    if (isempty(p)), continue; endif
    kind = p{1};
    if (strcmp(kind,'PROGRESS'))
      if (numel(p) != 8), error('GXTXT:ParallelExecution','Invalid PROGRESS record'); endif
      state=decode_local(p{2}); cur=str2double(p{3}); total=str2double(p{4}); msg=decode_local(p{6});
      analysis_run_id=decode_local(p{7}); module_id=decode_local(p{8});
      progress_local(state,cur,total,msg,analysis_run_id,module_id);
    elseif (strcmp(kind,'SUMMARY'))
      if (numel(p) != 15), error('GXTXT:ParallelExecution','Invalid SUMMARY record'); endif
      result.run_id=decode_local(p{2}); result.state=decode_local(p{3}); result.requested_workers=decode_local(p{4});
      result.worker_count=str2double(p{5}); result.total=str2double(p{6}); result.completed=str2double(p{7});
      result.success_count=str2double(p{8}); result.error_count=str2double(p{9}); result.cancelled_count=str2double(p{10});
      result.not_executed_count=str2double(p{11}); result.fallback_reason=decode_local(p{12});
      result.started_at=str2double(p{13}); result.finished_at=str2double(p{14}); expected_results=result.total;
      completion_count=str2double(p{15}); result.completion_order=cell(1,0); result.results=cell(1,0);
      result.expected_completion_count=completion_count; saw_summary=true;
    elseif (strcmp(kind,'COMPLETEID'))
      if (!saw_summary || numel(p)!=2), error('GXTXT:ParallelExecution','Invalid COMPLETEID record'); endif
      result.completion_order{end+1}=decode_local(p{2});
    elseif (strcmp(kind,'ITEMRESULT'))
      if (!saw_summary || numel(p)!=11), error('GXTXT:ParallelExecution','Invalid ITEMRESULT record'); endif
      r=struct(); r.index=str2double(p{2}); r.id=decode_local(p{3}); r.state=decode_local(p{4});
      r.value=decode_local(p{5}); r.stdout=decode_local(p{6}); r.stderr=decode_local(p{7});
      r.error=decode_local(p{8}); r.error_code=decode_local(p{9}); r.reason=decode_local(p{10});
      if (isempty(p{11})), r.exit_status=[]; else r.exit_status=str2double(p{11}); endif
      result.results{end+1}=r;
    elseif (strcmp(kind,'END'))
      if (!saw_summary), error('GXTXT:ParallelExecution','Parallel Execution ended without SUMMARY'); endif
      if (numel(result.results)!=expected_results), error('GXTXT:ParallelExecution','Parallel Execution result count mismatch'); endif
      if (numel(result.completion_order)!=result.expected_completion_count), error('GXTXT:ParallelExecution','Parallel Execution completion-order count mismatch'); endif
      result=rmfield(result,'expected_completion_count');
      return;
    elseif (strcmp(kind,'ERROR'))
      if (numel(p)<2), error('GXTXT:ParallelExecution','Parallel Execution binding failed'); endif
      error('GXTXT:ParallelExecution','%s',decode_local(p{2}));
    else
      error('GXTXT:ParallelExecution','Unknown Parallel Execution binding record: %s',kind);
    endif
  endwhile
endfunction

function line=parallel_readline_local(fid,pid)
% Work items may legitimately run for more than generic bridge timeouts. Wait
% until one complete newline-terminated protocol record arrives or the client
% actually exits. popen2() is nonblocking, so fgets() may return a fragment of
% a large Base64 result record before its LF terminator.
  buffer=''; started=time();
  while (time()-started < 900)
    part=fgets(fid);
    if (ischar(part))
      buffer=[buffer part];
      if (!isempty(part) && double(part(end))==10)
        line=regexprep(buffer,'[\r\n]+$',''); return;
      endif
      fclear(fid); pause(0.005); continue;
    endif
    % Windows Octave may return -1 from waitpid(WNOHANG) while the popen2
    % child is still running. Its pipe is polled until a complete record or
    % the bounded idle timeout instead.
    if (!ispc())
      [done,~,~]=waitpid(pid,WNOHANG());
      if (done==pid || done<0)
        if (!isempty(buffer)), error('GXTXT:ParallelExecution','Parallel Execution transport terminated with an incomplete protocol record'); endif
        error('GXTXT:ParallelExecution','Parallel Execution transport terminated unexpectedly');
      endif
    endif
    fclear(fid); pause(0.005);
  endwhile
  error('GXTXT:ParallelExecution','Parallel Execution transport response timed out');
endfunction

function progress_local(state,current,total,message,analysis_run_id,module_id)
  persistent progress_checked=false;
  if (!progress_checked)
    progress_checked=true;
    if (exist('gxtxt_progress_update','file')!=2)
      here=fileparts(mfilename('fullpath')); root=fileparts(fileparts(fileparts(here)));
      util=fullfile(root,'core','octave','util'); if(exist(util,'dir')==7),addpath(util);endif
    endif
  endif
  if (exist('gxtxt_progress_update','file')!=2), return; endif
  try
    % Existing Progress API v1 reads the module/run identity from the standard
    % runtime environment. The explicit values here are retained by the CORE
    % service and are therefore used only for stage/message reporting.
    if (strcmp(state,'completed'))
      gxtxt_progress_complete('parallel_execution',message);
    elseif (strcmp(state,'failed'))
      gxtxt_progress_fail('parallel_execution',message);
    elseif (strcmp(state,'cancelled'))
      gxtxt_progress_update(current,total,'parallel_execution',message);
    elseif (current==0)
      gxtxt_progress_start('parallel_execution',message,'determinate',total);
    else
      gxtxt_progress_update(current,total,'parallel_execution',message);
    endif
  catch
    % Progress is advisory and must not alter scientific execution.
  end_try_catch
endfunction

function out=b64_local(value)
  out=char(matlab.net.base64encode(uint8(char(text_local(value,'text'))))); out=out(:)';
endfunction

function out=decode_local(value)
  if (isempty(value)), out=''; return; endif
  out=char(matlab.net.base64decode(value)); out=out(:)';
endfunction

function out=cellstr_list_local(value,label)
  if (ischar(value)), out={value};
  elseif (iscell(value)), out=cell(1,numel(value)); for i=1:numel(value),out{i}=text_local(value{i},label);endfor
  elseif (isstring(value)), out=cellstr(value(:)');
  else error('GXTXT:ParallelExecution','%s must be a string or cell array of strings',label); endif
endfunction

function out=text_local(value,label)
  if (ischar(value)), out=value;
  elseif (isstring(value) && isscalar(value)), out=char(value);
  elseif ((isnumeric(value)||islogical(value)) && isscalar(value)), out=num2str(value,17);
  else error('GXTXT:ParallelExecution','%s must be scalar text',label); endif
endfunction

function out=bool_local(value,label)
  if ((islogical(value)||isnumeric(value)) && isscalar(value)), out=logical(value);
  elseif (ischar(value) && any(strcmpi(strtrim(value),{'0','1','true','false','yes','no'}))), out=any(strcmpi(strtrim(value),{'1','true','yes'}));
  else error('GXTXT:ParallelExecution','%s must be a scalar boolean',label); endif
endfunction

function value=field_local(source,name,default)
  if (isfield(source,name)), value=source.(name); else value=default; endif
endfunction
