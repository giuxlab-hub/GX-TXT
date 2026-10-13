function [S,chunk]=gxtxt_table_stream_numeric_fast_next(S)
% Read a preflighted numeric CSV chunk without per-character Octave loops.
% SPDX-License-Identifier: GPL-3.0-or-later
  data=textscan(S.fid,S.numeric_fast_format,S.chunk_rows, ...
    'Delimiter',S.delimiter,'EndOfLine','\n','CollectOutput',true);
  if(isempty(data)),A=zeros(0,numel(S.names));else A=data{1};endif
  n=rows(A);if(columns(A)!=numel(S.names)),error('GXTXT:TableStream','Numeric CSV changed during streaming');endif
  first=S.row_number+1;S.row_number+=n;
  S.bytes_read=ftell(S.fid);S.eof=feof(S.fid)||n<S.chunk_rows;
  values=cell(1,numel(S.indices));for i=1:numel(values),values{i}=A(:,S.indices(i));endfor
  chunk=struct('api_version',2,'names',{S.columns},'values',{values},'nrows',n, ...
    'first_row',first,'last_row',S.row_number,'eof',S.eof, ...
    'bytes_read',S.bytes_read,'total_bytes',S.total_bytes,'schema',S.schema);
endfunction
