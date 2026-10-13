% SPDX-License-Identifier: GPL-3.0-or-later
function diagnostics=gxtxt_table_stream_diagnostics(S)
  if(!isstruct(S)||!isfield(S,'api_version')||S.api_version<3||!isfield(S,'bridge_in')||S.bridge_in<0),error('GXTXT:TableStream','Diagnostics require an open Table Stream v3 stream');endif
  fputs(S.bridge_in,"DIAG\n");fflush(S.bridge_in);
  head=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid));bridge_error(head);
  if(numel(head)!=2||!strcmp(head{1},'DIAG')),error('GXTXT:TableStream','Invalid Table Stream v3 diagnostics response');endif
  count=str2double(head{2});diagnostics=struct();
  for i=1:count
    item=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid));
    if(numel(item)!=3||!strcmp(item{1},'ITEM')),error('GXTXT:TableStream','Invalid Table Stream v3 diagnostic item');endif
    key=regexprep(gxtxt_table_stream_v3_decode(item{2}),'[^A-Za-z0-9_]','_');value=gxtxt_table_stream_v3_decode(item{3});numeric=str2double(value);
    if(!isnan(numeric)&&!isempty(value)),diagnostics.(key)=numeric;else diagnostics.(key)=value;endif
  endfor
  ending=gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid);if(!strcmp(ending,'END')),error('GXTXT:TableStream','Invalid Table Stream v3 diagnostics terminator');endif
endfunction
function bridge_error(parts),if(numel(parts)>=2&&strcmp(parts{1},'ERROR')),error('GXTXT:TableStream','%s',gxtxt_table_stream_v3_decode(parts{2}));endif;endfunction
