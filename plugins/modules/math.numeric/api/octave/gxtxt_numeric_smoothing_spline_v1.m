% Existing natural cubic objective with bounded manual/GCV selection.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_smoothing_spline_v1(x,y,options)
 if(!isreal(x)||!isreal(y)),error('GXTXT:Numeric:Smoothing','Smoothing requires real observations');endif
 if(exist('gxtxt_numeric_smoothing_native','file')!=3),error('GXTXT:Numeric:Smoothing','The packaged native smoothing backend is unavailable');endif
 if(isfield(options,'weights')||isfield(options,'sigma')),error('GXTXT:Numeric:Smoothing','This natural cubic smoothing contract requires unweighted observations');endif
 mode=option(options,'smoothing_selection','manual');
 if(strcmp(mode,'manual'))
  if(!isfield(options,'smoothing_lambda')),error('GXTXT:Numeric:Smoothing','smoothing_lambda is required for manual smoothing');endif
  out=gxtxt_numeric_smoothing_native(x,y,options.smoothing_lambda);
  out.smoothing_selection=struct('method','manual','evaluations',1,'criterion','gcv_n_rss_over_n_minus_edf_squared','selected_lambda',out.smoothing_lambda,'selected_edf',out.edf,'selected_gcv',out.gcv_score,'boundary_optimum',false);
 elseif(strcmp(mode,'gcv'))
  if(numel(x)<5),error('GXTXT:Numeric:Smoothing','GCV selection requires at least five observations');endif
  bounds=option(options,'gcv_lambda_bounds',[]);count=option(options,'gcv_grid_count',17);refine=option(options,'gcv_refinement_evaluations',24);
  if(!isnumeric(bounds)||!isreal(bounds)||numel(bounds)!=2||any(!isfinite(bounds))||bounds(1)<=0||bounds(2)<=bounds(1)),error('GXTXT:Numeric:Smoothing','GCV needs explicit increasing positive finite lambda bounds');endif
  if(!isscalar(count)||!isreal(count)||!isfinite(count)||count!=fix(count)||count<3||count>65||!isscalar(refine)||!isreal(refine)||!isfinite(refine)||refine!=fix(refine)||refine<0||refine>64),error('GXTXT:Numeric:Smoothing','GCV needs 3..65 log-grid candidates and 0..64 refinement evaluations');endif
  logs=linspace(log(bounds(1)),log(bounds(2)),count);lambdas=exp(logs);lambdas(1)=bounds(1);lambdas(end)=bounds(2);
  table=zeros(count+refine,4);best=Inf;best_index=0;evaluations=0;
  for k=1:count
   candidate=gxtxt_numeric_smoothing_native(x,y,lambdas(k));evaluations+=1;
   table(evaluations,:)=[candidate.smoothing_lambda,candidate.edf,candidate.sse,candidate.gcv_score];
   if(candidate.gcv_available&&candidate.gcv_score<best),out=candidate;best=candidate.gcv_score;best_index=k;endif
  endfor
  if(best_index==0),error('GXTXT:Numeric:Smoothing','No finite GCV candidate in the requested bounds');endif
  left=logs(max(1,best_index-1));right=logs(min(count,best_index+1));ratio=(sqrt(5)-1)/2;
  a=right-ratio*(right-left);b=left+ratio*(right-left);fa=NaN;fb=NaN;
  for k=1:refine
   if(isnan(fa)),at=a;side=1;elseif(isnan(fb)),at=b;side=2;elseif(fa<=fb),right=b;b=a;fb=fa;a=right-ratio*(right-left);at=a;side=1;else left=a;a=b;fa=fb;b=left+ratio*(right-left);at=b;side=2;endif
   candidate=gxtxt_numeric_smoothing_native(x,y,exp(at));evaluations+=1;
   table(evaluations,:)=[candidate.smoothing_lambda,candidate.edf,candidate.sse,candidate.gcv_score];
   if(side==1),fa=candidate.gcv_score;else fb=candidate.gcv_score;endif
   if(candidate.gcv_available&&candidate.gcv_score<best),out=candidate;best=candidate.gcv_score;endif
  endfor
  out.smoothing_selection=struct('method','bounded_log_grid_golden_section','criterion','gcv_n_rss_over_n_minus_edf_squared', ...
    'lambda_bounds',bounds(:).','grid_count',count,'refinement_budget',refine,'evaluations',evaluations,'candidate_columns',{{'lambda','edf','sse','gcv_score'}},'candidates',table(1:evaluations,:), ...
    'selected_lambda',out.smoothing_lambda,'selected_edf',out.edf,'selected_gcv',out.gcv_score,'boundary_optimum',any(out.smoothing_lambda==bounds), ...
    'guarantee','Best evaluated candidate within the explicit bounds; no global optimum guarantee');
 else,error('GXTXT:Numeric:Smoothing','Unknown smoothing selection; use manual or gcv');endif
 out.model='smoothing_spline';out.parametric=false;out.source_x=x;out.source_count=numel(x);out.parameters=out.smoothed_y;
 out.converged=true;
 out.penalty='sum squared residuals + lambda times integral squared second derivative';out.extrapolation='error';
 out.smoother_dof_convention='trace((I-S)^T*(I-S)); fixed lambda, independent equal-variance observations; smoothing bias excluded';
endfunction
function v=option(options,key,fallback),v=fallback;if(isfield(options,key)),v=options.(key);endif;endfunction
