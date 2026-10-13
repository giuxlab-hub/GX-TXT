function emitted = gxtxt_progress_complete(stage, message)
  if (nargin < 1), stage=''; endif
  if (nargin < 2), message=''; endif
  emitted = gxtxt_progress('complete',stage,message);
endfunction
