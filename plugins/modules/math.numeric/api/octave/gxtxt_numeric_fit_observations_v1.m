% Exact bounded observation receipt; no copies of scientific rows in metadata.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_observations_v1(observed,weights,response_offset,predictors)
  if(nargin<2),weights=[];endif
  if(!isnumeric(observed)||!isreal(observed)||!isvector(observed)||isempty(observed)||any(!isfinite(observed(:))))
    error('GXTXT:Numeric:FitObservations','Observed response must be a nonempty finite real vector');
  endif
  observed=double(observed(:));n=numel(observed);
  if(isempty(weights)),weights=ones(n,1);endif
  if(!isnumeric(weights)||!isreal(weights)||!isvector(weights)||numel(weights)!=n||any(!isfinite(weights(:)))||any(weights(:)<=0))
    error('GXTXT:Numeric:FitObservations','Weights must match the retained rows and be finite and strictly positive');
  endif
  weights=double(weights(:));log_weight_sum=sum(log(weights));
  if(!isfinite(log_weight_sum)),error('GXTXT:Numeric:FitObservations','Weight log normalization is outside binary64 range');endif
  out=struct('schema','gxtxt.fit_observations.v1','n',n,'encoding','float64_le_ordered',...
    'response_sha256',digest(observed),'weights_sha256',digest(weights),'log_weight_sum',log_weight_sum);
  if(nargin>=3&&!isempty(response_offset))
    if(!isnumeric(response_offset)||!isscalar(response_offset)||!isreal(response_offset)||!isfinite(response_offset))
      error('GXTXT:Numeric:FitObservations','Response translation must be a finite scalar');
    endif
    mapped=gxtxt_numeric_v1('array_binary','add',observed,response_offset,struct());
    if(any(!isfinite(mapped.values))),error('GXTXT:Numeric:FitObservations','Translated response is not finite');endif
    out.response_offset=double(response_offset);
    out.fit_response_sha256=digest(mapped.values);
  endif
  if(nargin>=4)
    if(!isnumeric(predictors)||!isreal(predictors)||ndims(predictors)!=2||rows(predictors)!=n||columns(predictors)<1||any(!isfinite(predictors(:))))
      error('GXTXT:Numeric:FitObservations','Predictors must be the finite retained design with one row per response');
    endif
    out.predictor_count=columns(predictors);out.predictors_sha256=digest(double(predictors(:)));
  endif
endfunction
function value=digest(values)
  [~,~,endian]=computer();if(strcmp(endian,'B')),values=swapbytes(values);endif
  bytes=typecast(values,'uint8');
  value=hash('sha256',['gxtxt.fit_observations.v1:f64le:' char(bytes(:)')]);
endfunction
