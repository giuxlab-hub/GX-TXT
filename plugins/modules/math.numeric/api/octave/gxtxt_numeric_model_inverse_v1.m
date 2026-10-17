% Explicit local bracket inversion through the existing public root owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_model_inverse_v1(model,targets,bracket,options)
  if(ischar(model)),model=gxtxt_numeric_model_state_decode_v1(model);endif
  allowed={'domain','extrapolation','x_tolerance','response_tolerance','max_iterations','orientation','translation','polar_frame'};
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),allowed)))
    error('GXTXT:Numeric:Options','Unknown local model inverse option');
  endif
  if(!isnumeric(targets)||!isreal(targets)||!isvector(targets)||isempty(targets)||numel(targets)>64||any(!isfinite(targets(:))))
    error('GXTXT:Numeric:Query','Local inversion requires1..64 finite response targets');
  endif
  if(!isnumeric(bracket)||!isreal(bracket)||numel(bracket)!=2||any(!isfinite(bracket(:)))||bracket(1)>=bracket(2))
    error('GXTXT:Numeric:Domain','Supply an explicit increasing continuous-branch bracket');
  endif
  if(!isfield(options,'domain')),error('GXTXT:Numeric:Domain','Retained training domain is required');endif
  targets=gxtxt_numeric_query_double_v1(targets);bracket=gxtxt_numeric_query_double_v1(bracket);
  qopts=struct('domain',options.domain,'derivative',false);
  for key={'extrapolation','orientation','translation','polar_frame'}
    if(isfield(options,key{1})),qopts.(key{1})=options.(key{1});endif
  endfor
  endpoints=gxtxt_numeric_v1('model_query',model,bracket,qopts);
  if(endpoints.parametric),error('GXTXT:Numeric:Model','XY parametric curves require an explicit projection; scalar inversion is unavailable');endif
  xtol=1e-12;ytol=1e-10;limit=128;
  if(isfield(options,'x_tolerance')),xtol=options.x_tolerance;endif
  if(isfield(options,'response_tolerance')),ytol=options.response_tolerance;endif
  if(isfield(options,'max_iterations')),limit=options.max_iterations;endif
  for v={xtol,ytol}
    if(!isnumeric(v{1})||!isreal(v{1})||!isscalar(v{1})||!isfinite(v{1})||v{1}<=0),error('GXTXT:Numeric:Options','Inverse tolerances must be finite positive absolute coordinate/response values');endif
  endfor
  if(!isnumeric(limit)||!isreal(limit)||!isscalar(limit)||!isfinite(limit)||limit<1||limit>256||limit!=fix(limit)),error('GXTXT:Numeric:Options','Inverse iteration budget must be1..256');endif
  targets=double(targets(:));n=numel(targets);roots=NaN(n,1);residual=roots;valid=false(n,1);iterations=zeros(n,1);evaluations=zeros(n,1);reasons=cell(n,1);
  for k=1:n
    a=endpoints.predicted(1)-targets(k);b=endpoints.predicted(2)-targets(k);
    if(a==0&&b==0)
      reasons{k}='Both bracket endpoints match; no unique local inverse is established.';continue;
    elseif(a==0),root=bracket(1);value=0;converged=true;
    elseif(b==0),root=bracket(2);value=0;converged=true;
    elseif(sign(a)==sign(b))
      reasons{k}='No sign-changing bracket; a local root is not established.';continue;
    else
      try
        found=gxtxt_numeric_v1('root_find',@(x)query_response(model,x,qopts)-targets(k),bracket,...
          struct('tolerance',xtol,'max_iterations',limit));
        root=found.root;value=query_response(model,root,qopts)-targets(k);converged=found.converged;
        iterations(k)=found.iterations;evaluations(k)=found.function_evaluations;
      catch failure
        iterations(k)=NaN;evaluations(k)=NaN;
        reasons{k}=['Root evaluation failed: ',failure.message];continue;
      end_try_catch
    endif
    if(converged&&isfinite(root)&&root>=bracket(1)&&root<=bracket(2)&&isfinite(value)&&abs(value)<=ytol)
      roots(k)=root;residual(k)=value;valid(k)=true;reasons{k}='Local bracket root verified against the response tolerance; global uniqueness is not certified.';
    else
      reasons{k}='Solver did not establish an in-bracket root within the response tolerance.';
    endif
  endfor
  outside=valid&(roots<options.domain(1)|roots>options.domain(2));
  out=struct('schema','gxtxt.model_inverse.v1','targets',targets,'roots',roots,'valid',valid,...
    'residual',residual,'bracket',double(bracket(:)),'domain',double(options.domain(:)),...
    'is_extrapolated',outside,'iterations',iterations,'function_evaluations',evaluations,...
    'reasons',{reasons},'x_tolerance',xtol,'response_tolerance',ytol,...
    'uniqueness','not_certified','branch_contract','caller_declares_continuous_branch',...
    'fit_performed',false,'uncertainty_available',false);
endfunction
function value=query_response(model,x,options)
  evaluated=gxtxt_numeric_v1('model_query',model,x,options);value=evaluated.predicted;
endfunction
