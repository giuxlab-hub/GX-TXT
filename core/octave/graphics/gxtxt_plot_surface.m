% SPDX-License-Identifier: GPL-3.0-or-later
% Gridded surface primitive. No scattered-data interpolation is performed.
function h=gxtxt_plot_surface(ax,X,Y,Z,C)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<4),error('GXTXT:Plot3D','surface requires X, Y and Z');endif
  validate_grid(X,Y,Z,'surface');
  if(nargin<5||isempty(C)),h=surf(ax,X,Y,Z);else validate_color(C,Z,'surface');h=surf(ax,X,Y,Z,C);endif
  setappdata(ax,'gxtxt_plot_3d',true);
  % A surface is a filled plot; the mesh primitive provides wire edges.
  % Dense grids otherwise render as a nearly black wireframe by default.
  set(h,'edgecolor','none');
endfunction
function validate_grid(X,Y,Z,name)
  if(!isnumeric(Z)||ndims(Z)!=2||isempty(Z)),error('GXTXT:Plot3D','%s requires a non-empty numeric Z matrix',name);endif
  [nr,nc]=size(Z);
  ok=(isvector(X)&&isvector(Y)&&numel(X)==nc&&numel(Y)==nr) || (isequal(size(X),size(Z))&&isequal(size(Y),size(Z)));
  if(!ok),error('GXTXT:Plot3D','%s requires gridded X/Y compatible with Z; scattered XYZ must use trisurf',name);endif
endfunction
function validate_color(C,Z,name)
  if(!isnumeric(C)||!isequal(size(C),size(Z))),error('GXTXT:Plot3D','%s color C must have the same grid size as Z',name);endif
endfunction
