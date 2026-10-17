function ids=pd_uncertainty_aux_ids(presentation,series)
% Uncertainty is optional presentation data; grouping/order/bar geometry is not.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<2),series=struct();endif
  ids={};required={};
  for name={'x_error','y_error'}
    if(!isfield(presentation,name{1})),continue;endif
    item=presentation.(name{1});mode='none';if(isfield(item,'mode')),mode=lower(strtrim(item.mode));endif
    if(strcmp(mode,'symmetric')),fields={'variable_id'};
    elseif(strcmp(mode,'asymmetric')),fields={'lower_variable_id','upper_variable_id'};
    else continue;endif
    for field=fields,if(isfield(item,field{1})),ids{end+1}=item.(field{1});endif;endfor
  endfor
  if(isfield(presentation,'band'))
    for field={'lower_variable_id','upper_variable_id'}
      if(isfield(presentation.band,field{1})),ids{end+1}=presentation.band.(field{1});endif
    endfor
  endif
  if(isfield(presentation,'family_variable_id')),required{end+1}=presentation.family_variable_id;endif
  if(isfield(presentation,'bar_bounds'))
    for field={'lower_variable_id','upper_variable_id'}
      if(isfield(presentation.bar_bounds,field{1})),required{end+1}=presentation.bar_bounds.(field{1});endif
    endfor
  endif
  for field={'secondary_variable_id','ordering_variable_id'}
    if(isfield(series,field{1})),required{end+1}=series.(field{1});endif
  endfor
  ids=unique(ids,'stable');ids=ids(!cellfun(@isempty,ids)&!ismember(ids,required));
endfunction
