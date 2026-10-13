% SPDX-License-Identifier: GPL-3.0-or-later
% Return one named column from gxtxt_read_csv_table().
function v = gxtxt_table_column(T,name,type)
  if (nargin < 3 || isempty(type)), type='auto'; endif
  idx = find(strcmp(T.names,name),1);
  if (isempty(idx)), error('GXTXT:CSV','Column not found: %s',name); endif
  raw = T.rows(:,idx);
  type = lower(strtrim(type));
  if (strcmp(type,'string') || strcmp(type,'text') || strcmp(type,'categorical'))
    v = raw; return;
  endif
  num = NaN(numel(raw),1);
  all_numeric = true;
  for i=1:numel(raw)
    s = strtrim(raw{i});
    if (isempty(s)), num(i)=NaN; continue; endif
    q = str2double(s);
    if (!isfinite(q) && !strcmpi(s,'nan') && !strcmpi(s,'inf') && !strcmpi(s,'-inf'))
      all_numeric = false; break;
    endif
    num(i)=q;
  endfor
  if (strcmp(type,'numeric') || strcmp(type,'double') || strcmp(type,'number'))
    if (!all_numeric), error('GXTXT:CSV','Column %s is not numeric',name); endif
    v=num; return;
  endif
  if (all_numeric), v=num; else v=raw; endif
endfunction
