% Shared full-rank covariance from the existing column-scaled QR/SVD factor.
% SPDX-License-Identifier: GPL-3.0-or-later
function covariance=gxtxt_numeric_fit_covariance_v1(factor,scale)
  if(!isscalar(scale)||!isreal(scale)||!isfinite(scale)||scale<0||factor.rank!=factor.free_count)
    error('GXTXT:Numeric:Covariance','A finite scale and fully identified free coordinates are required');
  endif
  covariance=zeros(factor.p,factor.p);
  if(factor.free_count)
    scaled_inverse=factor.right_vectors*diag(1./factor.singular_values);
    physical_inverse=scaled_inverse./factor.column_scale(:);
    covariance(factor.free,factor.free)=(physical_inverse*physical_inverse.')*scale;
  endif
endfunction
