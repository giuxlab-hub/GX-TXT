% Reusable dimensionless logarithm and physical response retransformation.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_log_response_v1(operation,values,options)
  if(!(isa(values,'double')||isa(values,'single'))||!isreal(values)||numel(values)>1000000),error('GXTXT:Numeric:Logarithm','Values must be real floating-point arrays with at most1000000 elements; convert integer data explicitly');endif
  values=double(values);
  if(!isstruct(options)||!isfield(options,'reference')),error('GXTXT:Numeric:Logarithm','An explicit positive reference in the source response units is required');endif
  reference=options.reference;
  if(!isnumeric(reference)||!isreal(reference)||!isscalar(reference)||!isfinite(reference)||reference<=0),error('GXTXT:Numeric:Logarithm','Reference must be a finite positive scalar');endif
  reference=double(reference);
  if(strcmp(operation,'log_ratio'))
    if(numel(fieldnames(options))!=1),error('GXTXT:Numeric:Logarithm','log_ratio accepts only its explicit reference');endif
    if(any(!isfinite(values(:)))||any(values(:)<=0)),error('GXTXT:Numeric:Logarithm','Natural logarithms require finite strictly positive values; no rows are silently omitted');endif
    result=log(values)-log(reference);
    close=abs(values-reference)<=.5*reference;
    result(close)=log1p((values(close)-reference)/reference);
    if(any(!isfinite(result(:)))),error('GXTXT:Numeric:Logarithm','Log ratio is outside finite binary64 range');endif
    out=struct('schema','gxtxt.log_ratio.v1','values',result,'n',numel(values),'reference',reference,'base','natural','input_shape',size(values),'method','dimensionless_natural_log_with_log1p_near_reference');
    return;
  endif
  if(!strcmp(operation,'log_response_retransform')),error('GXTXT:Numeric:Logarithm','Unknown logarithmic response operation');endif
  allowed={'reference','log_standard_deviation','lower','upper','interval_kind','confidence'};
  if(any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric:Logarithm','Unknown response retransformation option');endif
  if(any(!isfinite(values(:)))),error('GXTXT:Numeric:Logarithm','Log predictions must be finite');endif
  out=struct('schema','gxtxt.log_response_retransform.v1','n',numel(values),'reference',reference,'base','natural','median',physical_exp(values,reference),'mean',[],'log_standard_deviation',[],'log_bias_correction',[],'mean_available',false,'lower',[],'upper',[],'interval_kind','none','confidence',[],'interval_available_count',0,'method','monotone_exponential_of_dimensionless_log_response');
  if(isfield(options,'log_standard_deviation')&&!isempty(options.log_standard_deviation))
    deviation=options.log_standard_deviation;
    if(!isnumeric(deviation)||!isreal(deviation)||!isscalar(deviation)||!isfinite(deviation)||deviation<0),error('GXTXT:Numeric:Logarithm','Log standard deviation must be a finite nonnegative scalar');endif
    correction=(double(deviation)/sqrt(2))^2;
    if(!isfinite(correction)),error('GXTXT:Numeric:Logarithm','Lognormal correction exceeds finite binary64 range');endif
    out.mean=physical_exp(values+correction,reference);out.mean_available=true;
    out.log_standard_deviation=double(deviation);out.log_bias_correction=correction;
  endif
  kind='none';if(isfield(options,'interval_kind')),kind=options.interval_kind;endif
  if(!ischar(kind)||!any(strcmp(kind,{'none','log_mean_confidence','log_new_observation'}))),error('GXTXT:Numeric:Logarithm','Unknown captured log-space interval kind');endif
  has_bounds=isfield(options,'lower')||isfield(options,'upper');
  if(strcmp(kind,'none'))
    if(has_bounds||isfield(options,'confidence')),error('GXTXT:Numeric:Logarithm','Bounds/confidence require an explicit captured log-space interval kind');endif
  else
    if(!isfield(options,'lower')||!isfield(options,'upper')||!isfield(options,'confidence')),error('GXTXT:Numeric:Logarithm','Intervals require both captured bounds and confidence');endif
    lower=options.lower;upper=options.upper;confidence=options.confidence;
    if(!(isa(lower,'double')||isa(lower,'single'))||!(isa(upper,'double')||isa(upper,'single'))||!isreal(lower)||!isreal(upper)||!isequal(size(lower),size(values))||!isequal(size(upper),size(values))||any(isinf(lower(:)))||any(isinf(upper(:)))||any(xor(isnan(lower(:)),isnan(upper(:))))),error('GXTXT:Numeric:Logarithm','Bounds must match prediction shape with paired NaN gaps');endif
    if(!isnumeric(confidence)||!isreal(confidence)||!isscalar(confidence)||!isfinite(confidence)||confidence<=0||confidence>=1),error('GXTXT:Numeric:Logarithm','Confidence must lie strictly between zero and one');endif
    valid=isfinite(lower)&isfinite(upper);
    if(any(lower(valid)>values(valid))||any(upper(valid)<values(valid))),error('GXTXT:Numeric:Logarithm','Captured bounds must contain their log prediction');endif
    out.lower=NaN(size(values));out.upper=NaN(size(values));
    out.lower(valid)=physical_exp(double(lower(valid)),reference);out.upper(valid)=physical_exp(double(upper(valid)),reference);
    out.interval_kind=kind;out.confidence=double(confidence);out.interval_available_count=sum(valid(:));
  endif
endfunction
function values=physical_exp(log_values,reference)
  % Prefer multiplication near ordinary scales; combine logs when exp alone
  % under/overflows although the physical product is representable.
  values=reference.*exp(log_values);
  repair=!isfinite(values)|values==0;
  values(repair)=exp(log(reference)+log_values(repair));
  if(any(!isfinite(values(:)))||any(values(:)<=0)),error('GXTXT:Numeric:Logarithm','Physical response is outside positive finite binary64 range; choose appropriate units');endif
endfunction
