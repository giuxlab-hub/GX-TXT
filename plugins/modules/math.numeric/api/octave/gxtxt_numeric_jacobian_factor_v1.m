% Shared Numeric factorization; never forms J'J or an n-by-n covariance.
% SPDX-License-Identifier: GPL-3.0-or-later
function factor=gxtxt_numeric_jacobian_factor_v1(J,fixed)
  [n,p]=size(J);fixed=logical(fixed(:));
  if(numel(fixed)!=p||!isreal(J)||any(!isfinite(J(:)))),error('GXTXT:Numeric:Jacobian','Invalid Jacobian or fixed mask');endif
  free=find(!fixed);count=numel(free);column_scale=zeros(1,count);
  for k=1:count,column_scale(k)=norm(J(:,free(k)));endfor
  column_scale(column_scale==0)=1;
  s=[];physical_s=[];V=[];rnk=0;condition=NaN;scaled_condition=NaN;
  if(count)
    % Octave's single-output dense QR returns packed Householder data: its
    % leading upper triangle is R, with no explicit observation-sized Q/U.
    packed=qr(J(:,free)./column_scale,0);
    R=triu(packed(1:min(n,count),:));clear packed;
    [~,S,V]=svd(R,0);s=diag(S);tolerance=max(n,count)*eps(max(s));rnk=sum(s>tolerance);
    physical_s=svd(R.*column_scale);condition=Inf;scaled_condition=Inf;
    if(rnk==count),condition=max(physical_s)/min(physical_s);scaled_condition=max(s)/min(s);endif
  endif
  factor=struct('n',n,'p',p,'free',free,'free_count',count,'column_scale',column_scale,...
    'singular_values',s,'physical_singular_values',physical_s,'right_vectors',V,'rank',rnk,...
    'condition_number',condition,'scaled_condition_number',scaled_condition);
endfunction
