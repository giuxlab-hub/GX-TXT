% SPDX-License-Identifier: GPL-3.0-or-later
% Gridded mesh primitive. No scattered-data interpolation is performed.
function h=gxtxt_plot_mesh(ax,X,Y,Z,C)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<4),error('GXTXT:Plot3D','mesh requires X, Y and Z');endif
  validate_grid_local(X,Y,Z);
  if(nargin<5||isempty(C)),h=mesh(ax,X,Y,Z);else if(!isnumeric(C)||!isequal(size(C),size(Z))),error('GXTXT:Plot3D','mesh color C must match Z size');endif;h=mesh(ax,X,Y,Z,C);endif
  setappdata(ax,'gxtxt_plot_3d',true);
endfunction
function validate_grid_local(X,Y,Z)
  if(!isnumeric(Z)||ndims(Z)!=2||isempty(Z)),error('GXTXT:Plot3D','mesh requires a non-empty numeric Z matrix');endif
  [nr,nc]=size(Z);ok=(isvector(X)&&isvector(Y)&&numel(X)==nc&&numel(Y)==nr)||(isequal(size(X),size(Z))&&isequal(size(Y),size(Z)));
  if(!ok),error('GXTXT:Plot3D','mesh requires gridded X/Y compatible with Z; scattered XYZ must use trisurf');endif
endfunction
