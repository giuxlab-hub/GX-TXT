% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT Temporal Set API v1 standard_octave runtime reader.
%
% S = gxtxt_temporal_set_from_runtime(runtime_cfg, key)
%
% Regular Temporal Window Sets remain compact: S stores the generator and the
% resolved row-domain parameters, not one struct per generated window. Use
% gxtxt_temporal_set_member(S,index) to reconstruct a deterministic member.
function S = gxtxt_temporal_set_from_runtime(runtime_cfg, key)
  if (nargin < 2 || isempty(key)), key = 'temporal_set'; endif
  if (ischar(runtime_cfg) || isstring(runtime_cfg))
    cfg = gxtxt_ini_read(char(runtime_cfg));
  elseif (isstruct(runtime_cfg))
    cfg = runtime_cfg;
  else
    error('GXTXT:TemporalSet','runtime_cfg must be a parsed runtime struct or runtime.ini path');
  endif
  p = ['temporal_set.' char(key) '.'];
  S = struct();
  S.api_version = parse_integer_local(gxtxt_ini_get(cfg,[p 'api_version'],'1'),'api_version',0);
  S.id = strtrim(gxtxt_ini_get(cfg,[p 'id'],''));
  S.enabled = parse_bool_local(gxtxt_ini_get(cfg,[p 'enabled'],'0'));
  S.type = lower(strtrim(gxtxt_ini_get(cfg,[p 'type'],'')));
  S.source_dataset_id = strtrim(gxtxt_ini_get(cfg,[p 'source_dataset_id'],''));
  S.temporal_variable_id = strtrim(gxtxt_ini_get(cfg,[p 'temporal_variable_id'],''));
  S.temporal_variable = strtrim(gxtxt_ini_get(cfg,[p 'temporal_variable'],''));
  S.temporal_unit = strtrim(gxtxt_ini_get(cfg,[p 'temporal_unit'],''));
  S.parent_selection_id = strtrim(gxtxt_ini_get(cfg,[p 'parent_selection_id'],''));
  S.boundary_policy = strtrim(gxtxt_ini_get(cfg,[p 'boundary_policy'],''));
  S.axis_kind = lower(strtrim(gxtxt_ini_get(cfg,[p 'axis_kind'],'')));
  S.axis_origin = parse_optional_num_local(gxtxt_ini_get(cfg,[p 'axis_origin'],''));
  S.axis_step = parse_optional_num_local(gxtxt_ini_get(cfg,[p 'axis_step'],''));
  S.axis_count = parse_integer_local(gxtxt_ini_get(cfg,[p 'axis_count'],'0'),'axis_count',0);
  S.effective_row_start = parse_integer_local(gxtxt_ini_get(cfg,[p 'effective_row_start'],'0'),'effective_row_start',0);
  S.effective_row_count = parse_integer_local(gxtxt_ini_get(cfg,[p 'effective_row_count'],'0'),'effective_row_count',0);
  S.member_count = parse_integer_local(gxtxt_ini_get(cfg,[p 'member_count'],'0'),'member_count',0);
  S.generator_basis = lower(strtrim(gxtxt_ini_get(cfg,[p 'generator_basis'],'')));
  S.window_size = parse_optional_num_local(gxtxt_ini_get(cfg,[p 'window_size'],''));
  S.step = parse_optional_num_local(gxtxt_ini_get(cfg,[p 'step'],''));
  S.duration_unit = strtrim(gxtxt_ini_get(cfg,[p 'duration_unit'],''));
  S.partial_policy = lower(strtrim(gxtxt_ini_get(cfg,[p 'partial_policy'],'drop')));
  % CORE writes these window-only fields empty for segment sets. Normalize that
  % valid absence to zero; enabled window sets are still required to be positive.
  S.resolved_window_rows = parse_optional_integer_local(gxtxt_ini_get(cfg,[p 'resolved_window_rows'],'0'),'resolved_window_rows',0,0);
  S.resolved_step_rows = parse_optional_integer_local(gxtxt_ini_get(cfg,[p 'resolved_step_rows'],'0'),'resolved_step_rows',0,0);
  S.members = struct('index',{},'member_id',{},'label',{},'requested_time_start',{},'requested_time_end',{},'time_start',{},'time_end',{},'row_start',{},'row_count',{});

  if (!S.enabled), return; endif
  if (isempty(S.id) || !any(strcmp(S.type,{'segment_set','window_set'})))
    error('GXTXT:TemporalSet','Incomplete or unsupported Temporal Set runtime section: %s',key);
  endif
  if (isempty(S.source_dataset_id) || isempty(S.temporal_variable_id))
    error('GXTXT:TemporalSet','Temporal Set runtime is missing Dataset or temporal-variable identity: %s',key);
  endif
  if (!strcmp(S.boundary_policy,'start_inclusive_end_exclusive'))
    error('GXTXT:TemporalSet','Unsupported Temporal Set boundary policy: %s',S.boundary_policy);
  endif

  if (strcmp(S.type,'segment_set'))
    members = S.members;
    for i = 1:S.member_count
      q = sprintf('%smember.%d.',p,i);
      M = struct();
      M.index = parse_integer_local(gxtxt_ini_get(cfg,[q 'index'],num2str(i)),'member.index',1);
      M.member_id = strtrim(gxtxt_ini_get(cfg,[q 'member_id'],''));
      M.label = gxtxt_ini_get(cfg,[q 'label'],'');
      M.requested_time_start = parse_required_num_local(gxtxt_ini_get(cfg,[q 'requested_time_start'],''),'requested_time_start');
      M.requested_time_end = parse_required_num_local(gxtxt_ini_get(cfg,[q 'requested_time_end'],''),'requested_time_end');
      M.time_start = parse_required_num_local(gxtxt_ini_get(cfg,[q 'time_start'],''),'time_start');
      M.time_end = parse_required_num_local(gxtxt_ini_get(cfg,[q 'time_end'],''),'time_end');
      M.row_start = parse_integer_local(gxtxt_ini_get(cfg,[q 'row_start'],''),'row_start',0);
      M.row_count = parse_integer_local(gxtxt_ini_get(cfg,[q 'row_count'],''),'row_count',0);
      if (isempty(M.member_id)), error('GXTXT:TemporalSet','Temporal Segment member %d has no stable member_id',i); endif
      members(end+1) = M;
    endfor
    S.members = members;
  else
    if (!any(strcmp(S.generator_basis,{'samples','duration'})) || S.resolved_window_rows < 1 || S.resolved_step_rows < 1)
      error('GXTXT:TemporalSet','Temporal Window Set runtime has invalid resolved generator parameters: %s',key);
    endif
    if (!any(strcmp(S.partial_policy,{'drop','include'})))
      error('GXTXT:TemporalSet','Unsupported partial-window policy: %s',S.partial_policy);
    endif
  endif
endfunction

function value = parse_optional_num_local(raw)
  if (isempty(strtrim(raw))), value = NaN; else value = parse_required_num_local(raw,'numeric field'); endif
endfunction

function value = parse_required_num_local(raw,name)
  value = str2double(strtrim(raw));
  if (!isfinite(value)), error('GXTXT:TemporalSet','Invalid %s value: %s',name,raw); endif
endfunction

function value = parse_integer_local(raw,name,min_value)
  value = str2double(strtrim(raw));
  if (!isfinite(value) || value != fix(value) || value < min_value)
    error('GXTXT:TemporalSet','Invalid %s integer: %s',name,raw);
  endif
endfunction

function value = parse_optional_integer_local(raw,name,min_value,default_value)
  if (isempty(strtrim(raw)))
    value = default_value;
  else
    value = parse_integer_local(raw,name,min_value);
  endif
endfunction

function value = parse_bool_local(raw)
  value = any(strcmp(lower(strtrim(raw)),{'1','true','yes','on'}));
endfunction
