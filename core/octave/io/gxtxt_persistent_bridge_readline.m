function line=gxtxt_persistent_bridge_readline(fid,pid,label)
% Read one complete newline-terminated record from a persistent popen2 bridge.
% popen2 streams are nonblocking and fgets() can return a partial line. Buffer
% fragments until LF so large Base64/binary protocol records remain framed.
 if(nargin<3),label='CORE';endif;started=time();buffer='';
 while(time()-started<300)
   part=fgets(fid);
   if(ischar(part))
     buffer=[buffer part];
     if(!isempty(part)&&double(part(end))==10)
       line=regexprep(buffer,'[\r\n]+$','');return;
     endif
     fclear(fid);pause(0.001);continue;
   endif
   % Windows Octave can block inside waitpid(WNOHANG) for popen2 children.
   % The bounded pipe poll below provides the same framing without that call.
   if(!ispc())
     [done,~,~]=waitpid(pid,WNOHANG());
     if(done==pid||done<0)
       if(!isempty(buffer)),error('GXTXT:Bridge','%s bridge terminated with an incomplete protocol record',label);endif
       error('GXTXT:Bridge','%s bridge terminated unexpectedly',label);
     endif
   endif
   fclear(fid);pause(0.001);
 endwhile
 error('GXTXT:Bridge','%s bridge response timed out',label);
endfunction
