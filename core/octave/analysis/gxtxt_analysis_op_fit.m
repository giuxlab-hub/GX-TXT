% SPDX-License-Identifier: GPL-3.0-or-later
% Generic nonlinear fit bridge from Scientific Analysis API v1 to one selected
% Mathematical Model Plugin API v1 resource described in runtime.ini [model].
% The model function contract is y = f(theta, x, family) or y = f(theta, x).
function R = gxtxt_analysis_op_fit(x,y,family,model_cfg,max_iter,tol)
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
  z0=theta_to_z(init,lo,hi);
  obj=@(z) objective(z,lo,hi,fn,xx,ff,yy);
  opt=optimset('MaxIter',max_iter,'TolX',tol,'TolFun',tol,'Display','off');
  [z,fval,exitflag]=fminsearch(obj,z0,opt);theta=z_to_theta(z,lo,hi);
  pred=call_model(fn,theta,x,family);res=y-pred;finite=isfinite(res);rmse=sqrt(mean(res(finite).^2));mae=mean(abs(res(finite)));
  ssr=sum(res(finite).^2);yf=y(finite);sst=sum((yf-mean(yf)).^2);if(sst==0),r2=NaN;else r2=1-ssr/sst;endif
  st='valid';reason='';if(exitflag<=0),st='warning';reason='optimizer_not_converged';endif
  R=struct('predicted',pred,'theta',theta,'parameter_names',{names},'objective',fval,'exitflag',exitflag,'rmse',rmse,'mae',mae,'r2',r2,'status',st,'reason',reason);
endfunction
function q=objective(z,lo,hi,fn,x,f,y)
  th=z_to_theta(z,lo,hi);p=call_model(fn,th,x,f);r=y-p;r=r(isfinite(r));if(isempty(r)),q=realmax;else q=mean(r.^2);endif
endfunction
function y=call_model(fn,theta,x,f)
  h=str2func(fn);if(isempty(f)),y=h(theta,x);else y=h(theta,x,f);endif;y=y(:);
endfunction
function z=theta_to_z(t,lo,hi)
  z=zeros(size(t));for i=1:numel(t)
    if(isfinite(lo(i))&&isfinite(hi(i))),u=(t(i)-lo(i))/(hi(i)-lo(i));u=min(max(u,1e-9),1-1e-9);z(i)=log(u/(1-u));
    elseif(isfinite(lo(i))),z(i)=log(max(t(i)-lo(i),1e-12));elseif(isfinite(hi(i))),z(i)=log(max(hi(i)-t(i),1e-12));else z(i)=t(i);endif
  endfor
endfunction
function t=z_to_theta(z,lo,hi)
  t=zeros(size(z));for i=1:numel(z)
    if(isfinite(lo(i))&&isfinite(hi(i))),u=1/(1+exp(-z(i)));t(i)=lo(i)+(hi(i)-lo(i))*u;
    elseif(isfinite(lo(i))),t(i)=lo(i)+exp(z(i));elseif(isfinite(hi(i))),t(i)=hi(i)-exp(z(i));else t(i)=z(i);endif
  endfor
endfunction
function a=parse_num_list(s),a=[];for q=parse_list(s),v=str2double(q{1});if(!isfinite(v)&&!any(strcmpi(q{1},{'inf','+inf','-inf'}))),error('GXTXT:AnalysisFit','invalid numeric list value: %s',q{1});endif;a(end+1)=v;endfor;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif;endfunction
