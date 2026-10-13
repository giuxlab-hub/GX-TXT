function mask = gxtxt_selection_mask(S, x, varargin)
  % Build an inclusive logical mask from a Dataset Selection API v1 struct.
  % mask = gxtxt_selection_mask(S,x)    for x_range
  % mask = gxtxt_selection_mask(S,x,y)  for rectangle
  % Coordinates passed here must be in the canonical units carried by S.
  % SPDX-License-Identifier: GPL-3.0-or-later
  if (!isstruct(S)), error('GXTXT:Selection','S must be a selection struct.'); endif
  x = x(:);
  if (!isfield(S,'enabled') || !S.enabled)
    mask = true(size(x));
    return;
  endif
  if (!isfield(S,'type')), error('GXTXT:Selection','Selection type is missing.'); endif
  typ=lower(strtrim(S.type));
  mask = isfinite(x) & x >= min(S.x_min,S.x_max) & x <= max(S.x_min,S.x_max);
  if (strcmp(typ,'x_range'))
    return;
  elseif (strcmp(typ,'rectangle'))
    if (isempty(varargin)), error('GXTXT:Selection','Rectangle selection requires Y data.'); endif
    y=varargin{1}(:);
    if (numel(y) != numel(x)), error('GXTXT:Selection','X and Y lengths differ.'); endif
    mask = mask & isfinite(y) & y >= min(S.y_min,S.y_max) & y <= max(S.y_min,S.y_max);
  else
    error('GXTXT:Selection','Unsupported Dataset Selection type: %s',typ);
  endif
endfunction
