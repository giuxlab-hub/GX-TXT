% SPDX-License-Identifier: GPL-3.0-or-later
% Convert a user-facing font size to Octave points.
% In "px" mode the requested value refers to pixels in the final PNG.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
function pt = gxtxt_plot_font_to_points(value, unit, dpi)
  pt = NaN;
  if (nargin < 1 || !isfinite(value) || value <= 0), return; endif
  if (nargin < 2 || isempty(unit)), unit = 'px'; endif
  if (nargin < 3 || !isfinite(dpi) || dpi <= 0), dpi = 200; endif
  unit = lower(strtrim(unit));
  if (strcmp(unit,'px') || strcmp(unit,'pixel') || strcmp(unit,'pixels'))
    % 1 point = dpi/72 output pixels when print() rasterizes at dpi.
    pt = value * 72.0 / dpi;
  else
    pt = value;
  endif
endfunction
