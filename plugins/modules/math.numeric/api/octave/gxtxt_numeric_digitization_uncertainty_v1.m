% Pixel/calibration propagation through the existing uncertainty owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_digitization_uncertainty_v1(action,varargin)
  switch(action)
    case 'propagate',out=propagate(varargin{1},varargin{2});
    case 'covariance',out=materialize(varargin{1},varargin{2});
    otherwise,error('GXTXT:Numeric:Digitization','Unknown digitization uncertainty action');
  endswitch
endfunction
function out=propagate(lin,spec)
  closed(lin,{'schema','coordinates','point_jacobian','calibration_jacobian','coordinate_units','calibration_ids','calibration_units','mapping','jacobian_method','condition_number'});
  if(!strcmp(lin.schema,'gxtxt.digitization_linearization.v1')),fail('Unknown calibration linearization');endif
  xy=real_values(lin.coordinates);jp=real_values(lin.point_jacobian);jc=real_values(lin.calibration_jacobian);
  n=rows(xy);m=columns(jc);
  if(n<1||n>4096||columns(xy)!=2||!isequal(size(jp),[2*n,2])||rows(jc)!=2*n||m<1||m>32),fail('Bounded physical coordinates and aligned point/calibration Jacobians are required');endif
  units=texts(lin.coordinate_units,2);ids=texts(lin.calibration_ids,m);calunits=texts(lin.calibration_units,m);
  if(numel(unique(ids))!=m),fail('Calibration input identities must be unique');endif
  closed(spec,{'mode','pixel_distribution','pixel_scale','calibration_standard_uncertainty','override_standard_uncertainty','rationale'});
  mode=option(spec,'mode','pixel_calibration');rationale=option(spec,'rationale','');
  if(!ischar(rationale)||isempty(strtrim(rationale))||numel(rationale)>2048),fail('Document the uncertainty distribution/calibration evidence or override rationale');endif
  local=zeros(2*n,2);shared=zeros(2*n,m);sigma=zeros(n,2);pixel_sigma=zeros(n,2);blocks=zeros(n,3);
  if(strcmp(mode,'pixel_calibration'))
    distribution=option(spec,'pixel_distribution','');scale=real_values(option(spec,'pixel_scale',[]));cal=real_values(option(spec,'calibration_standard_uncertainty',[]));
    if(numel(scale)!=2||any(scale(:)<=0)||numel(cal)!=m||any(cal(:)<0)||isfield(spec,'override_standard_uncertainty')),fail('Declare two positive pixel scales and aligned nonnegative calibration standard uncertainties');endif
    if(strcmp(distribution,'rectangular_full_width')),pixel=scale(:)/sqrt(12);
    elseif(strcmp(distribution,'normal_standard_uncertainty')),pixel=scale(:);
    else,fail('Pixel size is not sigma: declare rectangular full width or normal standard uncertainty');endif
    cal=cal(:);
    for i=1:n
      rows_i=2*i-1:2*i;point=jp(rows_i,:);calibration=jc(rows_i,:);
      % One call yields independent pixel, shared calibration and total blocks.
      augmented=[point,zeros(2,m);zeros(2,2),calibration;point,calibration];
      propagated=gxtxt_numeric_v1('propagate_uncertainty',augmented,[pixel;cal]);
      c=propagated.covariance(5:6,5:6);sigma(i,:)=propagated.standard_uncertainty(5:6).';pixel_sigma(i,:)=propagated.standard_uncertainty(1:2).';
      blocks(i,:)=[c(1,1),c(1,2),c(2,2)];local(rows_i,:)=point.*pixel.';shared(rows_i,:)=calibration.*cal.';
    endfor
    declaration=struct('mode',mode,'pixel_distribution',distribution,'pixel_scale',scale(:).','pixel_standard_uncertainty',pixel.','calibration_standard_uncertainty',cal.','rationale',rationale);
  elseif(strcmp(mode,'physical_override'))
    for key={'pixel_distribution','pixel_scale','calibration_standard_uncertainty'},if(isfield(spec,key{1})),fail('Physical override replaces the declared error model; mixed pixel/calibration fields are forbidden');endif;endfor
    values=real_values(option(spec,'override_standard_uncertainty',[]));
    if(numel(values)==2),values=repmat(values(:).',n,1);endif
    if(!isequal(size(values),[n,2])||any(values(:)<=0)),fail('Override requires positive physical X/Y standard uncertainties');endif
    for i=1:n
      propagated=gxtxt_numeric_v1('propagate_uncertainty',eye(2),values(i,:));
      sigma(i,:)=propagated.standard_uncertainty.';pixel_sigma(i,:)=sigma(i,:);
      blocks(i,:)=[propagated.covariance(1,1),0,propagated.covariance(2,2)];local(2*i-1:2*i,:)=diag(values(i,:));
    endfor
    distribution='declared_independent_physical_standard_uncertainty';
    declaration=struct('mode',mode,'pixel_distribution',distribution,'override_standard_uncertainty',values,'rationale',rationale);
  else,fail('Choose pixel_calibration or explicit physical_override');endif
  if(any(!isfinite(sigma(:)))||any(sigma(:)<=0)||any(!isfinite(blocks(:)))||any(!isfinite(local(:)))||any(!isfinite(shared(:)))),fail('Propagated physical standard uncertainty must be finite and positive');endif
  correlation=(blocks(:,2)./sigma(:,1))./sigma(:,2);
  out=struct('schema','gxtxt.digitization_uncertainty.v1','numeric_api','NUMERIC_API_v1','operation','digitization_uncertainty',...
    'coordinates',xy,'coordinate_units',{units},'point_count',n,'calibration_ids',{ids},'calibration_units',{calunits},...
    'standard_uncertainty',sigma,'independent_standard_uncertainty',pixel_sigma,'covariance_blocks',blocks,...
    'independent_factor',local,'shared_factor',shared,'declaration',declaration,...
    'source_linearization_sha256',hash('sha256',jsonencode(lin)));
  out.summary=struct('schema','gxtxt.digitization_uncertainty_summary.v1','numeric_api','NUMERIC_API_v1',...
    'operation','digitization_uncertainty','point_count',n,'calibration_input_count',m,'coordinate_units',{units},...
    'mode',mode,'pixel_distribution',distribution,'propagation','first_order_linear_propagation',...
    'has_shared_calibration',logical(any(shared(:)!=0)),'has_xy_correlation',logical(any(abs(correlation)>64*eps)),...
    'maximum_absolute_xy_correlation',max(abs(correlation)),'correlation_roundoff_tolerance',64*eps,...
    'source_linearization_sha256',out.source_linearization_sha256,'rationale',rationale);
  out.state_sha256=digest(out);out.summary.state_sha256=out.state_sha256;
endfunction
function out=materialize(state,axis)
  state=validate(state);n=state.point_count;m=columns(state.shared_factor);
  if(n>512),fail('Full calibration covariance is bounded to512 points; retain shared factors for larger sources');endif
  if(!ischar(axis)||!any(strcmp(axis,{'x','y','xy'}))),fail('Choose x, y or interleaved xy covariance');endif
  factor=zeros(2*n,2*n+m);
  for i=1:n,r=2*i-1:2*i;factor(r,r)=state.independent_factor(r,:);endfor
  factor(:,2*n+1:end)=state.shared_factor;
  if(strcmp(axis,'x')),positions=1:2:2*n;elseif(strcmp(axis,'y')),positions=2:2:2*n;else,positions=1:2*n;endif
  propagated=gxtxt_numeric_v1('propagate_uncertainty',factor(positions,:),ones(2*n+m,1));
  out=struct('schema','gxtxt.digitization_covariance.v1','numeric_api','NUMERIC_API_v1','operation','digitization_covariance',...
    'axis',axis,'point_count',n,'coordinate_units',{state.coordinate_units},'covariance',propagated.covariance,...
    'standard_uncertainty',propagated.standard_uncertainty,'source_state_sha256',state.state_sha256,...
    'row_order','original_points_interleaved_xy_or_selected_axis','method',propagated.method);
endfunction
function state=validate(state)
  if(!isstruct(state)||numel(state)!=1||!isfield(state,'schema')||!strcmp(state.schema,'gxtxt.digitization_uncertainty.v1')||!isfield(state,'state_sha256')||!strcmp(state.state_sha256,digest(state))||!strcmp(state.summary.state_sha256,state.state_sha256)),fail('Retained digitization uncertainty identity changed');endif
  n=state.point_count;m=numel(state.calibration_ids);
  if(!isscalar(n)||n<1||n>4096||n!=fix(n)||m<1||m>32||!isequal(size(state.independent_factor),[2*n,2])||!isequal(size(state.shared_factor),[2*n,m])),fail('Retained uncertainty factor shape changed');endif
endfunction
function value=digest(s)
  ordered=struct();
  for key={'schema','numeric_api','operation','coordinates','coordinate_units','point_count','calibration_ids','calibration_units','standard_uncertainty','independent_standard_uncertainty','covariance_blocks','independent_factor','shared_factor','declaration','source_linearization_sha256','summary'}
    name=key{1};if(!isfield(s,name)),fail('Incomplete digitization uncertainty state');endif;ordered.(name)=s.(name);
  endfor
  if(isfield(ordered.summary,'state_sha256')),ordered.summary=rmfield(ordered.summary,'state_sha256');endif
  % Existing scalar transport encodes logical inputs as numeric0/1. Normalize
  % declared flags without changing scientific values or weakening other fields.
  for key={'has_shared_calibration','has_xy_correlation'}
    value=ordered.summary.(key{1});if(!isscalar(value)||!ismember(value,[0,1])),fail('Correlation flags must be boolean');endif
    ordered.summary.(key{1})=logical(value);
  endfor
  value=hash('sha256',jsonencode(canonical(ordered)));
endfunction
function value=real_values(value)
  if(!isnumeric(value)||!isreal(value)||ndims(value)>2),fail('Real numerical arrays are required');endif
  if(isinteger(value)&&(any(value(:)>2^53)||any(value(:)<-2^53))),fail('Integer outside the exact binary64 range requires explicit conversion');endif
  value=double(value);if(any(!isfinite(value(:)))),fail('Finite numerical arrays are required');endif
endfunction
function values=texts(values,count)
  if(!iscellstr(values)||numel(values)!=count),fail('Explicit physical units and calibration identities are required');endif
  values=reshape(values,1,[]);for i=1:count,if(isempty(strtrim(values{i}))||numel(values{i})>256),fail('Empty or oversized identity/unit');endif;endfor
endfunction
function closed(s,allowed)
  if(!isstruct(s)||numel(s)!=1||any(!ismember(fieldnames(s),allowed))),fail('Unknown digitization contract field');endif
endfunction
function value=option(s,key,fallback)
  if(isfield(s,key)),value=s.(key);else,value=fallback;endif
endfunction
function fail(message),error('GXTXT:Numeric:Digitization',message);endfunction

function value=canonical(value)
  if(isstruct(value)),value=orderfields(value);for key=fieldnames(value).',name=key{1};value.(name)=canonical(value.(name));endfor
  elseif(iscell(value)),for k=1:numel(value),value{k}=canonical(value{k});endfor;endif
endfunction
