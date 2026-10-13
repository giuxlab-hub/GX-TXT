function [P,result]=gxtxt_publication_v2_finalize(P)
 [P,x]=gxtxt_publication_v2_call(P,'FINALIZE');result=gxtxt_table_stream_v3_decode(x{2});P=finish(P);P.finalized=true;
endfunction
function P=finish(P),try fclose(P.bridge_in);catch;end_try_catch;try fclose(P.bridge_out);catch;end_try_catch;try waitpid(P.bridge_pid);catch;end_try_catch;P.bridge_in=-1;P.bridge_out=-1;P.bridge_pid=-1;P.closed=true;endfunction
