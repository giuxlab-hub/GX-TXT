function emitted = gxtxt_progress_start(stage, message, mode, total)
  if (nargin < 1), stage=''; endif
  if (nargin < 2), message=''; endif
  if (nargin < 3), mode='indeterminate'; endif
  if (nargin < 4), total=''; endif
  emitted = gxtxt_progress('start',stage,message,mode,total);
endfunction
