function idx=tdfft_select_windows(cfg, graph, times, member_ids)
% Resolve a human-facing plot/export window selection into 1-based indices.
% SPDX-License-Identifier: GPL-3.0-or-later
  n=numel(times);
  if(n<1),idx=[];return;endif
  prefix=['plot.' graph '.'];
  mode=lower(strtrim(gxtxt_ini_get(cfg,[prefix 'selection_mode'],'all')));
  switch(mode)
    case 'all'
      idx=(1:n)';
    case 'index_range'
      a=parse_int(gxtxt_ini_get(cfg,[prefix 'start_index'],'1'),1);
      b=parse_int(gxtxt_ini_get(cfg,[prefix 'end_index'],'0'),0);
      if(b<=0),b=n;endif
      a=max(1,a);b=min(n,b);
      if(b<a),error('analysis.time_dependent_fft: selected window index range is empty (%d..%d)',a,b);endif
      idx=(a:b)';
    case 'explicit_list'
      idx=parse_index_list(gxtxt_ini_get(cfg,[prefix 'explicit_list'],''),n);
      if(isempty(idx)),error('analysis.time_dependent_fft: explicit window list is empty');endif
    case 'time_range'
      lo=parse_optional_number(gxtxt_ini_get(cfg,[prefix 'time_start'],''),-Inf);
      hi=parse_optional_number(gxtxt_ini_get(cfg,[prefix 'time_end'],''),Inf);
      if(hi<lo),error('analysis.time_dependent_fft: plot time range end is smaller than start');endif
      idx=find(times(:)>=lo & times(:)<=hi);
      if(isempty(idx)),error('analysis.time_dependent_fft: no Temporal Set windows fall inside the selected time range');endif
    otherwise
      error('analysis.time_dependent_fft: unsupported window selection mode: %s',mode);
  endswitch
  idx=unique(idx(:),'stable');
endfunction

function idx=parse_index_list(raw,n)
  raw=strtrim(raw);idx=[];
  if(isempty(raw)),return;endif
  raw=strrep(raw,';',',');parts=strsplit(raw,',');
  for i=1:numel(parts)
    token=strtrim(parts{i});if(isempty(token)),continue;endif
    dash=find(token=='-',1);
    if(isempty(dash))
      v=str2double(token);
      if(!isfinite(v)||v!=fix(v)||v<1||v>n),error('analysis.time_dependent_fft: invalid window index "%s"',token);endif
      idx(end+1,1)=v;
    else
      a=str2double(strtrim(token(1:dash-1)));b=str2double(strtrim(token(dash+1:end)));
      if(!isfinite(a)||!isfinite(b)||a!=fix(a)||b!=fix(b)||a<1||b<1||a>n||b>n||b<a)
        error('analysis.time_dependent_fft: invalid window range "%s"',token);
      endif
      idx=[idx;(a:b)'];
    endif
  endfor
endfunction

function v=parse_int(raw,def)
  v=str2double(strtrim(raw));if(!isfinite(v)||v!=fix(v)),v=def;endif
endfunction
function v=parse_optional_number(raw,def)
  raw=strtrim(raw);if(isempty(raw)),v=def;return;endif
  v=str2double(raw);if(!isfinite(v)),error('analysis.time_dependent_fft: invalid numeric time selection value: %s',raw);endif
endfunction
