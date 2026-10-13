% SPDX-License-Identifier: GPL-3.0-or-later
function line=gxtxt_table_stream_v3_readline(fid,pid)
% Octave can report a temporary EOF on a nonblocking Windows popen2 pipe.
% Its Windows waitpid(WNOHANG) path can also block while the Tcl child is
% waiting for the next request. Keep that platform's polling path bounded.
  if(ispc())
    started=time();buffer='';
    while(time()-started<120)
      part=fgets(fid);
      if(ischar(part))
        buffer=[buffer part];
        if(!isempty(part)&&double(part(end))==10)
          line=regexprep(buffer,'[\r\n]+$','');return;
        endif
      endif
      fclear(fid);pause(0.002);
    endwhile
    error('GXTXT:TableStream','Table Stream v3 bridge response timed out');
  endif
  line=gxtxt_persistent_bridge_readline(fid,pid,'Table Stream v3');
endfunction
