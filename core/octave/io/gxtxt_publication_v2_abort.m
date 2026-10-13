function P=gxtxt_publication_v2_abort(P)
 if(P.closed),return;endif;try,[P,~]=gxtxt_publication_v2_call(P,'ABORT');catch;end_try_catch;try fclose(P.bridge_in);catch;end_try_catch;try fclose(P.bridge_out);catch;end_try_catch;try waitpid(P.bridge_pid);catch;end_try_catch;P.bridge_in=-1;P.bridge_out=-1;P.bridge_pid=-1;P.closed=true;
endfunction
