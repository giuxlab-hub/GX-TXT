function emitted = gxtxt_progress_fail(stage, message)
  if (nargin < 1), stage=''; endif
  if (nargin < 2), message=''; endif
  emitted = gxtxt_progress('fail',stage,message);
endfunction
