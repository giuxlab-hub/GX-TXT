function G=demo_visualization_surface3d_prepare_grid(x,y,z)
% Validate and map finite XYZ rows to one exact rectangular grid.
% No interpolation or scattered-data gridding is performed.
% SPDX-License-Identifier: GPL-3.0-or-later
  x=double(x(:));y=double(y(:));z=double(z(:));
  if(isempty(x)||numel(x)!=numel(y)||numel(x)!=numel(z))
    error('demo.visualization.surface3d: bound variables do not contain aligned XYZ rows');
  endif
  if(any(!isfinite(x))||any(!isfinite(y))||any(!isfinite(z)))
    error('demo.visualization.surface3d: X, Y, and Z must contain only finite values');
  endif
  xu=sort(unique(x)); yu=sort(unique(y)); nx=numel(xu); ny=numel(yu); n=numel(x);
  if(nx<2||ny<2), error('demo.visualization.surface3d: X and Y must each contain multiple unique coordinates'); endif
  if(n!=nx*ny)
    error('demo.visualization.surface3d: source is not a complete rectangular grid (%d rows, %d x %d expected)',n,nx,ny);
  endif
  [okx,ix]=ismember(x,xu); [oky,iy]=ismember(y,yu);
  if(!all(okx)||!all(oky)), error('demo.visualization.surface3d: failed to resolve X/Y coordinates onto the grid'); endif
  linear=sub2ind([ny,nx],iy,ix);
  if(numel(unique(linear))!=n)
    error('demo.visualization.surface3d: duplicate X/Y grid coordinates are not allowed');
  endif
  Z=nan(ny,nx); Z(linear)=z;
  if(any(!isfinite(Z(:))))
    error('demo.visualization.surface3d: one or more rectangular grid cells are missing');
  endif
  G=struct('x_grid',xu(:).','y_grid',yu(:).','z_grid',Z,'nx',nx,'ny',ny);
endfunction
