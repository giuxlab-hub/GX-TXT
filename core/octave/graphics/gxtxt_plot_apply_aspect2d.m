% SPDX-License-Identifier: GPL-3.0-or-later
% Public Scientific Plot Framework 2D XY data-aspect policy.
function ratio = gxtxt_plot_apply_aspect2d(ax,mode)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<2||isempty(mode)),mode='auto';endif
  mode=lower(strtrim(mode));
  if(strcmp(mode,'inherit')),mode='auto';endif
  if(!any(strcmp(mode,{'auto','xy_equal'})))
    error('GXTXT:XYAspectMode','Unknown 2D XY aspect mode: %s',mode);
  endif
  if(strcmp(mode,'xy_equal'))
    if(!strcmp(get(ax,'xscale'),'linear')||!strcmp(get(ax,'yscale'),'linear'))
      error('GXTXT:XYAspectLog','xy_equal requires linear X and Y scales');
    endif
    set(ax,'plotboxaspectratiomode','auto');
    daspect(ax,[1 1 1]);
  else
    set(ax,'dataaspectratiomode','auto');
    set(ax,'plotboxaspectratiomode','auto');
  endif
  ratio=get(ax,'dataaspectratio');
  setappdata(ax,'gxtxt_plot_aspect_mode',mode);
  setappdata(ax,'gxtxt_plot_xy_aspect_mode',mode);
  setappdata(ax,'gxtxt_plot_aspect_ratio',ratio);
endfunction
