% SPDX-License-Identifier: GPL-3.0-or-later
% Scattered XYZ triangulated surface. Delaunay connectivity is geometry only;
% this helper never interpolates values onto a grid.
function [h,tri]=gxtxt_plot_trisurf(ax,x,y,z,C,tri)
  if(nargin<1||isempty(ax)),ax=gca();endif
  if(nargin<4),error('GXTXT:Plot3D','trisurf requires x, y and z vectors');endif
  x=x(:);y=y(:);z=z(:);if(numel(x)!=numel(y)||numel(x)!=numel(z)||numel(x)<3),error('GXTXT:Plot3D','scattered x/y/z must have equal length >= 3');endif
  if(nargin<5),C=[];endif;if(!isempty(C)),C=C(:);if(numel(C)!=numel(z)),error('GXTXT:Plot3D','scattered color C must match x/y/z length');endif;endif
  if(nargin<6||isempty(tri)),tri=delaunay(x,y);endif
  if(!isnumeric(tri)||size(tri,2)!=3||isempty(tri)),error('GXTXT:Plot3D','triangulation must be an N x 3 index matrix');endif
  old=[];try old=gca();axes(ax);catch;end_try_catch
  unwind_protect
    if(isempty(C)),h=trisurf(tri,x,y,z);else h=trisurf(tri,x,y,z,C);endif
  unwind_protect_cleanup
    if(!isempty(old)),try axes(old);catch;end_try_catch;endif
  end_unwind_protect
  setappdata(ax,'gxtxt_plot_3d',true);
endfunction
