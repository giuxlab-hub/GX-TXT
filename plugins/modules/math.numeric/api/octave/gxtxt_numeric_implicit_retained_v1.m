% Retained branch adapter; equation, root and derivative owners are unchanged.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_implicit_retained_v1(action,saved,varargin)
  if(!isstruct(saved)||numel(saved)!=1),fail('One retained implicit branch is required');endif
  required={'schema','kind','recipe','parameters','declaration_sha256','equation_source_sha256','equation_binding_sha256','branch'};
  if(!isempty(setxor(fieldnames(saved),required))||!strcmp(saved.schema,'gxtxt.implicit_branch_model.v1')||!strcmp(saved.kind,'implicit_branch')),fail('Invalid retained implicit branch schema');endif
  model=gxtxt_numeric_implicit_v1('compose',saved.recipe);
  for pair={'declaration_sha256','declaration_sha256';'equation_source_sha256','source_sha256';'equation_binding_sha256','binding_sha256'}.'
    field=pair{1};target=pair{2};owner=model;if(!strcmp(field,'declaration_sha256')),owner=model.equation_model;endif
    if(!strcmp(saved.(field),owner.(target))),fail('Retained implicit declaration identity changed');endif
  endfor
  model.parameters=saved.parameters(:);model.equation_model.parameters=model.parameters;
  model=gxtxt_numeric_implicit_v1('validate',model);branch=saved.branch;
  if(!isstruct(branch)||numel(branch)!=1||!isempty(setdiff(fieldnames(branch),{'response_index','bracket','continuous_branch_declared','independent_domain','x_tolerance','response_tolerance','max_iterations'}))),fail('Retained branch must explicitly bind its domain and root settings');endif
  for field={'response_index','bracket','continuous_branch_declared','independent_domain'}
    if(!isfield(branch,field{1})),fail(['Missing branch ' field{1}]);endif
  endfor
  if(!isnumeric(branch.response_index)||!isscalar(branch.response_index)||!any(branch.response_index==[1 2])||!isscalar(branch.continuous_branch_declared)||!ismember(branch.continuous_branch_declared,[0 1])||!branch.continuous_branch_declared),fail('Explicit continuous branch and response coordinate are required');endif
  for field={'bracket','independent_domain'}
    value=branch.(field{1});if(!isnumeric(value)||!isreal(value)||numel(value)!=2||any(!isfinite(value(:)))||value(1)>=value(2)),fail('Finite increasing branch intervals are required');endif
    branch.(field{1})=gxtxt_numeric_query_double_v1(value(:));
  endfor
  defaults=struct('x_tolerance',1e-12,'response_tolerance',1e-10,'max_iterations',128);
  for field=fieldnames(defaults).'
    name=field{1};if(!isfield(branch,name)),branch.(name)=defaults.(name);endif
    value=branch.(name);if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)||value<=0),fail('Invalid retained root tolerance or budget');endif
  endfor
  if(branch.max_iterations>256||branch.max_iterations!=fix(branch.max_iterations)),fail('Retained root iteration budget must be1..256');endif
  orientation='y_of_x';if(branch.response_index==1),orientation='x_of_y';endif
  if(strcmp(action,'validate')),out=struct('model',model,'branch',branch,'orientation',orientation);return;endif
  if(!strcmp(action,'query')||numel(varargin)!=2),fail('Unknown retained implicit action');endif
  query=varargin{1};options=varargin{2};
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),{'domain','orientation','translation','extrapolation','derivative','tangent_floors'}))),fail('Unknown implicit retained query option');endif
  if(isfield(options,'orientation')&&!strcmp(options.orientation,orientation)),fail('Query orientation differs from the saved implicit response branch');endif
  if(isfield(options,'translation')&&(!isnumeric(options.translation)||!isreal(options.translation)||numel(options.translation)!=2||any(options.translation(:)!=0))),fail('Implicit branch queries require physical coordinates without translation');endif
  if(!isfield(options,'domain')||!isnumeric(options.domain)||!isreal(options.domain)||numel(options.domain)!=2||any(!isfinite(options.domain(:)))||options.domain(1)>=options.domain(2)),fail('An increasing physical reference domain is required');endif
  domain=gxtxt_numeric_query_double_v1(options.domain(:));
  policy='error';if(isfield(options,'extrapolation')),policy=options.extrapolation;endif
  if(!ischar(policy)||!any(strcmp(policy,{'error','allow'}))),fail('Extrapolation must be error or explicit allow');endif
  if(!isnumeric(query)||!isreal(query)||!isvector(query)||isempty(query)||numel(query)>64||any(!isfinite(query(:)))),fail('Implicit retained queries require1..64 finite values');endif
  query=gxtxt_numeric_query_double_v1(query(:));outside=query<domain(1)|query>domain(2);
  if(strcmp(policy,'error')&&any(outside)),fail('Query lies outside the retained reference domain');endif
  branch.extrapolation='reject';if(strcmp(policy,'allow')),branch.extrapolation='allow';endif
  if(isfield(options,'derivative')),branch.derivative=options.derivative;endif
  floors=[0;0];if(isfield(options,'tangent_floors')),floors=options.tangent_floors;endif
  if(!isnumeric(floors)||!isreal(floors)||numel(floors)!=2||any(!isfinite(floors(:)))||any(floors(:)<0)),fail('Two finite nonnegative physical tangent floors are required');endif
  floors=gxtxt_numeric_query_double_v1(floors(:));found=gxtxt_numeric_implicit_v1('query',model,query,branch);
  tx=ones(size(query));ty=found.derivative;
  if(branch.response_index==1),tx=ty;ty=ones(size(query));endif
  regular=found.valid&found.derivative_valid&isfinite(tx)&isfinite(ty);
  valid=regular&abs(tx)>floors(1);inverse_valid=regular&abs(ty)>floors(2);
  slope=NaN(size(query));inverse=slope;slope(valid)=ty(valid)./tx(valid);inverse(inverse_valid)=tx(inverse_valid)./ty(inverse_valid);
  valid=valid&isfinite(slope);inverse_valid=inverse_valid&isfinite(inverse);slope(!valid)=NaN;inverse(!inverse_valid)=NaN;
  out=found;out.schema='gxtxt.model_query.v1';out.query=query;out.parametric=false;out.domain=domain;out.extrapolation=policy;
  out.branch_extrapolated=found.is_extrapolated;out.is_extrapolated=outside|found.is_extrapolated;
  out.orientation=orientation;out.translation=[0;0];out.model_response_derivative=found.derivative;
  out.derivative=slope;out.derivative_valid=valid;out.inverse_derivative=inverse;out.inverse_derivative_valid=inverse_valid;
  out.tangent_x=tx;out.tangent_y=ty;out.tangent_floors=floors;
endfunction
function fail(message),error('GXTXT:Numeric:ImplicitRetained','%s',message);endfunction
