function R=spectral_features_compute(freq,value,input_semantics,exclude_dc,numeric_api)
% Compute spectral-distribution features while delegating generic reductions to NUMERIC_API_v1.
% Spectral feature definitions and amplitude/power/PSD interpretation remain domain semantics here.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<5||isempty(numeric_api)),error('analysis.spectral_features: NUMERIC_API_v1 function is required');endif
  f=double(freq(:));v=double(value(:));sem=lower(strtrim(input_semantics));
  if(numel(f)!=numel(v)||numel(f)<3),error('analysis.spectral_features: spectrum must contain at least three matched bins');endif
  if(any(!isfinite(f))||any(!isfinite(v))),error('analysis.spectral_features: spectrum contains non-finite values');endif
  if(any(f<0)||any(diff(f)<=0)),error('analysis.spectral_features: frequency axis must be non-negative and strictly increasing');endif
  if(!any(strcmp(sem,{'amplitude','power','psd'}))),error('analysis.spectral_features: unsupported input semantics: %s',sem);endif

  grid=feval(numeric_api,'grid_info',f,struct('nonfinite','error','rtol',1e-6,'atol',0));
  if(!grid.strict_monotonic||!strcmp(grid.direction,'increasing')||!grid.uniform)
    error('analysis.spectral_features: a uniformly spaced frequency axis is required (relative spacing deviation %.6g)',grid.relative_max_step_deviation);
  endif
  df=grid.step_median;reldev=grid.max_step_deviation/max(abs(df),realmin);

  vstats=feval(numeric_api,'statistics',v,struct('nonfinite','error'));
  if(vstats.min<0),error('analysis.spectral_features: selected spectral values must be non-negative');endif
  keep=true(size(f));
  if(exclude_dc && abs(f(1))<=max(1,abs(df))*1e-12),keep(1)=false;endif
  f=f(keep);v=v(keep);
  if(numel(f)<2),error('analysis.spectral_features: fewer than two bins remain after DC handling');endif

  if(strcmp(sem,'amplitude')),base=v.^2;else,base=v;endif
  bstats=feval(numeric_api,'statistics',base,struct('nonfinite','error'));
  total=bstats.sum;
  if(!isfinite(total)||total<=0),error('analysis.spectral_features: selected spectrum has no positive power-equivalent content');endif
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
    'input_semantics',sem,'exclude_dc',logical(exclude_dc),'df',df,'spacing_relative_deviation',reldev,'bin_count',numel(f), ...
    'dominant_frequency',dominant,'spectral_centroid',centroid,'rms_frequency',rmsf,'spectral_bandwidth',bandwidth, ...
    'frequency_05',f05,'frequency_50',f50,'frequency_85',f85,'frequency_95',f95,'occupied_bandwidth_90',occupied90, ...
    'spectral_flatness',flatness,'spectral_crest_factor',crest,'spectral_entropy',entropy,'total_power_equivalent',total);
endfunction
