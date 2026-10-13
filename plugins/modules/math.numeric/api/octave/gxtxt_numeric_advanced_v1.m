% Advanced public NUMERIC_API_v1 operations. Inputs and frames are explicit.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_advanced_v1(family,action,a,b,c,opts)
  switch(family)
    case 'geometry',out=geometry_action(action,a,b,c,opts);
    case 'sparse',out=sparse_action(action,a,b,c,opts);
    case 'equations',out=equations_action(action,a,b,c,opts);
    case 'variational',out=variational_action(action,a,b,c,opts);
    case 'statistics',out=statistics_action(action,a,b,c,opts);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown advanced family');
  endswitch
endfunction
function v=option(s,k,d),v=d;if(isfield(s,k)),v=s.(k);endif;endfunction
function finite(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Numeric:InvalidOperand','%s must be finite numeric data',name);
  endif
endfunction
function out=value(v)
  out=struct('value_real',real(v),'value_imaginary',imag(v));
endfunction
function v=vec3(x,name)
  finite(x,name);if(numel(x)!=3||!isreal(x)),error('GXTXT:Numeric:DimensionMismatch','%s must be a real three-vector',name);endif;v=x(:).';
endfunction
function out=geometry_action(action,a,b,c,opts)
  if(any(strcmp(action,{'mesh_section','volume_slice'}))&&ischar(a))
    out=vtk_geometry_file_action(action,a,b,c,opts);return;
  endif
  if(any(strcmp(action,{'mesh_smooth','mesh_remesh','mesh_boolean'}))&&ischar(a))
    out=vtk_geometry_file_action(action,a,b,c,opts);return;
  endif
  switch(action)
    case 'plane_frame'
      O=vec3(a,'origin');N=vec3(b,'normal');if(norm(N)<1e-12),error('GXTXT:Numeric:DegenerateFrame','normal is zero');endif;N=N/norm(N);
      if(isempty(c)),hint=[1 0 0];if(abs(dot(N,hint))>0.9),hint=[0 1 0];endif;else,hint=vec3(c,'U hint');endif
      U=hint-dot(hint,N)*N;if(norm(U)<1e-12),error('GXTXT:Numeric:DegenerateFrame','U hint is parallel to normal');endif
      U=U/norm(U);V=cross(N,U);
      out=struct('origin',O,'normal',N,'u_axis',U,'v_axis',V);
    case 'plane_three_points'
      P=vec3(a,'first point');Q=vec3(b,'second point');R=vec3(c,'third point');N=cross(Q-P,R-P);
      if(norm(N)<1e-12),error('GXTXT:Numeric:DegeneratePlane','three points are collinear');endif
      out=geometry_action('plane_frame',P,N,Q-P,struct());
    case 'centroid'
      finite(a,'points');if(columns(a)!=3),error('GXTXT:Numeric:DimensionMismatch','points must be N by 3');endif
      out=struct('centroid',mean(a,1));
    case 'plane_offset'
      O=vec3(a,'origin');N=vec3(b,'normal');finite(c,'offset');if(!isscalar(c)),error('GXTXT:Numeric:DimensionMismatch','offset must be scalar');endif
      if(norm(N)<1e-12),error('GXTXT:Numeric:DegenerateFrame','normal is zero');endif
      out=geometry_action('plane_frame',O+c*N/norm(N),N,[],struct());
    case 'plane_flip'
      out=geometry_action('plane_frame',a,-vec3(b,'normal'),c,struct());
    case 'plane_orient'
      O=vec3(a,'origin');finite(b,'azimuth elevation roll');if(numel(b)!=3),error('GXTXT:Numeric:DimensionMismatch','orientation must have azimuth elevation roll in radians');endif
      az=b(1);el=b(2);roll=b(3);N=[cos(el)*cos(az),cos(el)*sin(az),sin(el)];U=[-sin(az),cos(az),0];
      U=cos(roll)*U+sin(roll)*cross(N,U);out=geometry_action('plane_frame',O,N,U,struct());
    case 'trajectory_tangent'
      finite(a,'trajectory');finite(b,'row index');if(columns(a)!=3||rows(a)<2||!isscalar(b)||b<1||b>rows(a)||b!=fix(b)),error('GXTXT:Numeric:DimensionMismatch','N by 3 trajectory and one-based row index required');endif
      if(b==1),D=a(2,:)-a(1,:);elseif(b==rows(a)),D=a(end,:)-a(end-1,:);else,D=a(b+1,:)-a(b-1,:);endif
      if(norm(D)==0),error('GXTXT:Numeric:DegenerateTangent','local trajectory tangent is zero');endif
      out=struct('point',a(b,:),'tangent',D/norm(D),'source_row',b);
    case 'plane_containing_tangent'
      P=vec3(a,'point');D=vec3(b,'tangent');finite(c,'roll');if(!isscalar(c)),error('GXTXT:Numeric:DimensionMismatch','roll must be scalar radians');endif
      if(norm(D)<1e-12),error('GXTXT:Numeric:DegenerateTangent','tangent is zero');endif
      D=D/norm(D);H=[0 0 1];if(abs(dot(H,D))>0.9),H=[0 1 0];endif
      N=cross(D,H);N=N/norm(N);N=cos(c)*N+sin(c)*cross(D,N);out=geometry_action('plane_frame',P,N,D,struct());
    case 'trajectory_plane_intersections'
      finite(a,'trajectory');O=vec3(b,'origin');N=vec3(c,'normal');if(norm(N)<1e-12),error('GXTXT:Numeric:DegenerateFrame','normal is zero');endif;N=N/norm(N);
      if(columns(a)!=3||rows(a)<2),error('GXTXT:Numeric:DimensionMismatch','trajectory must have at least two 3D points');endif
      signed=(a-O)*N';p=[];pairs=[];fractions=[];
      for k=1:rows(a)-1
        d0=signed(k);d1=signed(k+1);
        if(d0==0&&d1==0),continue;endif
        if(d0*d1>0),continue;endif
        fraction=d0/(d0-d1);if(fraction<0||fraction>1),continue;endif
        p(end+1,:)=a(k,:)+fraction*(a(k+1,:)-a(k,:));pairs(end+1,:)=[k,k+1];fractions(end+1,1)=fraction;
      endfor
      out=struct('points',p,'source_row_pairs',pairs,'fraction',fractions,'status',ternary(isempty(p),'empty','intersected'));
    case 'mesh_section'
      finite(a,'vertices');finite(b,'triangle indices');O=vec3(c,'origin');N=vec3(option(opts,'normal',[]),'normal');N=N/norm(N);
      if(columns(a)!=3||columns(b)!=3||any(b(:)<1)||any(b(:)>rows(a))),error('GXTXT:Numeric:InvalidMesh','vertices N by 3 and triangle indices M by 3 required');endif
      tolerance=option(opts,'tolerance',1e-10);segments=[];source_triangles=[];
      for k=1:rows(b)
        T=a(b(k,:),:);d=(T-O)*N';points=[];
        for edge=[1 2;2 3;3 1]'
          i=edge(1);j=edge(2);if(abs(d(i))<=tolerance&&abs(d(j))<=tolerance),continue;endif
          if(d(i)*d(j)>0),continue;endif
          f=d(i)/(d(i)-d(j));if(f>=0&&f<=1),points(end+1,:)=T(i,:)+f*(T(j,:)-T(i,:));endif
        endfor
        if(rows(points)>=2&&norm(points(1,:)-points(2,:))>tolerance)
          segments(end+1,:)=[points(1,:),points(2,:)];source_triangles(end+1,1)=k;
        endif
      endfor
      out=struct('segments',segments,'source_triangle_index',source_triangles,'status',ternary(isempty(segments),'empty','intersected'));
    case 'frame_transform'
      finite(a,'points');O=vec3(b,'origin');finite(c,'frame');
      if(columns(a)!=3||!isequal(size(c),[3 3])||norm(c'*c-eye(3),'fro')>1e-8||det(c)<0)
        error('GXTXT:Numeric:InvalidFrame','points must be N by 3 and frame right-handed orthonormal');
      endif
      out=value((a-O)*c);
    case {'nearest','kdtree_query'}
      finite(a,'source points');finite(b,'query points');
      if(columns(a)!=columns(b)||columns(a)<1),error('GXTXT:Numeric:DimensionMismatch','point dimensions must match');endif
      index=zeros(rows(b),1);distance=zeros(rows(b),1);
      if(strcmp(action,'kdtree_query')),tree=build_kdtree(a,(1:rows(a))',1);endif
      for k=1:rows(b)
        if(strcmp(action,'nearest')),d=sum((a-b(k,:)).^2,2);[d2,index(k)]=min(d);
        else,[index(k),d2]=query_kdtree(tree,a,b(k,:),0,Inf);endif
        distance(k)=sqrt(d2);
      endfor
      out=struct('index',index,'distance',distance);
    case 'point_segment_distance'
      finite(a,'query points');P=vec3(b,'segment start');Q=vec3(c,'segment end');
      if(columns(a)!=3),error('GXTXT:Numeric:DimensionMismatch','query points must be N by 3');endif
      d=Q-P;den=dot(d,d);if(den==0),error('GXTXT:Numeric:DegenerateSegment','segment length is zero');endif
      t=max(0,min(1,((a-P)*d')/den));closest=P+t*d;
      out=struct('distance',sqrt(sum((a-closest).^2,2)),'fraction',t,'closest',closest);
    case 'triangle_area'
      finite(a,'triangles');if(columns(a)!=9),error('GXTXT:Numeric:DimensionMismatch','triangles must be N by 9 vertex coordinates');endif
      p=a(:,1:3);q=a(:,4:6);r=a(:,7:9);out=struct('area',sqrt(sum(cross(q-p,r-p,2).^2,2))/2);
    case 'tetrahedron_volume'
      finite(a,'tetrahedra');if(columns(a)!=12),error('GXTXT:Numeric:DimensionMismatch','tetrahedra must be N by 12 vertex coordinates');endif
      p=a(:,1:3);u=a(:,4:6)-p;v=a(:,7:9)-p;w=a(:,10:12)-p;out=struct('volume',abs(sum(u.*cross(v,w,2),2))/6);
    case 'barycentric'
      finite(a,'query points');finite(b,'triangle');if(columns(a)!=3||!isequal(size(b),[3 3])),error('GXTXT:Numeric:DimensionMismatch','N by 3 points and 3 by 3 triangle required');endif
      u=b(2,:)-b(1,:);v=b(3,:)-b(1,:);G=[dot(u,u),dot(u,v);dot(u,v),dot(v,v)];
      if(rcond(G)<1e-14),error('GXTXT:Numeric:DegenerateTriangle','triangle has zero area');endif
      w=(a-b(1,:))*[u;v]'/G;out=struct('weights',[1-sum(w,2),w],'plane_distance',abs((a-b(1,:))*cross(u,v)'/norm(cross(u,v))));
    case 'plane_fit'
      finite(a,'points');if(columns(a)!=3||rows(a)<3),error('GXTXT:Numeric:DimensionMismatch','at least three 3D points required');endif
      O=mean(a,1);[~,S,V]=svd(a-O,0);N=V(:,3)';if(N(find(abs(N)>1e-12,1))<0),N=-N;endif
      out=struct('origin',O,'normal',N,'rms_distance',S(3,3)/sqrt(rows(a)));
    case 'line_fit'
      finite(a,'points');if(columns(a)!=3||rows(a)<2),error('GXTXT:Numeric:DimensionMismatch','at least two 3D points required');endif
      O=mean(a,1);[~,S,V]=svd(a-O,0);D=V(:,1)';if(D(find(abs(D)>1e-12,1))<0),D=-D;endif
      out=struct('origin',O,'direction',D,'rms_distance',sqrt(sum(sum(((a-O)-((a-O)*D')*D).^2,2))/rows(a)));
    case 'rigid_transform'
      finite(a,'source points');finite(b,'target points');if(!isequal(size(a),size(b))||columns(a)!=3||rows(a)<3),error('GXTXT:Numeric:DimensionMismatch','matching N by 3 point sets required');endif
      P=mean(a);Q=mean(b);[U,~,V]=svd((a-P)'*(b-Q));R=U*diag([1 1 det(U*V')])*V';T=Q-P*R;
      out=struct('rotation',R,'translation',T,'rms_residual',sqrt(mean(sum((a*R+T-b).^2,2))));
    case {'mesh_surface_area','mesh_volume','point_triangle_distance','point_mesh_distance'}
      finite(b,'vertices');finite(c,'triangle indices');
      if(columns(b)!=3||columns(c)!=3||any(c(:)<1)||any(c(:)>rows(b))||any(c(:)!=fix(c(:)))),error('GXTXT:Numeric:InvalidMesh','vertices N by 3 and one-based triangle indices M by 3 required');endif
      p=b(c(:,1),:);q=b(c(:,2),:);r=b(c(:,3),:);
      if(strcmp(action,'mesh_surface_area')),out=struct('area',sum(sqrt(sum(cross(q-p,r-p,2).^2,2))/2));return;endif
      if(strcmp(action,'mesh_volume'))
        edges=sort([c(:,[1 2]);c(:,[2 3]);c(:,[3 1])],2);[~,~,ic]=unique(edges,'rows');
        if(any(accumarray(ic,1)!=2)),error('GXTXT:Numeric:OpenMesh','enclosed volume requires a closed manifold mesh');endif
        out=struct('signed_volume',sum(sum(p.*cross(q,r,2),2))/6,'volume',abs(sum(sum(p.*cross(q,r,2),2))/6));return;
      endif
      finite(a,'query points');if(columns(a)!=3),error('GXTXT:Numeric:DimensionMismatch','query points must be N by 3');endif
      dist=Inf(rows(a),1);nearest=zeros(rows(a),1);
      for k=1:rows(c)
        d=point_triangle_distance(a,p(k,:),q(k,:),r(k,:));take=d<dist;dist(take)=d(take);nearest(take)=k;
      endfor
      out=struct('distance',dist,'triangle_index',nearest);
    case 'delaunay'
      finite(a,'points');out=struct('simplices',delaunayn(a));
    case 'voronoi'
      finite(a,'points');[v,cells]=voronoin(a,{'Qbb','Qz'});out=struct('vertices',v,'cells',{cells});
    case 'orientation2d'
      finite(a,'point A');finite(b,'point B');finite(c,'point C');
      if(numel(a)!=2||numel(b)!=2||numel(c)!=2),error('GXTXT:Numeric:DimensionMismatch','orientation2d requires three 2D points');endif
      signed=(b(1)-a(1))*(c(2)-a(2))-(b(2)-a(2))*(c(1)-a(1));out=struct('signed_area_twice',signed,'sign',sign(signed));
    case 'orientation3d'
      finite(a,'tetrahedron');if(numel(a)!=12),error('GXTXT:Numeric:DimensionMismatch','orientation3d requires four 3D points as 12 coordinates');endif
      t=reshape(a,3,4)';signed=det([t(2,:)-t(1,:);t(3,:)-t(1,:);t(4,:)-t(1,:)]);out=struct('signed_volume_sixfold',signed,'sign',sign(signed));
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown geometry action');
  endswitch
endfunction
function out=vtk_geometry_file_action(action,path,origin,normal,opts)
  processing=any(strcmp(action,{'mesh_smooth','mesh_remesh','mesh_boolean'}));
  if(!processing)
    origin=vec3(origin,'origin');normal=vec3(normal,'normal');if(norm(normal)<1e-12),error('GXTXT:Numeric:DegenerateFrame','normal is zero');endif;normal=normal/norm(normal);
  endif
  if(!isfile(path)),error('GXTXT:Numeric:MissingSource','geometry payload is missing');endif
  helper=fullfile(fileparts(mfilename('fullpath')),'gxtxt_geometry_cut_v1.py');
  request_path=[tempname() '.json'];result_path=[tempname() '.json'];
  if(processing)
    output_path=option(opts,'output_path','');if(isempty(output_path)||!ischar(output_path)),error('GXTXT:Numeric:InvalidArguments','mesh processing requires output_path');endif
    request=struct('action',action,'path',path,'second_path',origin,'output_path',output_path,'method',option(opts,'method',''),'iterations',option(opts,'iterations',2),'format',option(opts,'format',''),'sha256',option(opts,'sha256',''));
  else
    request=struct('action',action,'path',path,'origin',origin,'normal',normal,'format',option(opts,'format',''),'sha256',option(opts,'sha256',''));
  endif
  unwind_protect
    fid=fopen(request_path,'w');if(fid<0),error('GXTXT:Numeric:IO','cannot write geometry request');endif
    fprintf(fid,'%s',jsonencode(request));fclose(fid);
    executable=getenv('GXTXT_PYTHON_EXECUTABLE');if(isempty(executable)),executable='python3';endif
    command=[shell_quote(executable) ' ' shell_quote(helper) ' ' shell_quote(request_path) ' ' shell_quote(result_path)];
    [status,diagnostic]=system(command);
    if(status!=0),error('GXTXT:Numeric:GeometryBackend','VTK section failed: %s',strtrim(diagnostic));endif
    out=jsondecode(fileread(result_path));
    if(isfield(out,'error')),error('GXTXT:Numeric:GeometryBackend','%s',out.error);endif
  unwind_protect_cleanup
    if(isfile(request_path)),unlink(request_path);endif
    if(isfile(result_path)),unlink(result_path);endif
  end_unwind_protect
endfunction
function q=shell_quote(s),q=['''' strrep(s,'''','''"''"''') ''''];endfunction
function v=ternary(condition,a,b),if(condition),v=a;else,v=b;endif;endfunction
function tree=build_kdtree(points,indices,depth)
  if(isempty(indices)),tree=[];return;endif
  axis=mod(depth-1,columns(points))+1;[~,order]=sort(points(indices,axis));indices=indices(order);mid=ceil(numel(indices)/2);
  tree=struct('index',indices(mid),'axis',axis,'left',build_kdtree(points,indices(1:mid-1),depth+1), ...
    'right',build_kdtree(points,indices(mid+1:end),depth+1));
endfunction
function [best,d2]=query_kdtree(tree,points,query,best,d2)
  if(isempty(tree)),return;endif
  candidate=sum((points(tree.index,:)-query).^2);if(candidate<d2),d2=candidate;best=tree.index;endif
  delta=query(tree.axis)-points(tree.index,tree.axis);
  if(delta<0),near=tree.left;far=tree.right;else,near=tree.right;far=tree.left;endif
  [best,d2]=query_kdtree(near,points,query,best,d2);
  if(delta^2<=d2),[best,d2]=query_kdtree(far,points,query,best,d2);endif
endfunction
function d=point_triangle_distance(P,A,B,C)
  u=B-A;v=C-A;n=cross(u,v);if(norm(n)<1e-14),error('GXTXT:Numeric:DegenerateTriangle','triangle has zero area');endif
  G=[dot(u,u),dot(u,v);dot(u,v),dot(v,v)];w=(P-A)*[u;v]'/G;
  projected=P-((P-A)*n')/(dot(n,n))*n;
  inside=w(:,1)>=0&w(:,2)>=0&sum(w,2)<=1;
  d=Inf(rows(P),1);d(inside)=sqrt(sum((P(inside,:)-projected(inside,:)).^2,2));
  edges={A,B;B,C;C,A};
  for j=1:3
    X=edges{j,1};Y=edges{j,2};h=Y-X;t=max(0,min(1,((P-X)*h')/dot(h,h)));d=min(d,sqrt(sum((P-(X+t*h)).^2,2)));
  endfor
endfunction
function out=sparse_action(action,a,b,c,opts)
  switch(action)
    case 'construct'
      finite(a,'triplets');finite(b,'shape');if(columns(a)!=3||numel(b)!=2),error('GXTXT:Numeric:DimensionMismatch','triplets N by 3 and shape [rows columns] required');endif
      M=sparse(a(:,1),a(:,2),a(:,3),b(1),b(2));
      [i,j,v]=find(M);out=struct('row',i,'column',j,'value_real',real(v),'value_imaginary',imag(v),'nonzeros',nnz(M),'shape',size(M));
    case {'matvec','solve','least_squares','eigen_subset'}
      if(isstruct(a))
        required={'row','column','value_real','value_imaginary','shape'};
        for k=1:numel(required),if(!isfield(a,required{k})),error('GXTXT:Numeric:InvalidSparse','missing sparse field');endif;endfor
        M=sparse(a.row,a.column,complex(a.value_real,a.value_imaginary),a.shape(1),a.shape(2));
      else,finite(a,'matrix');M=sparse(a);endif
      if(strcmp(action,'matvec')),finite(b,'vector');out=value(M*b);
      elseif(strcmp(action,'solve')),finite(b,'right-hand side');x=M\b;out=value(x);out.residual_norm=norm(M*x-b);
      elseif(strcmp(action,'least_squares')),finite(b,'right-hand side');x=M\b;out=value(x);out.residual_norm=norm(M*x-b);
      else,k=option(opts,'count',min(6,rows(M)-1));[V,D]=eigs(M,k,option(opts,'which','lm'));out=struct('eigenvalues_real',real(diag(D)),'eigenvalues_imaginary',imag(diag(D)),'eigenvectors_real',real(V),'eigenvectors_imaginary',imag(V));endif
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown sparse action');
  endswitch
endfunction
function out=equations_action(action,a,b,c,opts)
  if(!isa(a,'function_handle')),error('GXTXT:Numeric:CallbackRequired','equation residual requires a function handle');endif
  if(strcmp(action,'continuation'))
    finite(b,'initial point');finite(c,'continuation parameters');x=b(:);solutions=zeros(numel(x),numel(c));residuals=zeros(numel(c),1);statuses=zeros(numel(c),1);
    for k=1:numel(c)
      parameter=c(k);[x,f,info]=fsolve(@(state) a(state,parameter),x,optimset('TolX',option(opts,'tolerance',1e-8),'TolFun',option(opts,'tolerance',1e-8),'MaxIter',option(opts,'max_iterations',200)));
      solutions(:,k)=x;residuals(k)=norm(f);statuses(k)=info;
    endfor
    out=struct('parameters',c(:),'solutions',solutions,'residual_norm',residuals,'status',statuses,'converged',statuses>0);return;
  endif
  if(strcmp(action,'solve')),initials=b(:).';elseif(strcmp(action,'multiple_start')),initials=b;else,error('GXTXT:Numeric:UnknownOperation','unknown equation action');endif
  if(strcmp(action,'solve')),initials=initials(:).';endif
  solutions=cell(1,rows(initials));residuals=zeros(rows(initials),1);infos=zeros(rows(initials),1);
  for k=1:rows(initials)
    solver_opts=optimset('TolX',option(opts,'tolerance',1e-8),'TolFun',option(opts,'tolerance',1e-8),'MaxIter',option(opts,'max_iterations',200));
    if(isfield(opts,'jacobian'))
      if(!isa(opts.jacobian,'function_handle')),error('GXTXT:Numeric:InvalidArguments','jacobian must be a function handle');endif
      solver_opts=optimset(solver_opts,'Jacobian','on');fun=@(x) residual_with_jacobian(a,opts.jacobian,x);
    else fun=a;endif
    [x,f,info]=fsolve(fun,initials(k,:)',solver_opts);
    solutions{k}=x(:);residuals(k)=norm(f);infos(k)=info;
  endfor
  out=struct('solutions',{solutions},'residual_norm',residuals,'status',infos,'converged',infos>0);
endfunction
function [residual,J]=residual_with_jacobian(fun,jac,x),residual=fun(x);J=jac(x);endfunction
function out=variational_action(action,a,b,c,opts)
  if(!isa(a,'function_handle')),error('GXTXT:Numeric:CallbackRequired','variational action requires a Lagrangian/functional callback');endif
  switch(action)
    case {'action','functional'}
      finite(b,'coordinates');finite(c,'path');if(rows(c)!=numel(b)||any(diff(b(:))<=0)),error('GXTXT:Numeric:DimensionMismatch','path rows must match increasing parameter');endif
      velocity=gradient(c,b(:));L=zeros(numel(b),1);
      for k=1:numel(b),L(k)=a(b(k),c(k,:)',velocity(k,:)');endfor
      out=struct('action',trapz(b,L),'density',L,'velocity',velocity);
    case 'legendre'
      finite(b,'coordinates');finite(c,'velocity');h=sqrt(eps)*(1+abs(c(:)));p=zeros(numel(c),1);
      for k=1:numel(c),e=zeros(size(c));e(k)=h(k);p(k)=(a(b,c+e)-a(b,c-e))/(2*h(k));endfor
      out=struct('momentum',p,'hamiltonian',dot(p,c(:))-a(b,c));
    case 'first_variation'
      finite(b,'path');finite(c,'parameter');h=option(opts,'step',sqrt(eps));gradient_value=zeros(numel(b),1);
      for k=1:numel(b),e=zeros(size(b));e(k)=h;gradient_value(k)=(a(c,b+e)-a(c,b-e))/(2*h);endfor
      out=struct('gradient',reshape(gradient_value,size(b)));
    case 'euler_lagrange_residual'
      finite(b,'time');finite(c,'generalized coordinates');t=b(:);q=c;
      if(rows(q)!=numel(t)||numel(t)<3||any(diff(t)<=0)),error('GXTXT:Numeric:DimensionMismatch','time and generalized coordinates must match');endif
      v=zeros(size(q));for j=1:columns(q),v(:,j)=gradient(q(:,j),t);endfor
      dldq=zeros(size(q));dldv=zeros(size(q));
      for k=1:numel(t)
        for j=1:columns(q)
          h=sqrt(eps)*(1+abs(q(k,j)));e=zeros(columns(q),1);e(j)=h;
          dldq(k,j)=(a(t(k),q(k,:)'+e,v(k,:)')-a(t(k),q(k,:)'-e,v(k,:)'))/(2*h);
          h=sqrt(eps)*(1+abs(v(k,j)));e(j)=h;
          dldv(k,j)=(a(t(k),q(k,:)',v(k,:)'+e)-a(t(k),q(k,:)',v(k,:)'-e))/(2*h);
        endfor
      endfor
      residual=zeros(size(q));for j=1:columns(q),residual(:,j)=gradient(dldv(:,j),t)-dldq(:,j);endfor
      out=struct('residual',residual,'velocity',v,'momentum',dldv);
    case 'constrained'
      if(!isfield(opts,'constraints')),error('GXTXT:Numeric:InvalidArguments','constrained variation requires constraints struct');endif
      out=gxtxt_numeric_foundation_v1('constrained','solve',@(x) a(b,x),c,opts.constraints,opts);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown variational action');
  endswitch
endfunction
function out=statistics_action(action,a,b,c,opts)
  finite(a,'sample');x=a(:);
  switch(action)
    case 'confidence_interval'
      alpha=option(opts,'alpha',0.05);mu=mean(x);se=std(x)/sqrt(numel(x));q=tinv(1-alpha/2,numel(x)-1);
      out=struct('estimate',mu,'lower',mu-q*se,'upper',mu+q*se,'confidence',1-alpha);
    case 'robust_location'
      m=median(x);scale=max(1.4826*median(abs(x-m)),eps);constant=option(opts,'huber_constant',1.345);
      for k=1:100
        r=(x-m)/scale;weight=min(1,constant./max(abs(r),eps));next=sum(weight.*x)/sum(weight);
        if(abs(next-m)<1e-10*scale),m=next;break;endif;m=next;
      endfor
      out=struct('location',m,'scale',scale,'iterations',k,'method','Huber');
    case 'robust_regression'
      finite(a,'design matrix');finite(b,'response');X=a;y=b(:);if(rows(X)!=numel(y)),error('GXTXT:Numeric:DimensionMismatch','design rows must match response');endif
      beta=X\y;constant=option(opts,'huber_constant',1.345);
      for k=1:100
        residual=y-X*beta;scale=max(1.4826*median(abs(residual-median(residual))),eps);
        weight=min(1,constant*scale./max(abs(residual),eps));next=(X'*(weight.*X))\(X'*(weight.*y));
        if(norm(next-beta)<1e-10*max(1,norm(beta))),beta=next;break;endif;beta=next;
      endfor
      out=struct('coefficients',beta,'residual',y-X*beta,'iterations',k,'method','Huber IRLS');
    case 'covariance_diagnostics'
      finite(a,'observations');S=cov(a);out=struct('covariance',S,'eigenvalues',eig(S),'condition_number',cond(S),'rank',rank(S));
    case 'partial_correlation'
      finite(b,'second sample');finite(c,'control matrix');X=[x,b(:),c];P=pinv(cov(X));out=struct('correlation',-P(1,2)/sqrt(P(1,1)*P(2,2)));
    case 'multiple_testing'
      method=option(opts,'method','bonferroni');if(strcmp(method,'bonferroni')),p=min(1,x*numel(x));elseif(strcmp(method,'holm')),[s,ix]=sort(x);q=max(cummax((numel(x):-1:1)'.*s),0);p=zeros(size(x));p(ix)=min(1,q);elseif(strcmp(method,'bh')),[s,ix]=sort(x);q=flipud(cummin(flipud(numel(x)*s./(1:numel(x))')));p=zeros(size(x));p(ix)=min(1,q);else,error('GXTXT:Numeric:InvalidMethod','unknown correction');endif
      out=struct('adjusted_p',p);
    case 'bootstrap_ci'
      count=option(opts,'replicates',1000);seed=option(opts,'seed',[]);if(isempty(seed)||count<100),error('GXTXT:Numeric:SeedRequired','bootstrap requires seed and at least 100 replicates');endif
      previous=rng();unwind_protect
        rng(seed,'twister');estimates=zeros(count,1);for k=1:count,indices=randi(numel(x),numel(x),1);estimates(k)=mean(x(indices));endfor
      unwind_protect_cleanup,rng(previous);end_unwind_protect
      alpha=option(opts,'alpha',0.05);out=struct('estimate',mean(x),'lower',quantile(estimates,alpha/2),'upper',quantile(estimates,1-alpha/2),'replicates',count);
    case 'permutation_test'
      finite(b,'second sample');count=option(opts,'replicates',1000);seed=option(opts,'seed',[]);if(isempty(seed)||count<100),error('GXTXT:Numeric:SeedRequired','permutation test requires seed and at least 100 replicates');endif
      y=b(:);observed=mean(x)-mean(y);pooled=[x;y];extreme=0;previous=rng();unwind_protect
        rng(seed,'twister');for k=1:count,p=pooled(randperm(numel(pooled)));delta=mean(p(1:numel(x)))-mean(p(numel(x)+1:end));extreme+=(abs(delta)>=abs(observed));endfor
      unwind_protect_cleanup,rng(previous);end_unwind_protect
      out=struct('difference',observed,'p_value',(extreme+1)/(count+1),'replicates',count);
    case 'logistic_regression'
      finite(a,'design matrix');finite(b,'binary outcome');X=a;y=b(:);if(rows(X)!=numel(y)||any(y!=0&y!=1)),error('GXTXT:Numeric:DimensionMismatch','binary outcomes must match design rows');endif
      beta=zeros(columns(X),1);for k=1:100
        z=X*beta;p=1./(1+exp(-z));w=max(p.*(1-p),1e-10);gradient=X'*(y-p);H=X'*(w.*X);step=H\gradient;beta+=step;
        if(norm(step)<1e-9),break;endif
      endfor
      out=struct('coefficients',beta,'probability',1./(1+exp(-X*beta)),'iterations',k,'converged',norm(step)<1e-9);
    case 'glm'
      finite(a,'design matrix');finite(b,'response');X=a;y=b(:);
      if(rows(X)!=numel(y)),error('GXTXT:Numeric:DimensionMismatch','GLM design rows must match responses');endif
      family=option(opts,'family','poisson');
      if(strcmp(family,'binomial'))
        if(any(y!=0&y!=1)),error('GXTXT:Numeric:InvalidResponse','binomial GLM needs zero/one outcomes');endif
      elseif(strcmp(family,'poisson'))
        if(any(y<0)||any(y!=fix(y))),error('GXTXT:Numeric:InvalidResponse','Poisson GLM needs nonnegative counts');endif
      else,error('GXTXT:Numeric:InvalidMethod','GLM family must be binomial or poisson');endif
      beta=zeros(columns(X),1);tolerance=option(opts,'tolerance',1e-8);limit=option(opts,'max_iterations',100);
      for k=1:limit
        eta=X*beta;
        if(strcmp(family,'binomial')),mu=1./(1+exp(-max(-40,min(40,eta))));variance=max(mu.*(1-mu),1e-8);
        else,mu=exp(max(-40,min(40,eta)));variance=max(mu,1e-8);endif
        gradient=X'*(y-mu);hessian=X'*(variance.*X);
        if(rcond(hessian)<1e-12),error('GXTXT:Numeric:IllConditioned','GLM information matrix is singular');endif
        step=hessian\gradient;
        if(strcmp(family,'poisson'))
          current=sum(y.*eta-mu);scale=1;
          while(scale>1/1024)
            candidate=X*(beta+scale*step);next=sum(y.*candidate-exp(max(-40,min(40,candidate))));
            if(next>=current),break;endif;scale/=2;
          endwhile
          step*=scale;
        endif
        beta+=step;
        if(norm(step)<tolerance*max(1,norm(beta))),break;endif
      endfor
      eta=X*beta;if(strcmp(family,'binomial')),fitted=1./(1+exp(-eta));else,fitted=exp(eta);endif
      out=struct('coefficients',beta,'fitted_mean',fitted,'family',family,'link',ternary(strcmp(family,'binomial'),'logit','log'),'iterations',k,'converged',norm(step)<tolerance*max(1,norm(beta)),'score_norm',norm(X'*(y-fitted)));
    case 'survival_kaplan_meier'
      finite(a,'event times');finite(b,'event indicators');if(numel(a)!=numel(b)||any(b(:)!=0&b(:)!=1)),error('GXTXT:Numeric:DimensionMismatch','event times and censoring indicators must match');endif
      times=unique(a(:));survival=ones(numel(times),1);risk=numel(a);s=1;
      for k=1:numel(times),at=sum(a(:)==times(k));events=sum(a(:)==times(k)&b(:)==1);s*=1-events/risk;survival(k)=s;risk-=at;endfor
      out=struct('time',times,'survival',survival,'method','Kaplan-Meier');
    case 'kmeans'
      finite(a,'observations');clusters=option(opts,'clusters',2);seed=option(opts,'seed',[]);if(isempty(seed)),error('GXTXT:Numeric:SeedRequired','kmeans requires deterministic seed');endif
      pkg('load','statistics');previous=rng();unwind_protect
        rng(seed,'twister');[labels,centroids]=kmeans(a,clusters,'Replicates',option(opts,'replicates',5));
      unwind_protect_cleanup,rng(previous);end_unwind_protect
      out=struct('labels',labels,'centroids',centroids);
    otherwise,error('GXTXT:Numeric:UnknownOperation','unknown statistics action');
  endswitch
endfunction
