% SPDX-License-Identifier: GPL-3.0-or-later
% Numeric-owned local polynomial smoothing; public entry is smooth/dataset_smooth.
function out=gxtxt_numeric_lowess_v1(x,y,window,degree,iterations)
  n=numel(x);
  if(!any(degree==[1,2])),error('GXTXT:Numeric','LOWESS degree must be 1 or 2');endif
  if(window<degree+3||window>n||window>1001),error('GXTXT:Numeric','LOWESS needs degree+3 to min(N,1001) nearest neighbors in an odd window');endif
  if(iterations<0||iterations>10),error('GXTXT:Numeric','LOWESS robust_iterations must be from 0 to 10');endif
  work=(iterations+1)*n*window*(degree+1)^2;
  if(n>1000000||work>50000000),error('GXTXT:Numeric','LOWESS work budget exceeded; reduce window/iterations or use an explicit smaller source (no silent decimation)');endif
  rw=ones(n,1);ys=zeros(n,1);completed=0;scale=NaN;
  % Sorted, distinct coordinates were checked by the public owner. The nearest
  % window advances monotonically, so neighbor selection uses O(N) operations.
  for pass=0:iterations
    left=1;
    for i=1:n
      while(left+window<=n&&x(i)-x(left)>x(left+window)-x(i)),left+=1;endwhile
      idx=(left:left+window-1).';dx=x(idx)-x(i);radius=max(abs(dx));
      if(!isfinite(radius)||radius<=0),error('GXTXT:Numeric','LOWESS local physical span is not representable');endif
      u=dx/radius;w=max(0,1-abs(u).^3).^3.*rw(idx);
      active=w>0;
      if(sum(active)<degree+1),error('GXTXT:Numeric','LOWESS robust window has insufficient support; increase window or reduce robust_iterations');endif
      V=ones(sum(active),degree+1);ua=u(active);
      for power=1:degree,V(:,power+1)=ua.^power;endfor
      sw=sqrt(w(active));A=bsxfun(@times,V,sw);
      [Q,R]=qr(A,0);
      if(any(abs(diag(R))<=64*eps*norm(R,'fro'))),error('GXTXT:Numeric','LOWESS local polynomial is rank deficient; increase window or reduce degree');endif
      beta=R\(Q'*(sw.*y(idx(active))));ys(i)=beta(1);
    endfor
    if(any(!isfinite(ys))),error('GXTXT:Numeric','LOWESS local result is not finite');endif
    completed=pass;
    if(pass==iterations),break;endif
    residual=abs(y-ys);scale=median(residual);
    floor_scale=32*eps*max(abs(y));
    if(all(residual<=floor_scale)),break;endif
    if(scale<=floor_scale)
      rw=double(residual<=floor_scale);
    else
      u=min(1,(residual/scale)/6);rw=(1-u.^2).^2;
    endif
  endfor
  out=struct('x',x,'y',ys,'residuals',y-ys,'method','lowess','window',window,'degree',degree,...
    'kernel','tricube','endpoint_policy','nearest_x_window','neighbor_tie_policy','lower_x',...
    'robust_weight','bisquare_six_median_absolute_residual','robust_iterations',iterations,...
    'robust_iterations_completed',completed,'robust_zero_weight_count',sum(rw==0),...
    'robust_scale',scale,'maximum_work_units',work,'extrapolation','not_evaluated',...
    'uncertainty_policy','smoothing_induces_correlated_errors_no_parameter_inference');
endfunction
