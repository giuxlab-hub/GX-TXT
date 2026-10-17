% SPDX-License-Identifier: GPL-3.0-or-later
% Generic nonlinear fit bridge from Scientific Analysis API v1 to one selected
% Mathematical Model Plugin API v1 resource described in runtime.ini [model].
% The model function contract is y = f(theta, x, family) or y = f(theta, x).
function R = gxtxt_analysis_op_fit(x,y,family,model_cfg,max_iter,tol,context)
  if(nargin<7),context=struct();endif
  if(nargin<3),family=[];endif;if(nargin<5||isempty(max_iter)),max_iter=400;endif;if(nargin<6||isempty(tol)),tol=1e-8;endif
  if(!isnumeric(x)||!isnumeric(y)),error('GXTXT:AnalysisFit','x/y must be numeric');endif
  x=x(:);y=y(:);if(numel(x)!=numel(y)),error('GXTXT:AnalysisFit','x/y length mismatch');endif
  if(!isempty(family)&&numel(family)!=numel(x)),error('GXTXT:AnalysisFit','family length mismatch');endif
  fn=strtrim(gxtxt_ini_get(model_cfg,'model.function',''));script=strtrim(gxtxt_ini_get(model_cfg,'model.script',''));
  if(isempty(fn)),error('GXTXT:AnalysisFit','runtime [model] function is missing');endif
  if(!isempty(script)),addpath(fileparts(script));endif
  init=parse_num_list(gxtxt_ini_get(model_cfg,'model.param_initial',''));lo=parse_num_list(gxtxt_ini_get(model_cfg,'model.param_lower',''));hi=parse_num_list(gxtxt_ini_get(model_cfg,'model.param_upper',''));
  names=parse_list(gxtxt_ini_get(model_cfg,'model.param_names',''));
  if(isempty(init)),error('GXTXT:AnalysisFit','model initial parameters are missing');endif
  if(isempty(lo)),lo=-Inf(size(init));endif;if(isempty(hi)),hi=Inf(size(init));endif
  if(numel(lo)!=numel(init)||numel(hi)!=numel(init)),error('GXTXT:AnalysisFit','model parameter bounds length mismatch');endif
  good=isfinite(x)&isfinite(y);if(!isempty(family)&&isnumeric(family)),good &= isfinite(family(:));endif
  xx=x(good);yy=y(good);if(!isempty(family)),ff=family(good);else ff=[];endif
  if(numel(xx)<max(3,numel(init))),error('GXTXT:AnalysisFit','insufficient finite data for fit');endif
  callback=@(p,X) call_model(fn,p,X,ff);
  options=struct('solver','auto','max_iterations',max_iter,'tolerance',tol,'lower_bounds',lo,'upper_bounds',hi);
  fit=gxtxt_analysis_numeric_call('nonlinear_fit',callback,xx,yy,init,options);
  theta=fit.parameters;pred=call_model(fn,theta,x,family);
  metrics=gxtxt_analysis_numeric_call('residual_metrics',yy,fit.predicted);
  if(isempty(names)),names=arrayfun(@(k) sprintf('p%d',k),1:numel(theta),'UniformOutput',false);endif
  fit.model=struct('parameter_ids',{names});
  semantics=gxtxt_statistics_v1('from_numeric','math.numeric.nonlinear','nonlinear_fit',fit,context,metrics);
  rmse=gxtxt_statistics_v1('feature',semantics,'rmse');mae=gxtxt_statistics_v1('feature',semantics,'mae');
  quality=gxtxt_statistics_v1('feature',semantics,'r_squared');
  st='valid';reason='';if(!fit.converged),st='warning';reason='optimizer_not_converged';endif
  R=struct('predicted',pred,'theta',theta,'parameter_names',{names},'objective',metrics.mse,'objective_convention','mean_squared_residual',...
    'exitflag',fit.exitflag,'rmse',rmse.value,'mae',mae.value,'r2',quality.value,'status',st,'reason',reason,...
    'statistical_results',semantics,'diagnostic_features',struct('rmse',rmse,'mae',mae,'r2',quality),...
    'solver',fit.solver,'solver_message',fit.solver_message,'solver_options',options,'source_row_positions',find(good));
endfunction
function y=call_model(fn,theta,x,f)
  h=str2func(fn);if(isempty(f)),y=h(theta,x);else y=h(theta,x,f);endif;y=y(:);
endfunction
function a=parse_num_list(s),a=[];for q=parse_list(s),v=str2double(q{1});if(!isfinite(v)&&!any(strcmpi(q{1},{'inf','+inf','-inf'}))),error('GXTXT:AnalysisFit','invalid numeric list value: %s',q{1});endif;a(end+1)=v;endfor;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif;endfunction
