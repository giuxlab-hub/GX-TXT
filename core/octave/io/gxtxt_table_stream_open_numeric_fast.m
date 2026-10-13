function S=gxtxt_table_stream_open_numeric_fast(path,columns,chunk_rows)
% Public Table Stream v2 specialization for strict, all-numeric CSV tables.
% A bounded native preflight rejects quoted, missing, malformed or ragged
% rows. Other tables retain the established general CSV parser unchanged.
% SPDX-License-Identifier: GPL-3.0-or-later
  S=gxtxt_table_stream_open(path,columns,chunk_rows);
  n=numel(S.names);
  if(n<1||n>16||isempty(S.indices)|| ...
     !any(strcmp(S.delimiter,{',',sprintf('\t')}))),return;endif
  for i=1:numel(S.schema)
    m=S.schema(i);
    if(!strcmp(m.value_kind,'number')||!strcmp(m.decimal_separator,'.')|| ...
       !isempty(strtrim(m.value_format))),return;endif
  endfor
  if(!numeric_csv_preflight(path,S.bytes_read,S.delimiter,n,chunk_rows)),return;endif
  S.numeric_fast=true;
  S.numeric_fast_format=repmat('%f',1,n);
endfunction

function ok=numeric_csv_preflight(path,offset,delimiter,n,chunk_rows)
  ok=false;fid=fopen(path,'r');if(fid<0),return;endif
  unwind_protect
    if(fseek(fid,offset,'bof')!=0),return;endif
    code=uint8(delimiter);carry=0;last=uint8(10);total_lines=0;
    while(true)
      b=fread(fid,1048576,'uint8=>uint8')';
      if(isempty(b)),break;endif
      allowed=(b>=48&b<=57)|(b==43)|(b==45)|(b==46)|(b==69)|(b==101)| ...
        (b==32)|(b==9)|(b==10)|(b==13)|(b==code);
      if(!all(allowed)),return;endif
      sep=cumsum(double(b==code));ends=find(b==10);
      if(!isempty(ends))
        counts=[sep(ends(1))+carry,diff(sep(ends))];
        if(any(counts!=n-1)),return;endif
        total_lines+=numel(ends);carry=sep(end)-sep(ends(end));
      else
        carry+=sep(end);
      endif
      last=b(end);
    endwhile
    if(last!=10)
      if(carry!=n-1),return;endif
      total_lines+=1;
    endif
    if(total_lines<1),return;endif
    fseek(fid,offset,'bof');fmt=repmat('%f',1,n);seen=0;
    while(true)
      data=textscan(fid,fmt,chunk_rows,'Delimiter',delimiter,'EndOfLine','\n','CollectOutput',true);
      if(isempty(data)||isempty(data{1})),break;endif
      a=data{1};if(columns(a)!=n||any(!isfinite(a(:)))),return;endif
      seen+=rows(a);
      if(seen>total_lines),return;endif
    endwhile
    ok=(seen==total_lines);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
