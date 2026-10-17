% Linear-design deletion diagnostics from the existing fit and QR/SVD factor.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_influence_v1(Aw,fit,factor,input_rows,input_count)
  [n,p]=size(Aw);
  if(n>1000000||p>128||p<1||factor.rank!=p||factor.free_count!=p||fit.n!=n||fit.p!=p||numel(input_rows)!=n)
    error('GXTXT:Numeric:Influence','Influence requires a bounded full-rank unconstrained linear design');
  endif
  h=zeros(n,1);basis=factor.right_vectors./factor.singular_values(:).';
  for first=1:4096:n
    last=min(n,first+4095);block=(Aw(first:last,:)./factor.column_scale)*basis;
    h(first:last)=sum(block.^2,2);
  endfor
  tolerance=64*eps*max(1,p);
  if(any(!isfinite(h))||any(h>1+tolerance)),error('GXTXT:Numeric:Influence','Leverage exceeds the projection range beyond roundoff');endif
  corrections=sum(h>1);h=min(h,1);denominator=1-h;
  deletion=denominator>tolerance;
  deleted=NaN(n,1);prediction=NaN(n,1);
  deleted(deletion)=fit.residuals(deletion)./denominator(deletion);
  prediction(deletion)=fit.predicted(deletion)-h(deletion).*deleted(deletion);
  deletion=deletion&isfinite(deleted)&isfinite(prediction);
  deleted(!deletion)=NaN;prediction(!deletion)=NaN;
  studentized=NaN(n,1);cook=NaN(n,1);scale=NaN;
  if(fit.dof>0&&isfinite(fit.rmse)&&fit.rmse>0),scale=fit.rmse;endif
  if(isfinite(scale)&&scale>0)
    studentized(deletion)=(fit.weighted_residuals(deletion)/scale)./sqrt(denominator(deletion));
    cook(deletion)=(studentized(deletion).^2/p).*h(deletion)./denominator(deletion);
  endif
  scaled=deletion&isfinite(studentized)&isfinite(cook);
  studentized(!scaled)=NaN;cook(!scaled)=NaN;
  max_cook=NaN;if(any(scaled)),max_cook=max(cook(scaled));endif
  leverage_threshold=2*p/n;cook_threshold=4/n;
  out=struct('schema','gxtxt.linear_influence_numeric.v1','method','existing_column_scaled_qr_svd_exact_linear_deletion',...
    'n',n,'p',p,'rank',factor.rank,'dof',fit.dof,'input_count',input_count,...
    'weight_semantics',fit.weight_semantics,'scale_method','estimated_weighted_residual_mean_square',...
    'residual_scale',scale,'near_one_tolerance',tolerance,'leverage_roundoff_count',corrections,...
    'deletion_available_count',sum(deletion),'scaled_available_count',sum(scaled),...
    'maximum_leverage',max(h),'leverage_sum',sum(h),'maximum_cook_distance',max_cook,...
    'leverage_review_threshold',leverage_threshold,'cook_review_threshold',cook_threshold,...
    'high_leverage_count',sum(h>leverage_threshold),'high_cook_count',sum(cook>cook_threshold),...
    'input_row_index',uint64(input_rows(:)),'leverage',h,'deleted_residual',deleted,...
    'loo_prediction',prediction,'studentized_residual',studentized,'cooks_distance',cook,...
    'deletion_available',logical(deletion),'scaled_available',logical(scaled),...
    'row_identity','one_based_input_position_after_explicit_omission',...
    'factorization_reused',true,'fit_count',1,'block_rows',4096);
endfunction
