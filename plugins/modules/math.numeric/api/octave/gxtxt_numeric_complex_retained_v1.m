% A display projection keeps the complete complex model and scientific identity.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_complex_retained_v1(action,saved,varargin)
  required={'schema','kind','recipe','parameters','declaration_sha256','channel_id','projection'};
  if(!isstruct(saved)||!isscalar(saved)||!isempty(setdiff(fieldnames(saved),[required,{'reference'}]))||!all(isfield(saved,required))||!strcmp(saved.schema,'gxtxt.complex_projection_model.v1')||!strcmp(saved.kind,'complex_projection'))
    fail('One versioned retained complex projection is required');
  endif
  model=gxtxt_numeric_complex_v1('compose',saved.recipe);
  if(!ischar(saved.declaration_sha256)||!strcmp(saved.declaration_sha256,model.declaration_sha256)),fail('Retained complex declaration identity changed');endif
  model.parameters=saved.parameters(:);model.physical_model.parameters=model.parameters;
  model=gxtxt_numeric_complex_v1('validate',model);
  if(!ischar(saved.channel_id)),fail('A physical channel identity is required');endif
  channel=find(strcmp(saved.channel_id,model.channel_ids));
  if(numel(channel)!=1||!ischar(saved.projection)||!any(strcmp(saved.projection,{'real','imaginary','magnitude','db20'}))),fail('Choose one captured complex channel and real, imaginary, magnitude or db20 projection');endif
  reference=1;unit=model.channel_units{channel};
  if(strcmp(saved.projection,'db20'))
    if(!isfield(saved,'reference')||!isstruct(saved.reference)||!isscalar(saved.reference)||!isempty(setxor(fieldnames(saved.reference),{'value','unit'}))||!strcmp(saved.reference.unit,unit)||!isnumeric(saved.reference.value)||!isreal(saved.reference.value)||!isscalar(saved.reference.value)||!isfinite(saved.reference.value)||saved.reference.value<=0),fail('db20 projection requires a positive physical reference in the exact channel unit');endif
    reference=saved.reference.value;unit='dB';
  elseif(isfield(saved,'reference')),fail('A linear component or magnitude cannot acquire an undeclared dB reference');endif
  if(strcmp(action,'validate')),out=struct('model',model,'channel',channel,'projection',saved.projection,'reference',reference,'response_unit',unit);return;endif
  if(!strcmp(action,'query')||numel(varargin)!=2),fail('Unknown retained complex action');endif
  query=varargin{1};options=varargin{2};
  if(!isstruct(options)||!isscalar(options)||!isempty(setdiff(fieldnames(options),{'domain','orientation','translation','extrapolation','derivative','tangent_floors'}))),fail('Unknown complex retained query option');endif
  if(isfield(options,'orientation')&&!strcmp(options.orientation,'y_of_x')),fail('Complex frequency response projection requires Y(frequency) orientation');endif
  if(isfield(options,'translation')&&(!isnumeric(options.translation)||!isreal(options.translation)||numel(options.translation)!=2||any(options.translation(:)!=0))),fail('Complex frequency response projection requires untranslated physical coordinates');endif
  if(!isfield(options,'domain')||!isnumeric(options.domain)||!isreal(options.domain)||numel(options.domain)!=2||any(!isfinite(options.domain(:)))||options.domain(1)<=0||options.domain(1)>=options.domain(2)),fail('A finite positive increasing frequency domain is required');endif
  if(!isnumeric(query)||!isreal(query)||!isvector(query)||isempty(query)||numel(query)>65536||any(!isfinite(query(:)))||any(query(:)<=0)),fail('Complex projection queries require1..65536 positive finite physical frequencies');endif
  domain=gxtxt_numeric_query_double_v1(options.domain(:));query=gxtxt_numeric_query_double_v1(query(:));outside=query<domain(1)|query>domain(2);
  policy='error';if(isfield(options,'extrapolation')),policy=options.extrapolation;endif
  if(!ischar(policy)||!any(strcmp(policy,{'error','allow'}))),fail('Extrapolation must be error or explicit allow');endif
  if(any(outside)&&strcmp(policy,'error')),fail('Complex projection query exceeds the retained domain');endif
  derivative=true;if(isfield(options,'derivative')),derivative=options.derivative;endif
  if(!(isnumeric(derivative)||islogical(derivative))||!isreal(derivative)||!isscalar(derivative)||!ismember(derivative,[0,1])),fail('Derivative must be boolean');endif
  floors=[0;0];if(isfield(options,'tangent_floors')),floors=options.tangent_floors;endif
  if(!isnumeric(floors)||!isreal(floors)||numel(floors)!=2||any(!isfinite(floors(:)))||any(floors(:)<0)),fail('Two finite nonnegative physical tangent floors are required');endif
  floors=gxtxt_numeric_query_double_v1(floors(:));
  evaluation=gxtxt_numeric_complex_v1('evaluate',model,query,struct('predictor_derivative',derivative));
  z=evaluation.predicted(:,channel);amplitude=abs(z);valid=true(size(query));regular=false(size(query));slope=NaN(size(query));
  if(derivative)
    a=2*channel-1;b=a+1;dz=complex(evaluation.predictor_derivative(:,a),evaluation.predictor_derivative(:,b));
    regular=logical(evaluation.derivative_valid(:,a))&logical(evaluation.derivative_valid(:,b));
  endif
  switch(saved.projection)
    case 'real'
      value=real(z);if(derivative),slope=real(dz);regular=logical(evaluation.derivative_valid(:,a));endif
    case 'imaginary'
      value=imag(z);if(derivative),slope=imag(dz);regular=logical(evaluation.derivative_valid(:,b));endif
    case {'magnitude','db20'}
      value=amplitude;
      if(derivative)
        regular=regular&amplitude>0;
        slope(regular)=real(conj(z(regular))./amplitude(regular).*dz(regular));
      endif
      if(strcmp(saved.projection,'db20'))
        valid=amplitude>0;value=NaN(size(query));value(valid)=20*(log10(amplitude(valid))-log10(reference));
        slope(regular)=20/log(10)*slope(regular)./amplitude(regular);
      endif
  endswitch
  valid=valid&isfinite(value);regular=regular&valid&isfinite(slope);
  inverse_valid=regular&abs(slope)>floors(2);derivative_valid=regular&1>floors(1);
  inverse=NaN(size(query));inverse(inverse_valid)=1./slope(inverse_valid);inverse_valid=inverse_valid&isfinite(inverse);inverse(!inverse_valid)=NaN;
  tangent_y=slope;tangent_y(!regular)=NaN;slope(!derivative_valid)=NaN;
  out=struct('schema','gxtxt.model_query.v1','query',query,'predicted',value,'points',[query,value],...
    'valid',valid,'parametric',false,'domain',domain,'extrapolation',policy,'is_extrapolated',outside,...
    'orientation','y_of_x','translation',[0;0],'derivative',slope,'derivative_valid',derivative_valid,...
    'inverse_derivative',inverse,'inverse_derivative_valid',inverse_valid,'tangent_x',ones(size(query)),...
    'tangent_y',tangent_y,'tangent_floors',floors,'derivative_method','shared_complex_coordinate_AD_and_explicit_projection_chain_rule',...
    'query_unit',model.predictor_unit,'response_unit',unit,'channel_id',saved.channel_id,'projection',saved.projection,...
    'declaration_sha256',model.declaration_sha256,'fit_performed',false,'uncertainty_available',false);
endfunction
function fail(message),error('GXTXT:Numeric:ComplexRetained','%s',message);endfunction
