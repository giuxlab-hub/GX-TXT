% SPDX-License-Identifier: GPL-3.0-or-later
% Adapt a time-axis label to the selected display unit.
function out = gxtxt_plot_time_label(base, unit)
  if (nargin < 1), base=''; endif
  if (nargin < 2 || isempty(unit)), unit='s'; endif
  unit=lower(strtrim(unit));
  if (strcmp(unit,'us')), shown='us'; else shown=unit; endif
  if (isempty(strtrim(base)))
    out=['Time [' shown ']'];
    return;
  endif
  out=base;
  % Replace a trailing common time unit if present. Free-form labels without a
  % recognized trailing unit remain untouched.
  pats={'[s]','[ms]','[us]','[µs]','[μs]','[ns]'};
  for k=1:numel(pats)
    p=pats{k};
    if (length(out)>=length(p) && strcmp(out(end-length(p)+1:end),p))
      out=[out(1:end-length(p)) '[' shown ']'];
      return;
    endif
  endfor
endfunction
