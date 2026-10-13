% MAGNETICS_API_v1 field and magnetic-circuit post-processing.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_magnetics_v1(family,action,a,b,c,opts)
  if(nargin<2||!ischar(family)||!ischar(action)),error('GXTXT:Magnetics:InvalidArguments','family and action required');endif
  if(nargin<3),a=[];endif;if(nargin<4),b=[];endif;if(nargin<5),c=[];endif;if(nargin<6),opts=struct();endif
  if(!isstruct(opts)),error('GXTXT:Magnetics:InvalidArguments','options must be a struct');endif
  family=lower(strtrim(family));action=lower(strtrim(action));
  switch(family)
    case 'coordinates',out=coordinate_action(action,a,b,c,opts);
    case 'field',out=field_action(action,a,b,c,opts);
    case 'integral',out=integral_action(action,a,b,c,opts);
    case 'constitutive',out=constitutive_action(action,a,b,c,opts);
    case 'circuit',out=circuit_action(action,a,b,c,opts);
    case 'energy',out=energy_action(action,a,b,c,opts);
    case 'bh',out=bh_action(action,a,b,c,opts);
    case 'loss',out=loss_action(action,a,b,c,opts);
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown magnetics family');
  endswitch
endfunction
function v=opt(s,k,d),v=d;if(isfield(s,k)),v=s.(k);endif,endfunction
function valid(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Magnetics:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
function out=split(v)
  out=struct('value_real',real(v),'value_imaginary',imag(v));
endfunction
function vector3(x,name)
  valid(x,name);if(!ismatrix(x)||columns(x)!=3),error('GXTXT:Magnetics:DimensionMismatch','%s must be N by 3',name);endif
endfunction
function dimension=vector_components(x,name)
  valid(x,name);
  if(ismatrix(x)&&columns(x)==3),dimension=2;
  elseif(ndims(x)==4&&size(x,4)==3),dimension=4;
  else error('GXTXT:Magnetics:DimensionMismatch','%s must have three vector components',name);endif
endfunction
function v=field_cross(a,b,dimension)
  if(dimension==2),v=cross(a,b,2);else
    v=cat(4,a(:,:,:,2).*b(:,:,:,3)-a(:,:,:,3).*b(:,:,:,2),a(:,:,:,3).*b(:,:,:,1)-a(:,:,:,1).*b(:,:,:,3),a(:,:,:,1).*b(:,:,:,2)-a(:,:,:,2).*b(:,:,:,1));
  endif
endfunction
function out=coordinate_action(action,coordinates,components,c,opts)
  vector3(coordinates,'coordinates');
  switch(action)
    case 'cartesian_to_cylindrical'
      x=coordinates(:,1);y=coordinates(:,2);z=coordinates(:,3);theta=atan2(y,x);v=[hypot(x,y),theta,z];
      if(!isempty(components)),vector3(components,'components');w=[components(:,1).*cos(theta)+components(:,2).*sin(theta),-components(:,1).*sin(theta)+components(:,2).*cos(theta),components(:,3)];endif
    case 'cylindrical_to_cartesian'
      r=coordinates(:,1);theta=coordinates(:,2);z=coordinates(:,3);if(any(r<0)),error('GXTXT:Magnetics:InvalidCoordinates','cylindrical radius must be nonnegative');endif
      v=[r.*cos(theta),r.*sin(theta),z];
      if(!isempty(components)),vector3(components,'components');w=[components(:,1).*cos(theta)-components(:,2).*sin(theta),components(:,1).*sin(theta)+components(:,2).*cos(theta),components(:,3)];endif
    case 'cartesian_to_spherical'
      x=coordinates(:,1);y=coordinates(:,2);z=coordinates(:,3);rho=sqrt(x.^2+y.^2+z.^2);az=atan2(y,x);polar=atan2(hypot(x,y),z);v=[rho,polar,az];
      if(!isempty(components)),vector3(components,'components');w=[sum(components.*[sin(polar).*cos(az),sin(polar).*sin(az),cos(polar)],2),sum(components.*[cos(polar).*cos(az),cos(polar).*sin(az),-sin(polar)],2),sum(components.*[-sin(az),cos(az),zeros(size(az))],2)];endif
    case 'spherical_to_cartesian'
      rho=coordinates(:,1);polar=coordinates(:,2);az=coordinates(:,3);if(any(rho<0)),error('GXTXT:Magnetics:InvalidCoordinates','spherical radius must be nonnegative');endif
      v=rho.*[sin(polar).*cos(az),sin(polar).*sin(az),cos(polar)];
      if(!isempty(components)),vector3(components,'components');w=components(:,1).*[sin(polar).*cos(az),sin(polar).*sin(az),cos(polar)]+components(:,2).*[cos(polar).*cos(az),cos(polar).*sin(az),-sin(polar)]+components(:,3).*[-sin(az),cos(az),zeros(size(az))];endif
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown coordinate transform');
  endswitch
  out=split(v);if(!isempty(components)),out.components_real=real(w);out.components_imaginary=imag(w);endif
endfunction
function out=field_action(action,axes,field,query,opts)
  switch(action)
    case 'magnitude',dimension=vector_components(field,'field');out=struct('magnitude',sqrt(sum(abs(field).^2,dimension)));
    case 'phasor',dimension=vector_components(field,'field');out=struct('magnitude',sqrt(sum(abs(field).^2,dimension)),'phase_rad',angle(field),'real',real(field),'imaginary',imag(field),'conjugate_real',real(conj(field)),'conjugate_imaginary',imag(conj(field)));
    case 'dot'
      dimension=vector_components(axes,'first field');if(vector_components(field,'second field')!=dimension||!isequal(size(axes),size(field))),error('GXTXT:Magnetics:DimensionMismatch','vector fields must match');endif
      out=split(sum(conj(axes).*field,dimension));
    case 'cross'
      dimension=vector_components(axes,'first field');if(vector_components(field,'second field')!=dimension||!isequal(size(axes),size(field))),error('GXTXT:Magnetics:DimensionMismatch','vector fields must match');endif
      out=split(field_cross(axes,field,dimension));
    case 'time_average_power'
      dimension=vector_components(axes,'electric field');if(vector_components(field,'magnetic field')!=dimension||!isequal(size(axes),size(field))),error('GXTXT:Magnetics:DimensionMismatch','E and H vector fields must match');endif
      v=0.5*field_cross(axes,conj(field),dimension);out=split(v);out.active_power_density=real(v);out.reactive_power_density=imag(v);out.unit='W/m^2';
    case 'joule_loss'
      dimension=vector_components(axes,'electric field');if(vector_components(field,'current density')!=dimension||!isequal(size(axes),size(field))),error('GXTXT:Magnetics:DimensionMismatch','E and J must match');endif
      phasor=opt(opts,'phasor',false);factor=1;if(phasor),factor=0.5;endif
      out=struct('loss_density',factor*real(sum(axes.*conj(field),dimension)),'unit','W/m^3');
    case 'normal_component'
      dimension=vector_components(field,'field');if(vector_components(query,'normals')!=dimension||!isreal(query)||!isequal(size(field),size(query))),error('GXTXT:Magnetics:DimensionMismatch','real normals and field shape must match');endif
      lengths=sqrt(sum(query.^2,dimension));if(any(lengths(:)==0)),error('GXTXT:Magnetics:ZeroNorm','normal vector is zero');endif
      normals=query./lengths;normal=sum(field.*normals,dimension);out=split(normal);out.tangential_real=real(field-normal.*normals);out.tangential_imaginary=imag(field-normal.*normals);
    case 'sample'
      if(!iscell(axes)||!(numel(axes)==2||numel(axes)==3)),error('GXTXT:Magnetics:InvalidGrid','2D or 3D axes required');endif
      if(numel(axes)==3&&ndims(field)==4&&size(field,4)==3)
        out=struct();for j=1:3
          r=gxtxt_numeric_v1('foundation','grid','interpolate',axes,field(:,:,:,j),query,opts);
          out.(sprintf('component%d_real',j))=r.value_real;out.(sprintf('component%d_imaginary',j))=r.value_imaginary;
        endfor
      else
        out=gxtxt_numeric_v1('foundation','grid','interpolate',axes,field,query,opts);
      endif
    case {'gradient','divergence','curl','laplacian'}
      if(!iscell(axes)||numel(axes)!=3),error('GXTXT:Magnetics:InvalidGrid','three coordinate axes required');endif
      if(strcmp(action,'gradient'))
        r=gxtxt_numeric_v1('foundation','calculus','gradient_grid',axes,field,[],opts);out=r;return;
      endif
      if(strcmp(action,'laplacian'))
        if(ndims(field)!=3),error('GXTXT:Magnetics:DimensionMismatch','Laplacian requires a 3D scalar field');endif
        v=zeros(size(field));for k=1:3,v+=second_grid_axis(field,axes{k},k);endfor
        out=split(v);return;
      endif
      if(ndims(field)!=4||size(field,4)!=3),error('GXTXT:Magnetics:DimensionMismatch','vector field must be nx by ny by nz by 3');endif
      for j=1:3
        r=gxtxt_numeric_v1('foundation','calculus','gradient_grid',axes,field(:,:,:,j),[],opts);
        for k=1:3,d{j,k}=complex(r.(sprintf('axis%d_real',k)),r.(sprintf('axis%d_imaginary',k)));endfor
      endfor
      if(strcmp(action,'divergence')),v=d{1,1}+d{2,2}+d{3,3};else v=cat(4,d{3,2}-d{2,3},d{1,3}-d{3,1},d{2,1}-d{1,2});endif
      out=split(v);
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown field action');
  endswitch
endfunction
function second=second_grid_axis(values,x,axis)
  n=numel(x);if(n<3),error('GXTXT:Magnetics:InvalidGrid','Laplacian needs at least three points on every axis');endif
  second=zeros(size(values));index=repmat({':'},1,3);
  for j=1:n
    if(j==1),ids=[1 2 3];elseif(j==n),ids=[n-2 n-1 n];else ids=[j-1 j j+1];endif
    x1=x(ids(1));x2=x(ids(2));x3=x(ids(3));
    i1=index;i2=index;i3=index;at=index;i1{axis}=ids(1);i2{axis}=ids(2);i3{axis}=ids(3);at{axis}=j;
    second(at{:})=2*(values(i1{:})/((x1-x2)*(x1-x3))+values(i2{:})/((x2-x1)*(x2-x3))+values(i3{:})/((x3-x1)*(x3-x2)));
  endfor
endfunction
function out=integral_action(action,geometry,field,connectivity,opts)
  switch(action)
    case {'line','circulation','mmf'}
      r=gxtxt_numeric_v1('foundation','calculus','line_integral',geometry,field,[],opts);out=r;
    case {'surface_flux','flux'}
      r=gxtxt_numeric_v1('foundation','calculus','surface_flux',geometry,field,connectivity,opts);out=r;
    case 'power'
      r=gxtxt_numeric_v1('foundation','calculus','surface_flux',geometry,field,connectivity,opts);out=r;out.unit='W';
    case 'volume'
      r=gxtxt_numeric_v1('foundation','calculus','integrate3',geometry,field,[],opts);out=r;
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown integral action');
  endswitch
endfunction
function out=loss_action(action,a,b,c,opts)
  switch(action)
    case 'steinmetz'
      valid(a,'peak flux density');valid(b,'frequency');k=opt(opts,'k',[]);alpha=opt(opts,'alpha',[]);beta=opt(opts,'beta',[]);
      if(isempty(k)||isempty(alpha)||isempty(beta)||any(real(a(:))<0)||any(real(b(:))<=0)||k<=0||alpha<=0||beta<=0),error('GXTXT:Magnetics:InvalidMaterial','positive empirical k alpha beta and frequency required');endif
      out=struct('loss_density',k.*(b.^alpha).*(abs(a).^beta),'unit','W/m^3','method','steinmetz');
    case 'arbitrary_waveform'
      valid(a,'time');valid(b,'B waveform');t=a(:);B=b(:);if(numel(t)!=numel(B)||numel(t)<3||any(diff(t)<=0)||!isreal(B)),error('GXTXT:Magnetics:InvalidWaveform','real B waveform and increasing time required');endif
      ki=opt(opts,'ki',[]);alpha=opt(opts,'alpha',[]);beta=opt(opts,'beta',[]);
      if(isempty(ki)||isempty(alpha)||isempty(beta)||ki<=0||alpha<=0||beta<=0),error('GXTXT:Magnetics:InvalidMaterial','positive iGSE ki alpha beta required');endif
      span=max(B)-min(B);derivative=diff(B)./diff(t);T=t(end)-t(1);
      out=struct('loss_density',ki*span^(beta-alpha)*sum(abs(derivative).^alpha.*diff(t))/T,'unit','W/m^3','method','igse');
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown core loss action');
  endswitch
endfunction
function out=constitutive_action(action,field,mu_r,c,opts)
  mu0=4*pi*1e-7;
  if(strcmp(action,'vacuum_permeability')),out=struct('value',mu0,'unit','H/m');return;endif
  if(strcmp(action,'anisotropic_b_from_h'))
    vector3(field,'H vectors');valid(mu_r,'relative permeability tensor');
    if(!isequal(size(mu_r),[3 3])||norm(mu_r-mu_r','fro')>1e-9||min(real(eig(mu_r)))<=0),error('GXTXT:Magnetics:InvalidMaterial','anisotropic permeability must be positive Hermitian 3 by 3');endif
    out=split(mu0*field*mu_r.');out.permeability_unit='H/m';return;
  endif
  if(strcmp(action,'nonlinear_b_from_h'))
    valid(field,'H query');valid(mu_r,'H curve');valid(c,'B curve');
    if(numel(mu_r)!=numel(c)||any(diff(mu_r(:))<=0)||!isreal(mu_r)||!isreal(c)),error('GXTXT:Magnetics:InvalidMaterial','monotonic real H/B curve required');endif
    policy=opt(opts,'extrapolation','error');if(!any(strcmp(policy,{'error','linear','clamp'}))),error('GXTXT:Magnetics:InvalidPolicy','extrapolation must be error, linear or clamp');endif
    if(strcmp(policy,'error')&&any(field(:)<mu_r(1)|field(:)>mu_r(end))),error('GXTXT:Magnetics:Extrapolation','query outside declared B-H curve');endif
    query=field;if(strcmp(policy,'clamp')),query=max(mu_r(1),min(mu_r(end),field));endif
    if(strcmp(policy,'linear'))
      values=interp1(mu_r(:),c(:),query,opt(opts,'method','pchip'),'extrap');
    else,values=interp1(mu_r(:),c(:),query,opt(opts,'method','pchip'));endif
    out=split(values);return;
  endif
  valid(field,'field');valid(mu_r,'relative permeability');if(any(mu_r(:)==0)),error('GXTXT:Magnetics:InvalidMaterial','relative permeability cannot be zero');endif
  mu=mu0*mu_r;
  switch(action)
    case 'b_from_h',v=mu.*field;
    case 'h_from_b',v=field./mu;
    case 'permeability',v=mu;
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown constitutive action');
  endswitch
  out=split(v);out.permeability_unit='H/m';
endfunction
function out=circuit_action(action,a,b,c,opts)
  switch(action)
    case 'reluctance'
      valid(a,'length');valid(b,'area');valid(c,'relative permeability');if(any(real(a(:))<=0)||any(real(b(:))<=0)||any(c(:)==0)||any(imag(a(:))!=0)||any(imag(b(:))!=0)||isreal(c)&&any(c(:)<=0)),error('GXTXT:Magnetics:InvalidGeometry','positive real length/area and nonzero permeability required');endif
      v=a./(4*pi*1e-7*c.*b);out=split(v);out.unit='A/Wb';
    case 'permeance',valid(a,'reluctance');if(any(a(:)==0)),error('GXTXT:Magnetics:Singular','zero reluctance');endif;out=split(1./a);out.unit='Wb/A';
    case 'series_reluctance',valid(a,'reluctances');out=split(sum(a(:)));out.unit='A/Wb';
    case 'parallel_reluctance',valid(a,'reluctances');if(any(a(:)==0)),error('GXTXT:Magnetics:Singular','zero reluctance');endif;out=split(1/sum(1./a(:)));out.unit='A/Wb';
    case 'mmf',valid(a,'turns');valid(b,'current');out=split(a.*b);out.unit='A_turn';
    case 'flux_linkage',valid(a,'turns');valid(b,'flux');out=split(a.*b);out.unit='Wb_turn';
    case 'inductance',valid(a,'flux linkage');valid(b,'current');if(any(b(:)==0)),error('GXTXT:Magnetics:Singular','zero current');endif;out=split(a./b);out.unit='H';
    case 'mutual_inductance',valid(a,'linked flux');valid(b,'other coil turns');valid(c,'source current');if(any(c(:)==0)),error('GXTXT:Magnetics:Singular','zero source current');endif;out=split(a.*b./c);out.unit='H';
    case 'coupling',valid(a,'mutual inductance');valid(b,'first self inductance');valid(c,'second self inductance');if(any(b(:)<=0)||any(c(:)<=0)),error('GXTXT:Magnetics:InvalidInductance','self inductances must be positive');endif;v=a./sqrt(b.*c);if(any(abs(v(:))>1+1e-9)),error('GXTXT:Magnetics:InconsistentInductance','passive coupling magnitude exceeds one');endif;out=split(v);
    case 'inductance_matrix'
      valid(a,'self inductances');valid(b,'mutual inductance');if(numel(a)!=2||!isscalar(b)||any(a(:)<=0)||abs(b)>sqrt(prod(a(:)))),error('GXTXT:Magnetics:InvalidInductance','two positive self inductances and physically bounded mutual inductance required');endif
      out=split([a(1),b;b,a(2)]);out.unit='H';
    case 'energy_derived_inductance'
      valid(a,'magnetic energy');valid(b,'current');if(any(a(:)<0)||any(b(:)==0)),error('GXTXT:Magnetics:InvalidInductance','nonnegative energy and nonzero current required');endif
      out=split(2*a./(b.^2));out.unit='H';
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown circuit action');
  endswitch
endfunction
function out=energy_action(action,B,H,geometry,opts)
  if(strcmp(action,'electric_density'))
    valid(B,'electric field');valid(H,'permittivity');
    epsilon=H;phasor=opt(opts,'phasor',false);factor=0.5;if(phasor),factor=0.25;endif
    if(columns(B)==3),density=factor*real(epsilon.*sum(abs(B).^2,2));else,density=factor*real(epsilon.*abs(B).^2);endif
    out=struct('energy_density',density,'unit','J/m^3');return;
  endif
  if(any(strcmp(action,{'force_from_gradient','torque_from_gradient'})))
    valid(B,'energy or coenergy gradient');out=split(-B);if(strcmp(action,'force_from_gradient')),out.unit='N';else,out.unit='N m';endif;return;
  endif
  valid(B,'B');valid(H,'H');
  switch(action)
    case 'density'
      if(!isequal(size(B),size(H))),error('GXTXT:Magnetics:DimensionMismatch','B and H shape differ');endif
      phasor=opt(opts,'phasor',false);if(!phasor&&(!isreal(B)||!isreal(H))),error('GXTXT:Magnetics:PhasorDeclaration','complex B/H energy requires phasor=true');endif
      factor=0.5;if(phasor),factor=0.25;endif
      if(ndims(B)==4&&size(B,4)==3),v=factor*real(sum(B.*conj(H),4));
      elseif(ismatrix(B)&&columns(B)==3),v=factor*real(sum(B.*conj(H),2));
      else v=factor*real(B.*conj(H));endif
      out=struct('energy_density',v,'unit','J/m^3');
    case 'integrated'
      density=energy_action('density',B,H,[],opts);r=gxtxt_numeric_v1('foundation','calculus','integrate3',geometry,density.energy_density,[],opts);out=r;out.unit='J';
    case 'coenergy_curve'
      if(!isvector(B)||!isvector(H)||numel(B)!=numel(H)||numel(B)<2),error('GXTXT:Magnetics:DimensionMismatch','B-H curve requires matching vectors');endif
      out=struct('coenergy_density',trapz(H(:),B(:)),'unit','J/m^3');
    case 'energy_curve'
      if(!isvector(B)||!isvector(H)||numel(B)!=numel(H)||numel(B)<2),error('GXTXT:Magnetics:DimensionMismatch','B-H curve requires matching vectors');endif
      out=struct('energy_density',trapz(B(:),H(:)),'unit','J/m^3');
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown energy action');
  endswitch
endfunction
function out=bh_action(action,H,B,c,opts)
  valid(H,'H');valid(B,'B');H=H(:);B=B(:);if(numel(H)!=numel(B)||numel(H)<2||!isreal(H)||!isreal(B)),error('GXTXT:Magnetics:DimensionMismatch','real B-H vectors must match');endif
  switch(action)
    case 'loop_area',if(H(1)!=H(end)||B(1)!=B(end)),H(end+1)=H(1);B(end+1)=B(1);endif;out=struct('area',abs(sum((B(1:end-1)+B(2:end))/2.*diff(H))),'unit','J/m^3');
    case 'remanence',indices=find(H(1:end-1).*H(2:end)<=0);if(isempty(indices)),error('GXTXT:Magnetics:NoCrossing','H curve does not cross zero');endif;out=struct('values',cross_values(H,B,indices),'unit','T');
    case 'coercivity',indices=find(B(1:end-1).*B(2:end)<=0);if(isempty(indices)),error('GXTXT:Magnetics:NoCrossing','B curve does not cross zero');endif;out=struct('values',cross_values(B,H,indices),'unit','A/m');
    case 'differential_permeability'
      if(any(diff(H)==0)),error('GXTXT:Magnetics:InvalidCurve','repeated H values prevent derivative');endif
      out=struct('value',gradient(B,H),'unit','H/m');
    case 'incremental_permeability'
      H0=opt(opts,'bias_h',[]);span=opt(opts,'delta_h',[]);
      if(isempty(H0)||isempty(span)||span<=0),error('GXTXT:Magnetics:InvalidCurve','bias_h and positive delta_h required');endif
      [hs,order]=sort(H);bs=B(order);if(any(diff(hs)<=0)),error('GXTXT:Magnetics:InvalidCurve','H values must be distinct');endif
      if(H0-span<hs(1)||H0+span>hs(end)),error('GXTXT:Magnetics:Extrapolation','incremental interval outside B-H curve');endif
      out=struct('value',(interp1(hs,bs,H0+span)-interp1(hs,bs,H0-span))/(2*span),'unit','H/m');
    case 'interpolate'
      valid(c,'query H');[hs,order]=sort(H);bs=B(order);if(any(diff(hs)<=0)),error('GXTXT:Magnetics:InvalidCurve','H values must be distinct');endif
      if(any(c(:)<hs(1)|c(:)>hs(end))),error('GXTXT:Magnetics:Extrapolation','query H outside observed curve');endif
      out=struct('B',interp1(hs,bs,c,opt(opts,'method','pchip')),'unit','T');
    case 'cycle_align'
      if(numel(H)<3),error('GXTXT:Magnetics:InvalidCurve','cycle requires at least three points');endif
      [~,start]=max(H);order=[start:numel(H),1:start-1];out=struct('H',H(order),'B',B(order),'start_index',start);
    case 'saturation_indicator',out=struct('maximum_abs_B',max(abs(B)),'maximum_abs_H',max(abs(H)),'unit_B','T','unit_H','A/m');
    otherwise,error('GXTXT:Magnetics:UnknownOperation','unknown B-H action');
  endswitch
endfunction
function values=cross_values(x,y,idx)
  values=y(idx)-x(idx).*(y(idx+1)-y(idx))./(x(idx+1)-x(idx));
endfunction
