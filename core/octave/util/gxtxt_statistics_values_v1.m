function values=gxtxt_statistics_values_v1(result)
% Validated numeric presentation: NaN means a non-value; statuses/reasons remain
% mandatory in the accompanying result metadata. No applicability is inferred.
% SPDX-License-Identifier: GPL-3.0-or-later
  gxtxt_statistics_v1('validate',result);
  values=struct();names=fieldnames(result.quantities);
  for k=1:numel(names)
    item=result.quantities.(names{k});
    if(strcmp(item.status,'value'))
      values.(names{k})=item.value;
    elseif(strcmp(item.kind,'matrix'))
      values.(names{k})=NaN(numel(result.parameters));
    elseif(strcmp(item.kind,'vector'))
      if(isfield(item,'probabilities')),values.(names{k})=NaN(size(item.probabilities));
      else values.(names{k})=NaN(numel(result.parameters),1);endif
    else
      values.(names{k})=NaN;
    endif
  endfor
endfunction
