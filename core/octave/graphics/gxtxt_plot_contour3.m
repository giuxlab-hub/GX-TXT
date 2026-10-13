% SPDX-License-Identifier: GPL-3.0-or-later
% Gridded 3D contour primitive. No scattered-data interpolation is performed.
function h=gxtxt_plot_contour3(ax,X,Y,Z,levels)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<4),error('GXTXT:Plot3D','contour3 requires X, Y and Z');endif
  validate_grid_local(X,Y,Z);
  if(nargin<5||isempty(levels)),[~,h]=contour3(ax,X,Y,Z);else [~,h]=contour3(ax,X,Y,Z,levels);endif
  setappdata(ax,'gxtxt_plot_3d',true);
endfunction
function validate_grid_local(X,Y,Z)
  if(!isnumeric(Z)||ndims(Z)!=2||isempty(Z)),error('GXTXT:Plot3D','contour3 requires a non-empty numeric Z matrix');endif
  [nr,nc]=size(Z);ok=(isvector(X)&&isvector(Y)&&numel(X)==nc&&numel(Y)==nr)||(isequal(size(X),size(Z))&&isequal(size(Y),size(Z)));
  if(!ok),error('GXTXT:Plot3D','contour3 requires gridded X/Y compatible with Z; scattered XYZ are not interpolated');endif
endfunction
