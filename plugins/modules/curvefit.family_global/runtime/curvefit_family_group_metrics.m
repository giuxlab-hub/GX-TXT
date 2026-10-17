% SPDX-License-Identifier: GPL-3.0-or-later
function metrics = curvefit_family_group_metrics(g,y,pred,numeric_fn)
  groups=unique(g); n_group=numel(groups);
  metrics=struct('family_value',groups(:),'group_value',groups(:),'n',zeros(n_group,1),'sse',zeros(n_group,1), ...
                 'rmse',zeros(n_group,1),'mae',zeros(n_group,1),'max_abs_error',zeros(n_group,1), ...
                 'response_variance',NaN(n_group,1),'r2',NaN(n_group,1));
  for k=1:n_group
    idx=find(g==groups(k));m=feval(numeric_fn,'residual_metrics',y(idx),pred(idx),struct());
    metrics.n(k)=m.n;metrics.sse(k)=m.sse;metrics.rmse(k)=m.rmse;
    metrics.mae(k)=m.mae;metrics.max_abs_error(k)=m.max_abs_error;metrics.r2(k)=m.r2;metrics.response_variance(k)=m.response_variance;
  endfor
endfunction

