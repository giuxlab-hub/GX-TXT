% SPDX-License-Identifier: GPL-3.0-or-later
% Public metadata bridge for plot axes/color variables.
% which: x, y, z, or c. factor maps source -> display: display=source*factor+offset.
function gxtxt_plot_set_axis_metadata(ax,which,source_variable,source_unit,display_unit,factor,offset)
  if(nargin<2||isempty(ax)),return;endif
  which=lower(strtrim(which));
  if(!any(strcmp(which,{'x','y','z','c'}))),error('GXTXT:PlotMeta','which must be x, y, z or c');endif
  if(nargin<3),source_variable='';endif;if(nargin<4),source_unit='';endif;if(nargin<5),display_unit=source_unit;endif
  if(nargin<6||isempty(factor)||!isfinite(factor)||factor==0),factor=1;endif
  if(nargin<7||isempty(offset)||!isfinite(offset)),offset=0;endif
  try setappdata(ax,['gxtxt_' which '_source_variable'],source_variable);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_source_unit'],source_unit);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_display_unit'],display_unit);catch;end_try_catch
  % Selection/metadata sidecars store display -> source, hence inverse factor.
  try setappdata(ax,['gxtxt_' which '_display_to_source_scale'],1/factor);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_display_to_source_offset'],-offset/factor);catch;end_try_catch
endfunction
