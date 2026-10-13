function emitted = gxtxt_progress(action, varargin)
% GX-TXT Plugin Progress API v1 - low-level Octave helper.
% Plugins should normally call gxtxt_progress_start/stage/update/complete/fail.
% Transport is enabled by the framework through GXTXT_PROGRESS_ENABLED=1.

  persistent last_emit_time = -Inf;
  persistent last_percent = -Inf;
  persistent last_stage = '';
  persistent active = false;

  emitted = false;
  if (!strcmp(getenv('GXTXT_PROGRESS_ENABLED'),'1'))
    return;
  endif

  action = lower(strtrim(action));
  stage = ''; message = ''; mode = 'indeterminate'; current = ''; total = '';
  force = false;

  switch (action)
    case 'start'
      stage = arg_or(varargin,1,''); message = arg_or(varargin,2,'');
      mode = normalize_mode(arg_or(varargin,3,'indeterminate'));
      total = arg_or(varargin,4,''); current = 0;
      active = true; last_emit_time = -Inf; last_percent = -Inf; last_stage = stage; force = true;
      state = 'start';
    case 'stage'
      stage = arg_or(varargin,1,last_stage); message = arg_or(varargin,2,'');
      mode = normalize_mode(arg_or(varargin,3,'indeterminate'));
      total = arg_or(varargin,4,''); current = 0;
      active = true; last_stage = stage; force = true;
      state = 'running';
    case 'update'
      current = arg_or(varargin,1,''); total = arg_or(varargin,2,'');
      stage = arg_or(varargin,3,last_stage); message = arg_or(varargin,4,'');
      mode = 'determinate'; state = 'running'; active = true;
    case 'complete'
      stage = arg_or(varargin,1,last_stage); message = arg_or(varargin,2,'');
      mode = 'determinate'; current = 1; total = 1; state = 'completed'; force = true; active = false;
    case 'fail'
      stage = arg_or(varargin,1,last_stage); message = arg_or(varargin,2,'');
      mode = 'indeterminate'; state = 'failed'; force = true; active = false;
    otherwise
      error('gxtxt_progress: unknown action: %s', action);
  endswitch

  now_s = time();
  if (strcmp(action,'update'))
    c = scalar_number(current); t = scalar_number(total);
    if (!isfinite(c) || !isfinite(t) || t <= 0)
      mode = 'indeterminate';
      pct = NaN;
    else
      pct = 100 * min(max(c,0),t) / t;
    endif
    significant = isfinite(pct) && (!isfinite(last_percent) || abs(pct-last_percent) >= 1.0 || c >= t);
    timed = (now_s - last_emit_time) >= 0.25;
    stage_changed = !strcmp(stage,last_stage);
    if (!(significant || timed || stage_changed)), return; endif
    if (isfinite(pct)), last_percent = pct; endif
  endif

  if (!force && !active && !strcmp(state,'running')), return; endif
  emit_record(state,mode,stage,message,current,total);
  last_emit_time = now_s;
  last_stage = stage;
  emitted = true;
endfunction

function v = arg_or(args, idx, def)
  if (numel(args) >= idx), v = args{idx}; else v = def; endif
endfunction

function m = normalize_mode(v)
  m = lower(strtrim(to_text(v)));
  if (!any(strcmp(m,{'determinate','indeterminate'}))), m='indeterminate'; endif
endfunction

function n = scalar_number(v)
  if (isnumeric(v) && isscalar(v)), n=double(v);
  elseif (ischar(v)), n=str2double(v);
  else n=NaN; endif
endfunction

function emit_record(state,mode,stage,message,current,total)
  fields = {
    'state', state;
    'mode', mode;
    'stage', stage;
    'message', message;
    'current', current;
    'total', total;
    'module_id', getenv('GXTXT_PROGRESS_MODULE_ID');
    'run_id', getenv('GXTXT_PROGRESS_RUN_ID')
  };
  parts = cell(1,rows(fields));
  for i=1:rows(fields)
    parts{i} = [fields{i,1} '=' escape_value(to_text(fields{i,2}))];
  endfor
  fprintf('@@GXTXT_PROGRESS_V1@@\t%s\n', strjoin(parts, sprintf('\t')));
  fflush(stdout);
endfunction

function s = to_text(v)
  if (ischar(v)), s=v;
  elseif (isnumeric(v) && isscalar(v)), s=sprintf('%.17g',v);
  elseif (islogical(v) && isscalar(v)), s=sprintf('%d',v);
  else s=''; endif
endfunction

function s = escape_value(s)
  s = strrep(s,'\','\\');
  s = strrep(s,sprintf('\t'),'\t');
  s = strrep(s,sprintf('\n'),'\n');
  s = strrep(s,sprintf('\r'),'\r');
endfunction
