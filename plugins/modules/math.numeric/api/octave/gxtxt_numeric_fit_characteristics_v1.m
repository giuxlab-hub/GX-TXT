% Deterministic shape hints on exact finite observations; no model is fitted.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_characteristics_v1(X,Y,options)
  if(nargin<3),options=struct();endif
  if(!isfloat(X)||!isfloat(Y)||!isreal(X)||!isreal(Y)||!isvector(X)||!isvector(Y)||numel(X)!=numel(Y)||numel(X)<2||numel(X)>1000000||any(!isfinite(X(:)))||any(!isfinite(Y(:))))
    fail('Characteristics require equal finite real floating vectors, 2..1000000 observations; resolve nonfinite handling upstream');
  endif
  defaults=struct('relative_flat_tolerance',1e-8,'monotonic_fraction',.95,'linearity_tolerance',.02,'prominence',.2,'period_tolerance',.15,'saturation_ratio',.25);
  if(!isstruct(options)||numel(options)!=1||!isempty(setdiff(fieldnames(options),fieldnames(defaults)))),fail('Unknown source-characteristic option');endif
  fields=fieldnames(defaults);lower=[0,.5,0,0,0,0];upper=[.001,1,.25,1,.5,1];
  for i=1:numel(fields)
    key=fields{i};value=defaults.(key);if(isfield(options,key)),value=options.(key);endif
    if(!isnumeric(value)||!isreal(value)||!isscalar(value)||!isfinite(value)||value<lower(i)||value>upper(i)||(strcmp(key,'prominence')&&value==0)),fail(['Invalid characteristic threshold: ',key]);endif
    defaults.(key)=double(value);
  endfor
  X=double(X(:));Y=double(Y(:));n=numel(X);[sx,order]=sort(X);sy=Y(order);
  signature=gxtxt_numeric_v1('fit_observation_signature',Y,[],[],X);
  distinct=1+sum(diff(sx)>0);xmin=sx(1);xmax=sx(end);ymin=min(Y);ymax=max(Y);
  out=struct('schema','gxtxt.fit_characteristics.v1','numeric_api','NUMERIC_API_v1','operation','fit_characteristics',...
    'status','value','reason','','observation_count',n,'distinct_predictors',distinct,...
    'duplicate_predictors',distinct<n,'predictor_minimum',xmin,'predictor_maximum',xmax,...
    'response_minimum',ymin,'response_maximum',ymax,'positive_predictors',all(X>0),...
    'response_one_sign',all(Y>0)||all(Y<0),'constant_response',ymin==ymax,...
    'shape_status','unavailable','monotonic','unavailable','linear_like',false,...
    'peak_count',0,'trough_count',0,'periodic_hint',false,'period_status','unavailable','period',NaN,...
    'saturating_hint',false,'tail_slope_ratio',NaN,'thresholds',defaults,...
    'observation_signature',signature,'order_policy','stable_predictor_sort_for_shape_only',...
    'nonfinite_policy','error','purpose','advisory_shape_hints_only','fitted',false,'accepted',false);
  span=xmax-xmin;amplitude=ymax-ymin;
  if(!isfinite(span)||!isfinite(amplitude)||span<=0)
    out.status='unavailable';out.reason='A finite nonzero predictor span and finitely representable response range are required';return;
  endif
  if(distinct<n)
    out.reason='Repeated predictors are retained observations; ordered functional shape hints are unavailable without an explicit duplicate policy';return;
  endif
  out.shape_status='value';u=(sx-xmin)/span;
  if(amplitude==0)
    out.monotonic='constant';out.linear_like=true;return;
  endif
  v=(sy-ymin)/amplitude;delta=diff(v);flat=defaults.relative_flat_tolerance;
  increasing=sum(delta>=-flat)/(n-1)>=defaults.monotonic_fraction;
  decreasing=sum(delta<=flat)/(n-1)>=defaults.monotonic_fraction;
  if(increasing&&decreasing),out.monotonic='nearly_constant';
  elseif(increasing),out.monotonic='increasing';elseif(decreasing),out.monotonic='decreasing';
  else,out.monotonic='mixed';endif
  out.linear_like=max(abs(v-(v(1)+(v(end)-v(1))*u)))<=defaults.linearity_tolerance;
  % Hysteresis records an interior extremum only after a declared fraction of
  % the observed range reverses its direction. Endpoints are never peaks.
  peaks=[];troughs=[];direction=0;extreme=1;prominence=defaults.prominence;
  for i=2:n
    if(direction==0)
      if(v(i)-v(extreme)>=prominence),direction=1;extreme=i;
      elseif(v(extreme)-v(i)>=prominence),direction=-1;extreme=i;endif
    elseif(direction==1)
      if(v(i)>v(extreme)),extreme=i;
      elseif(v(extreme)-v(i)>=prominence)
        if(extreme>1&&extreme<n),peaks(end+1)=extreme;endif
        direction=-1;extreme=i;
      endif
    else
      if(v(i)<v(extreme)),extreme=i;
      elseif(v(i)-v(extreme)>=prominence)
        if(extreme>1&&extreme<n),troughs(end+1)=extreme;endif
        direction=1;extreme=i;
      endif
    endif
  endfor
  out.peak_count=numel(peaks);out.trough_count=numel(troughs);
  if((numel(peaks)>=3&&numel(troughs)>=2)||(numel(troughs)>=3&&numel(peaks)>=2))
    intervals=[diff(sx(peaks));diff(sx(troughs))];period=median(intervals);
    if(isfinite(period)&&period>0&&max(abs(intervals/period-1))<=defaults.period_tolerance)
      out.periodic_hint=true;out.period_status='value';out.period=period;
    endif
  endif
  if(n>=8&&any(strcmp(out.monotonic,{'increasing','decreasing'})))
    edge=max(2,floor(n/5));first=abs((v(edge)-v(1))/(u(edge)-u(1)));
    last=abs((v(end)-v(end-edge+1))/(u(end)-u(end-edge+1)));
    if(isfinite(first)&&isfinite(last)&&first>0)
      out.tail_slope_ratio=last/first;
      out.saturating_hint=abs(v(edge)-v(1))>=.1&&out.tail_slope_ratio<=defaults.saturation_ratio;
    endif
  endif
endfunction
function fail(message),error('GXTXT:Numeric:FitCharacteristics','%s',message);endfunction
