% SPDX-License-Identifier: GPL-3.0-or-later
% Resolve one 1-based member of a Temporal Set runtime struct.
% row_start is zero-based, matching Canonical Dataset API range operations.
function M = gxtxt_temporal_set_member(S, index)
  if (!isstruct(S) || !isfield(S,'enabled') || !S.enabled)
    error('GXTXT:TemporalSet','An enabled Temporal Set struct is required');
  endif
  if (!isscalar(index) || !isfinite(index) || index != fix(index) || index < 1 || index > S.member_count)
    error('GXTXT:TemporalSet','Temporal Set member index is outside 1..%d',S.member_count);
  endif
  if (strcmp(S.type,'segment_set'))
    M = S.members(index);
    return;
  endif
  if (!strcmp(S.type,'window_set'))
    error('GXTXT:TemporalSet','Unsupported Temporal Set type: %s',S.type);
  endif
  row_start = S.effective_row_start + (index-1)*S.resolved_step_rows;
  parent_end = S.effective_row_start + S.effective_row_count;
  row_count = min(S.resolved_window_rows,parent_end-row_start);
  if (row_count < 0), row_count = 0; endif
  time_start = NaN; time_end = NaN;
  if (strcmp(S.axis_kind,'uniform') && isfinite(S.axis_origin) && isfinite(S.axis_step))
    time_start = S.axis_origin + row_start*S.axis_step;
    time_end = S.axis_origin + (row_start+row_count)*S.axis_step;
  endif
  M = struct('index',index,'member_id',sprintf('win_%06d',index),'label','', ...
      'requested_time_start',time_start,'requested_time_end',time_end, ...
      'time_start',time_start,'time_end',time_end, ...
      'row_start',row_start,'row_count',row_count);
endfunction
