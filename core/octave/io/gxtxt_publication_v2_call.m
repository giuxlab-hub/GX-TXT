function [P,parts]=gxtxt_publication_v2_call(P,line)
 if(P.closed),error('GXTXT:Publication','Publication handle is closed');endif
 fputs(P.bridge_in,[line "\n"]);fflush(P.bridge_in); raw=gxtxt_publication_v2_readline(P.bridge_out,P.bridge_pid);parts=gxtxt_table_stream_v3_parts(raw);
 if(numel(parts)>=2&&strcmp(parts{1},'ERROR')),error('GXTXT:Publication','%s',gxtxt_table_stream_v3_decode(parts{2}));endif
endfunction
