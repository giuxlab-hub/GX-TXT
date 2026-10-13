function s=tdfft_axis_label(base,unit)
% Build an automatic label from a quantity name and display unit.
% SPDX-License-Identifier: GPL-3.0-or-later
  s=base;if(!isempty(strtrim(unit))),s=[s ' [' strtrim(unit) ']'];endif
endfunction
