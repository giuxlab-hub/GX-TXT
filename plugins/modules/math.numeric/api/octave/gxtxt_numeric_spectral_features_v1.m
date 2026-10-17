function R=gxtxt_numeric_spectral_features_v1(freq,value,options)
% Numeric-owned spectrum distribution; public CORE owns physical interpretation.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric','Spectral options must be a scalar struct');endif
  for key=fieldnames(options)'
    if(!any(strcmp(key{1},{'input_semantics','exclude_dc'}))),error('GXTXT:Numeric','Unknown spectral option: %s',key{1});endif
  endfor
  input_semantics='amplitude';exclude_dc=true;
  if(isfield(options,'input_semantics')),input_semantics=options.input_semantics;endif
  if(isfield(options,'exclude_dc')),exclude_dc=options.exclude_dc;endif
  if(!ischar(input_semantics)||!isscalar(exclude_dc)||!(isnumeric(exclude_dc)||islogical(exclude_dc))||!isfinite(exclude_dc)||!any(exclude_dc==[0 1]))
    error('GXTXT:Numeric','Spectral semantics must be text and exclude_dc must be Boolean');
  endif
  numeric_api='gxtxt_numeric_v1';
  f=double(freq(:));v=double(value(:));sem=lower(strtrim(input_semantics));
  if(numel(f)!=numel(v)||numel(f)<3),error('GXTXT:Numeric: spectrum must contain at least three matched bins');endif
  if(any(!isfinite(f))||any(!isfinite(v))),error('GXTXT:Numeric: spectrum contains non-finite values');endif
  if(any(f<0)||any(diff(f)<=0)),error('GXTXT:Numeric: frequency axis must be non-negative and strictly increasing');endif
  if(!any(strcmp(sem,{'amplitude','power','psd'}))),error('GXTXT:Numeric: unsupported input semantics: %s',sem);endif

  grid=feval(numeric_api,'grid_info',f,struct('nonfinite','error','rtol',1e-6,'atol',0));
  if(!grid.strict_monotonic||!strcmp(grid.direction,'increasing')||!grid.uniform)
    error('GXTXT:Numeric: a uniformly spaced frequency axis is required (relative spacing deviation %.6g)',grid.relative_max_step_deviation);
  endif
  df=grid.step_median;reldev=grid.max_step_deviation/max(abs(df),realmin);

  vstats=feval(numeric_api,'statistics',v,struct('nonfinite','error'));
  if(vstats.min<0),error('GXTXT:Numeric: selected spectral values must be non-negative');endif
  keep=true(size(f));
  if(exclude_dc && abs(f(1))<=max(1,abs(df))*1e-12),keep(1)=false;endif
  f=f(keep);v=v(keep);
  if(numel(f)<2),error('GXTXT:Numeric: fewer than two bins remain after DC handling');endif

  if(strcmp(sem,'amplitude')),base=v.^2;else,base=v;endif
  bstats=feval(numeric_api,'statistics',base,struct('nonfinite','error'));
  total=bstats.sum;
  if(!isfinite(total)||total<=0),error('GXTXT:Numeric: selected spectrum has no positive power-equivalent content');endif
  q=base/total;
  c=feval(numeric_api,'cumulative_sum',q,struct('nonfinite','error'));cum=c.values;cum(end)=1.0;

  imax=find(base==bstats.max,1,'first');dominant=f(imax);
  wstats=feval(numeric_api,'weighted_statistics',f,base,struct('nonfinite','error'));
  centroid=wstats.mean;rmsf=wstats.rms;bandwidth=wstats.std_population;
  wq=feval(numeric_api,'weighted_quantiles',f,base,[0.05;0.50;0.85;0.95],struct('nonfinite','error'));
  f05=wq.quantiles(1);f50=wq.quantiles(2);f85=wq.quantiles(3);f95=wq.quantiles(4);occupied90=max(0,f95-f05);

  if(bstats.min<=0)
    flatness=0.0;
  else
    lstats=feval(numeric_api,'statistics',log(base),struct('nonfinite','error'));
    flatness=exp(lstats.mean)/bstats.mean;
  endif
  crest=bstats.max/bstats.mean;
  nz=q>0;
  if(any(nz))
    estats=feval(numeric_api,'statistics',q(nz).*log(q(nz)),struct('nonfinite','error'));
    H=-estats.sum;
  else
    H=0;
  endif
  if(numel(q)>1),entropy=H/log(numel(q));else,entropy=0;endif
  rel_db=10*log10(max(base,realmin)/bstats.max);
  R=struct('frequency',f,'source_value',v,'power_equivalent',base,'normalized_power',q,'cumulative_power',cum,'relative_power_db',rel_db, ...
    'quantile_definition',wq.definition,'input_semantics',sem,'exclude_dc',logical(exclude_dc),'df',df,'spacing_relative_deviation',reldev,'bin_count',numel(f), ...
    'dominant_frequency',dominant,'spectral_centroid',centroid,'rms_frequency',rmsf,'spectral_bandwidth',bandwidth, ...
    'frequency_05',f05,'frequency_50',f50,'frequency_85',f85,'frequency_95',f95,'occupied_bandwidth_90',occupied90, ...
    'spectral_flatness',flatness,'spectral_crest_factor',crest,'spectral_entropy',entropy,'total_power_equivalent',total);
endfunction
