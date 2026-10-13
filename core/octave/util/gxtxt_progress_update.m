function emitted = gxtxt_progress_update(current, total, stage, message)
  if (nargin < 3), stage=''; endif
  if (nargin < 4), message=''; endif
  emitted = gxtxt_progress('update',current,total,stage,message);
endfunction
