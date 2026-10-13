% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT Scientific Plot Framework API v1: common 3D axes styling.
function gxtxt_plot_apply_axes3d(ax,p)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<2),p=gxtxt_plot_config();endif
  gxtxt_plot_apply_axes(ax,p);
  try
    mode='inherit';if(isfield(p,'grid_mode')),mode=lower(strtrim(p.grid_mode));endif
    switch mode
      case 'none',set(ax,'zgrid','off');
      otherwise,if(p.grid),set(ax,'zgrid','on');else set(ax,'zgrid','off');endif
    endswitch
  catch
  end_try_catch
  try
    az=-37.5;el=30;
    if(isfield(p,'view_azimuth')&&isfinite(p.view_azimuth)),az=p.view_azimuth;endif
    if(isfield(p,'view_elevation')&&isfinite(p.view_elevation)),el=p.view_elevation;endif
    view(ax,az,el);
  catch
  end_try_catch
  try
    if(isfield(p,'projection')&&!isempty(p.projection)),set(ax,'projection',p.projection);endif
  catch
    % Some Octave graphics toolkits/releases do not expose projection.
  end_try_catch
  mode='auto';ratio='';
  if(isfield(p,'aspect_mode')),mode=p.aspect_mode;endif
  if(isfield(p,'aspect_ratio')),ratio=p.aspect_ratio;endif
  if(gxtxt_plot_axis_is_3d(ax)),gxtxt_plot_apply_aspect3d(ax,mode,ratio);endif
endfunction
