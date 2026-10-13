% SPDX-License-Identifier: GPL-3.0-or-later
% Presentation-only scaling for a physical color variable C.
function [out,display_unit,factor]=gxtxt_plot_color_scale(values,source_unit,mode)
  if(nargin<3||isempty(mode)),mode='auto';endif
  if(strcmpi(mode,'source')||strcmpi(mode,'inherit')||strcmpi(mode,'none')),mode='none';endif
  [out,display_unit,factor]=gxtxt_plot_display_scale(values,source_unit,mode);
endfunction
