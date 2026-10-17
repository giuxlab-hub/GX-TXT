function R=gxtxt_numeric_welch_aggregate_v1(sum_psd,sum_amplitude,options)
% Aggregate deterministic sums of normalized one-sided periodograms.
% Inputs already include each segment's one-sided and window normalization.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin!=3||!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric','Welch aggregation requires scalar options');endif
  keys={'window_count','frequency_step_hz','enbw_sum_hz'};
  for key=fieldnames(options)'
    if(!any(strcmp(key{1},keys))),error('GXTXT:Numeric','Unknown Welch aggregation option: %s',key{1});endif
  endfor
  for key=keys
    if(!isfield(options,key{1})),error('GXTXT:Numeric','Missing Welch aggregation option: %s',key{1});endif
    v=options.(key{1});
    if(!isnumeric(v)||!isreal(v)||!isscalar(v)||!isfinite(v)||v<=0),error('GXTXT:Numeric','Welch aggregation options must be finite positive scalars');endif
  endfor
  count=double(options.window_count);df=double(options.frequency_step_hz);
  if(count!=fix(count)),error('GXTXT:Numeric','Window count must be a positive integer');endif
  for v={sum_psd,sum_amplitude}
    x=v{1};
    if(!isnumeric(x)||!isreal(x)||!isvector(x)||numel(x)<2||any(!isfinite(x(:)))||any(x(:)<0)),error('GXTXT:Numeric','Periodogram sums must be finite nonnegative vectors with at least two bins');endif
  endfor
  if(numel(sum_psd)!=numel(sum_amplitude)),error('GXTXT:Numeric','Periodogram and amplitude sums must have the same bin count');endif
  psd=double(sum_psd(:))/count;amplitude=double(sum_amplitude(:))/count;
  frequency=(0:numel(psd)-1)'*df;psd_db=NaN(size(psd));positive=psd>0;
  psd_db(positive)=10*log10(psd(positive));
  power=sum(psd)*df;enbw=double(options.enbw_sum_hz)/count;
  if(!isfinite(power)||any(!isfinite(frequency))||!isfinite(enbw)),error('GXTXT:Numeric','Welch aggregation exceeds the finite numerical range');endif
  [peak_psd,index]=max(psd(2:end));index+=1;peak_frequency=frequency(index);
  if(peak_psd==0),peak_frequency=NaN;index=NaN;endif
  R=struct('psd',psd,'asd',sqrt(psd),'mean_amplitude',amplitude,'psd_db',psd_db,'frequency',frequency, ...
    'window_count',count,'bin_count',numel(psd),'df',df,'mean_enbw_hz',enbw,'integrated_power',power, ...
    'peak_frequency',peak_frequency,'peak_psd',peak_psd,'peak_index',index, ...
    'zero_level_bins',sum(!positive),'zero_policy','undefined_finite_logarithmic_level', ...
    'averaging','arithmetic_periodogram_mean','peak_policy','first_positive_maximum_excluding_dc');
endfunction
