function A=gxtxt_audio_decode_close(A)
 if(A.closed),return;endif
 close_error='';
 try
   fputs(A.bridge_in,"CLOSE\n");fflush(A.bridge_in);
   response=gxtxt_persistent_bridge_readline(A.bridge_out,A.bridge_pid,'Audio Decode');
   if(!strcmp(response,'CLOSED')),close_error=['unexpected close response: ' response];endif
 catch err
   close_error=err.message;
 end_try_catch
 try fclose(A.bridge_in);catch;end_try_catch
 try fclose(A.bridge_out);catch;end_try_catch
 done=0;
 if(isempty(close_error))
   try [wp,~,~]=waitpid(A.bridge_pid);done=(wp==A.bridge_pid||wp<0);catch;end_try_catch
 else
   started=time();
   while(time()-started<2)
     try [wp,~,~]=waitpid(A.bridge_pid,WNOHANG());catch;wp=-1;end_try_catch
     if(wp==A.bridge_pid||wp<0),done=1;break;endif
     pause(0.01);
   endwhile
   if(!done)
     try kill(A.bridge_pid,SIGTERM());catch;end_try_catch
     started=time();
     while(time()-started<2)
       try [wp,~,~]=waitpid(A.bridge_pid,WNOHANG());catch;wp=-1;end_try_catch
       if(wp==A.bridge_pid||wp<0),done=1;break;endif
       pause(0.01);
     endwhile
   endif
 endif
 if(!done),try kill(A.bridge_pid,SIGKILL());waitpid(A.bridge_pid);catch;end_try_catch;endif
 A.closed=true;A.bridge_pid=-1;A.bridge_in=-1;A.bridge_out=-1;
 if(!isempty(close_error)),error('GXTXT:AudioDecode','Audio Decode close failed: %s',close_error);endif
endfunction
