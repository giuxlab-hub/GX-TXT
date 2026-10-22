function [xyz, scalar, verts, lines, polys, primitive] = pd_scene_group(P, G, point_order, contour_levels)
  kind = P.plot_type;
  scalar=[]; verts=[]; lines={}; polys=[];
  if (any(strcmp(kind, {'surface','mesh','heatmap'})))
    x=G.x(:); y=G.y(:); z=G.z;
    if (!isequal(size(z), [numel(y), numel(x)])), error('plot.dataset interactive: prepared grid shape mismatch'); endif
    [X,Y]=meshgrid(x,y);
    if (strcmp(kind,'heatmap')), Z=zeros(size(z)); else Z=z; endif
    xyz=[X(:),Y(:),Z(:)];
    if (!isempty(G.c)), scalar=G.c(:); else scalar=z(:); endif
    ny=numel(y); nx=numel(x);
    if (strcmp(kind,'mesh'))
      % A rectangular mesh has only its actual row/column edges. Surface
      % triangulation would add scientific-looking diagonal connections.
      for j=1:nx
        for i=1:ny-1
          a=(j-1)*ny+i-1;lines{end+1}=[a,a+1];
        endfor
      endfor
      for i=1:ny
        for j=1:nx-1
          a=(j-1)*ny+i-1;lines{end+1}=[a,a+ny];
        endfor
      endfor
      primitive='trajectory';
    else
      for j=1:nx-1
        for i=1:ny-1
          a=(j-1)*ny+i-1; b=j*ny+i-1; c=a+1; d=b+1;
          polys(end+1,:)=[a,b,d]; polys(end+1,:)=[a,d,c];
        endfor
      endfor
      primitive='surface';
    endif
  elseif (strcmp(kind,'contour3'))
    x=G.x(:); y=G.y(:); z=G.z;
    if (!isequal(size(z), [numel(y),numel(x)])), error('plot.dataset interactive: contour grid shape mismatch'); endif
    C=contourc(x,y,z,contour_levels);
    xyz=zeros(0,3); pos=1;
    while (pos < columns(C))
      level=C(1,pos); n=round(C(2,pos));
      if (n<2 || pos+n>columns(C)), error('plot.dataset interactive: invalid contour segment'); endif
      first=rows(xyz);
      xyz=[xyz; C(1,pos+1:pos+n)', C(2,pos+1:pos+n)', repmat(level,n,1)];
      lines{end+1}=first:(first+n-1);
      pos+=n+1;
    endwhile
    if (isempty(lines)), error('plot.dataset interactive: contour has no displayable segments'); endif
    primitive='trajectory';
  else
    x=G.x(:); y=G.y(:); z=G.z(:);
    if (numel(x)!=numel(y) || numel(x)!=numel(z)), error('plot.dataset interactive: scattered XYZ shape mismatch'); endif
    xyz=[x,y,z];
    if (!isempty(G.c)), scalar=G.c(:);
    elseif (strcmp(kind,'trisurf')), scalar=z;
    endif
    if (strcmp(point_order,'sort_x') && any(strcmp(kind,{'line3','trisurf'})))
      [~,order]=sort(xyz(:,1)); xyz=xyz(order,:);
      if (!isempty(scalar)), scalar=scalar(order); endif
    endif
    if (strcmp(kind,'scatter3'))
      verts=(0:rows(xyz)-1)'; primitive='points';
    elseif (strcmp(kind,'line3'))
      lines={0:rows(xyz)-1}; primitive='trajectory';
    elseif (strcmp(kind,'trisurf'))
      tri=delaunay(x,y);
      if (isempty(tri) || columns(tri)!=3), error('plot.dataset interactive: triangulation failed'); endif
      polys=tri-1; primitive='surface';
    else error('plot.dataset interactive: unsupported prepared plot type'); endif
  endif
  if (isempty(xyz) || any(!isfinite(xyz(:))) || (!isempty(scalar) && (numel(scalar)!=rows(xyz) || any(!isfinite(scalar)))))
    error('plot.dataset interactive: nonfinite or inconsistent scene values');
  endif
endfunction
