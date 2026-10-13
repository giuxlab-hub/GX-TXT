% SPDX-License-Identifier: GPL-3.0-or-later
% Public Scientific Plot Framework 3D aspect policy.
function ratio = gxtxt_plot_apply_aspect3d(ax,mode,manual_ratio)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<2||isempty(mode)),mode='auto';endif
  if(nargin<3),manual_ratio='';endif
  mode=lower(strtrim(mode));
  if(strcmp(mode,'inherit')),mode='auto';endif
  if(!any(strcmp(mode,{'auto','xy_equal','data_equal','manual'})))
    error('GXTXT:AspectMode','Unknown 3D aspect mode: %s',mode);
  endif
  ratio=[];
  switch mode
    case 'auto'
      set(ax,'dataaspectratiomode','auto');
      set(ax,'plotboxaspectratiomode','auto');
      ratio=get(ax,'dataaspectratio');
    case 'xy_equal'
      set(ax,'dataaspectratiomode','auto');
      set(ax,'plotboxaspectratiomode','auto');
      previous=get(ax,'dataaspectratio');
      z=previous(3)/sqrt(previous(1)*previous(2));
      if(!isfinite(z)||z<=0),z=1;endif
      ratio=[1 1 z];
      daspect(ax,ratio);
    case 'data_equal'
      ratio=framed_ratio(ax,[1 1 1]);
      daspect(ax,ratio);
    case 'manual'
      if(ischar(manual_ratio))
        parts=regexp(strtrim(manual_ratio),'[,;[:space:]]+','split');
        ratio=str2double(parts);
      else
        ratio=manual_ratio;
      endif
      if(!isnumeric(ratio)||numel(ratio)!=3||any(!isfinite(ratio))||any(ratio<=0))
        error('GXTXT:AspectRatio','Manual 3D aspect requires three finite positive values.');
      endif
      ratio=reshape(ratio,1,3);
      ratio=framed_ratio(ax,ratio);
      daspect(ax,ratio);
  endswitch
  setappdata(ax,'gxtxt_plot_aspect_mode',mode);
  setappdata(ax,'gxtxt_plot_aspect_ratio',ratio);
endfunction

function ratio=framed_ratio(ax,ratio)
  % A literal data aspect can make a geospatial surface a needle when its Z
  % range is many times its X/Y extent. Keep the requested X:Y geometry and
  % bound only the projected Z extent to 1.5 times the larger horizontal
  % extent. This applies equally to GUI Axes, global defaults and rerender.
  xl=get(ax,'xlim');yl=get(ax,'ylim');zl=get(ax,'zlim');
  extents=[diff(xl) diff(yl) diff(zl)];
  if(any(!isfinite(extents))||any(extents<=0)),return;endif
  horizontal=max(extents(1:2)./ratio(1:2));
  if(!isfinite(horizontal)||horizontal<=0),return;endif
  minimum_z_ratio=extents(3)/(1.5*horizontal);
  if(ratio(3)<minimum_z_ratio),ratio(3)=minimum_z_ratio;endif
endfunction
