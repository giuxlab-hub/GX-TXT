function [records,metrics]=curvefit_family_statistics(metrics,context,provenance,prefix)
% Adapt existing Numeric scalar columns; never recompute their estimates.
% SPDX-License-Identifier: GPL-3.0-or-later
  names={'n','sse','rmse','mae','max_abs_error','r2','response_variance'};
  mapping=struct('n','n','sse','sse','rmse','rmse','mae','mae','max_abs_error','max_abs_error','r2','centered_comparison_score');
  records=struct();metrics.export_rows={};count=numel(metrics.n);
  for first=1:8192:count
    last=min(first+8191,count);ids=cell(1,last-first+1);columns=struct();
    for k=first:last,ids{k-first+1}=sprintf('%s_%06d',prefix,k);endfor
    for k=1:numel(names),name=names{k};columns.(name)=metrics.(name)(first:last);endfor
    table=gxtxt_statistics_v1('from_numeric_columns','math.numeric.comparison','residual_metrics',ids,columns,struct(),context,provenance);
    exported=gxtxt_statistics_v1('table_rows',table,mapping);
    metrics.export_rows=[metrics.export_rows,exported];
    records.(sprintf('%s_block_%04d',prefix,1+floor((first-1)/8192)))=table;
  endfor
  % Public row projection carries status, units and the legacy column alias.
  for k=1:count
    cells=metrics.export_rows{k}.cells;
    for name=fieldnames(mapping)',metrics.(name{1})(k)=cells.(name{1}).value;endfor
  endfor
endfunction
