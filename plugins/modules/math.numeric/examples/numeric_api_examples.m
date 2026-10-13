% NUMERIC_API_v1 Octave examples.
% SPDX-License-Identifier: GPL-3.0-or-later
x=(0:0.5:5)'; y=1+2*x+0.5*x.^2;
poly2=gxtxt_numeric_v1('polynomial_fit',x,y,2,[],struct());
poly2w=gxtxt_numeric_v1('polynomial_fit',x,y,2,linspace(1,2,numel(x))',struct());
yq=gxtxt_numeric_v1('polynomial_evaluate',poly2,[0;2.5;5],struct());
model=@(p,z) p(1).*exp(p(2).*z);
nl=gxtxt_numeric_v1('nonlinear_fit',model,x,3*exp(-0.4*x),[2;-0.2],struct('solver','fminsearch'));
sp=gxtxt_numeric_v1('spline_create',x,y,struct('method','spline'));
sp_eval=gxtxt_numeric_v1('spline_evaluate',sp,(0:0.25:5)',struct());
pp=gxtxt_numeric_v1('spline_create',x,y,struct('method','pchip'));
pp_eval=gxtxt_numeric_v1('spline_evaluate',pp,(0:0.25:5)',struct());
sm=gxtxt_numeric_v1('smooth',x,y,struct('method','savitzky_golay','window',5,'degree',2));
base=gxtxt_numeric_v1('baseline',x,y,[],[],struct('method','polynomial','degree',2));
peaks=gxtxt_numeric_v1('find_peaks',x,[0;1;0;0;2;0;0;1.5;0;0;0],struct('min_height',0.5));
root=gxtxt_numeric_v1('root_find',@(z) z.^2-2,[0 2],struct());
