% SPDX-License-Identifier: GPL-3.0-or-later
% Read a UTF-8-ish comma-separated table into a lightweight framework struct.
% The parser supports RFC4180-style quoted fields and doubled quote escaping.
function T = gxtxt_read_csv_table(path)
  fid = fopen(path,'r');
  if (fid < 0), error('GXTXT:CSV','Cannot open CSV: %s',path); endif
  unwind_protect
    header = '';
    while (true)
      header = fgetl(fid);
      if (!ischar(header)), error('GXTXT:CSV','CSV has no header: %s',path); endif
      if (!isempty(strtrim(header))), break; endif
    endwhile
    names = csv_split_line(header);
    for k=1:numel(names), names{k}=strtrim(names{k}); endfor
    if (isempty(names) || any(cellfun(@isempty,names))), error('GXTXT:CSV','CSV contains an empty header field: %s',path); endif
    rows = {};
    while (true)
      line = fgetl(fid);
      if (!ischar(line)), break; endif
      if (isempty(line)), continue; endif
      r = csv_split_line(line);
      if (numel(r) < numel(names)), r(end+1:numel(names)) = {''}; endif
      if (numel(r) > numel(names)), error('GXTXT:CSV','Row has %d fields; expected %d in %s',numel(r),numel(names),path); endif
      rows(end+1,1:numel(names)) = r; %#ok<AGROW>
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  T = struct('path',path,'names',{names},'rows',{rows},'nrows',size(rows,1),'ncols',numel(names));
endfunction

function fields = csv_split_line(line)
  fields = {};
  buf = '';
  quoted = false;
  i = 1;
  while (i <= length(line))
    c = line(i);
    if (quoted)
      if (c == '"')
        if (i < length(line) && line(i+1) == '"')
          buf(end+1) = '"'; i += 2; continue;
        else
          quoted = false; i += 1; continue;
        endif
      else
        buf(end+1) = c; i += 1; continue;
      endif
    else
      if (c == ',')
        fields{end+1} = buf; buf=''; i += 1; continue; %#ok<AGROW>
      elseif (c == '"' && isempty(buf))
        quoted = true; i += 1; continue;
      else
        buf(end+1) = c; i += 1; continue;
      endif
    endif
  endwhile
  if (quoted), error('GXTXT:CSV','Unterminated quoted CSV field'); endif
  fields{end+1} = buf;
endfunction
