% SPDX-License-Identifier: GPL-3.0-or-later
function S=gxtxt_table_stream_close(S)
  if(isstruct(S)&&isfield(S,'api_version')&&S.api_version>=3)
    if(isfield(S,'closed')&&S.closed),return;endif
    if(isfield(S,'bridge_in')&&S.bridge_in>=0)
      try,fputs(S.bridge_in,"CLOSE\n");fflush(S.bridge_in);gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid);catch;end_try_catch
      try,fclose(S.bridge_in);catch;end_try_catch;S.bridge_in=-1;
    endif
    if(isfield(S,'bridge_out')&&S.bridge_out>=0),try,fclose(S.bridge_out);catch;end_try_catch;S.bridge_out=-1;endif
    if(isfield(S,'bridge_pid')&&S.bridge_pid>0),try,waitpid(S.bridge_pid);catch;end_try_catch;S.bridge_pid=-1;endif
    S.closed=true;S.eof=true;return;
  endif
  if(isstruct(S)&&isfield(S,'fid')&&S.fid>=0),try fclose(S.fid);catch;end_try_catch;S.fid=-1;endif
endfunction
