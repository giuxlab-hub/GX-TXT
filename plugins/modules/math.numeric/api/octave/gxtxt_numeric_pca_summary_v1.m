function out=gxtxt_numeric_pca_summary_v1(singular_values,observation_count,options)
% Interpret existing SVD magnitudes numerically; no second SVD or data fit.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric','PCA summary options must be a scalar struct');endif
  if(!isnumeric(singular_values)||!isreal(singular_values)||!isvector(singular_values)||isempty(singular_values)||numel(singular_values)>8192||any(!isfinite(singular_values(:)))||any(singular_values(:)<0))
    error('GXTXT:Numeric','PCA summary requires one to 8192 finite nonnegative singular values');
  endif
  n=double(observation_count);
  if(!isscalar(n)||!isfinite(n)||n<2||n!=fix(n)),error('GXTXT:Numeric','PCA summary requires at least two observations');endif
  centered=true;if(isfield(options,'centered')),centered=options.centered;endif
  if(!isscalar(centered)||!any(centered==[0,1])),error('GXTXT:Numeric','centered must be boolean');endif
  values=double(singular_values(:));
  if(any(diff(values)>0)),error('GXTXT:Numeric','SVD singular values must retain descending component order');endif
  component_variance=values.^2/(n-1);total=sum(component_variance);
  if(!isfinite(total)),error('GXTXT:Numeric','PCA spectral moment overflow');endif
  ratios=NaN(size(values));cumulative=ratios;
  if(total>0),ratios=component_variance/total;cumulative=cumsum(ratios);endif
  method='centered_sample_covariance';if(!centered),method='uncentered_second_moment_n_minus_one';endif
  out=struct('n',n,'singular_value',values,'component_variance',component_variance, ...
    'explained_ratio',ratios,'cumulative_ratio',cumulative,'component_index',(1:numel(values))', ...
    'component_count',numel(values),'total_component_variance',total,'method',method);
endfunction
