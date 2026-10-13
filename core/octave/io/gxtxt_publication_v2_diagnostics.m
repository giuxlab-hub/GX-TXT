function [P,d]=gxtxt_publication_v2_diagnostics(P),[P,x]=gxtxt_publication_v2_call(P,'DIAG');d=gxtxt_table_stream_v3_decode(x{2});endfunction
