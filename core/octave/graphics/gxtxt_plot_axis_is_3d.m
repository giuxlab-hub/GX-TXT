% SPDX-License-Identifier: GPL-3.0-or-later
% Classify plotted 3D topology, independently of the camera elevation.
function tf = gxtxt_plot_axis_is_3d(ax)
  tf=false;
  if(isempty(ax)||!ishandle(ax)),return;endif
  try
    marker=getappdata(ax,'gxtxt_plot_3d');
    if(!isempty(marker)&&logical(marker)),tf=true;return;endif
  catch
  end_try_catch
  try children=findall(ax);catch;children=[];end_try_catch
  for k=1:numel(children)
    if(children(k)==ax),continue;endif
    try
      type=get(children(k),'type');
      if(!any(strcmp(type,{'line','surface','patch','scatter'}))),continue;endif
      z=get(children(k),'zdata');
      if(!isnumeric(z)||isempty(z)),continue;endif
      finite=z(isfinite(z));
      if(!isempty(finite)&&(max(finite(:))-min(finite(:))>0 || any(finite(:)!=0)))
        tf=true;return;
      endif
    catch
    end_try_catch
  endfor
endfunction
