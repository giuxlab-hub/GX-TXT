function out=gxtxt_numeric_window_metrics_v1(window,sample_rate,options)
% Discrete deterministic window moments; no spectral or sample inference.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isstruct(options)||!isscalar(options)||!isempty(fieldnames(options)))
    error('GXTXT:Numeric:InvalidPolicy','Window metrics have no estimator options');
  endif
  if(!isnumeric(window)||!isreal(window)||isempty(window)||any(!isfinite(window(:))))
    error('GXTXT:Numeric:InvalidWindow','Window must have finite real coefficients');
  endif
  if(!isnumeric(sample_rate)||!isreal(sample_rate)||!isscalar(sample_rate)||!isfinite(sample_rate)||sample_rate<=0)
    error('GXTXT:Numeric:InvalidSampleRate','Sample rate must be finite and positive');
  endif
  w=double(window(:));n=numel(w);scale=max(abs(w));
  if(scale==0),error('GXTXT:Numeric:InvalidWindow','Window must have nonzero sum');endif
  v=w/scale;total=sum(v);
  if(total==0),error('GXTXT:Numeric:InvalidWindow','Window must have nonzero sum');endif
  squares=sum(v.^2);cg=scale*(total/n);pg=(scale*sqrt(squares/n))^2;
  % A positive mathematical power below binary64 is not a valid zero gain.
  if(pg==0),pg=NaN;endif
  enbw=sample_rate*(squares/(total^2));
  if(cg==0),cg=NaN;endif
  if(enbw==0),enbw=NaN;endif
  out=struct('n',n,'sample_rate',sample_rate,'coherent_gain',cg,'power_gain',pg, ...
    'equivalent_noise_bandwidth_hz',enbw,'method','discrete_window_moments');
endfunction
