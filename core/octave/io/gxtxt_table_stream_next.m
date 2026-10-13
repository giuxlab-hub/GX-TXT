% SPDX-License-Identifier: GPL-3.0-or-later
% Read the next selected-column chunk as raw strings.
% chunk.values is a cell array: one N x 1 cell vector per requested column.
function [S,chunk]=gxtxt_table_stream_next(S)
  if(isstruct(S)&&isfield(S,'numeric_fast')&&S.numeric_fast)
    [S,chunk]=gxtxt_table_stream_numeric_fast_next(S);return;
  endif
  if(isstruct(S)&&isfield(S,'api_version')&&S.api_version>=3)
    [S,chunk]=gxtxt_table_stream_v3_next(S);return;
  endif
  if(!isstruct(S)||!isfield(S,'fid')||S.fid<0),error('GXTXT:TableStream','Invalid/closed stream');endif
  values=cell(1,numel(S.indices));for c=1:numel(values),values{c}=cell(0,1);endfor
  n=0;
  while(n<S.chunk_rows)
    line=fgetl(S.fid);if(!ischar(line)),S.eof=true;break;endif
    if(isempty(strtrim(line))),continue;endif
    r=gxtxt_csv_split_line(line,S.delimiter);if(numel(r)<numel(S.names)),r(end+1:numel(S.names))={''};endif;if(numel(r)>numel(S.names)),error('GXTXT:TableStream','Row has %d fields; expected %d',numel(r),numel(S.names));endif
    n+=1;S.row_number+=1;for c=1:numel(S.indices),values{c}{n,1}=r{S.indices(c)};endfor
  endwhile
  S.bytes_read=ftell(S.fid);if(S.bytes_read<0),S.bytes_read=S.total_bytes;endif
  chunk=struct('api_version',2,'names',{S.columns},'values',{values},'nrows',n,'first_row',S.row_number-n+1,'last_row',S.row_number,'eof',S.eof,'bytes_read',S.bytes_read,'total_bytes',S.total_bytes,'schema',S.schema);
endfunction
