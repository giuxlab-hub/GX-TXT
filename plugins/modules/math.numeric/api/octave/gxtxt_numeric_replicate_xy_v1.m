function R=gxtxt_numeric_replicate_xy_v1(X,Y,source_ids,options)
% Coordinate consensus extends the existing Numeric replicate reducer.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),options=struct();endif
  if(!isequal(size(X),size(Y))),error('GXTXT:Numeric','Aligned XY matrices must have identical dimensions');endif
  R=struct('x',gxtxt_numeric_replicate_summary_v1(X,source_ids,options), ...
           'y',gxtxt_numeric_replicate_summary_v1(Y,source_ids,options));
  R.covariance_xy=NaN(rows(X),1);
  if(columns(X)>1)
    for i=1:rows(X)
      receipt=gxtxt_numeric_v1('covariance',X(i,:),Y(i,:));
      R.covariance_xy(i)=receipt.covariance_sample;
    endfor
  endif
  R.covariance_method='sample_cross_coordinate_covariance_at_declared_correspondence';
endfunction
