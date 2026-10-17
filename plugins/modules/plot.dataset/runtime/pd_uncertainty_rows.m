function [values,state]=pd_uncertainty_rows(values,aux_ids,optional_ids,selected,state)
% Carry finite-run identities through reducers without retaining skipped rows.
% Runs refer to each series' selected observations, not unrelated filtered rows.
% SPDX-License-Identifier: GPL-3.0-or-later
  n=numel(aux_ids);selected=selected(:);
  if(isempty(state)),state=struct('last_good',false(1,numel(optional_ids)),'run',zeros(1,numel(optional_ids)));endif
  for k=1:numel(optional_ids)
    j=find(strcmp(aux_ids,optional_ids{k}),1);
    if(isempty(j)),error('plot.dataset: uncertainty variable %s was not requested',optional_ids{k});endif
    v=values{j};if(iscell(v)),v=str2double(v);endif
    if(!isnumeric(v)&&!islogical(v)),error('plot.dataset: uncertainty variable %s must be numeric',optional_ids{k});endif
    runs=zeros(numel(v),1);good=isfinite(v(selected));good=good(:);
    if(!isempty(selected))
      starts=good&![state.last_good(k);good(1:end-1)];
      r=state.run(k)+cumsum(starts);runs(selected)=r.*good;
      state.run(k)=r(end);state.last_good(k)=good(end);
    endif
    values{n+k}=runs;
  endfor
endfunction
