% Bounded numerical breakpoint/support facts; CORE owns their interpretation.
% SPDX-License-Identifier: GPL-3.0-or-later
function facts=gxtxt_numeric_fit_regularity_v1(model,q,fixed,x)
  ids={};continuity={};facts=struct();
  if(isfield(model,'regional_composition'))
    declarations=model.regional_composition.recipe.breakpoints;
    if(isstruct(declarations)),declarations=num2cell(declarations);endif
    for k=1:numel(declarations),ids{end+1}=declarations{k}.id;continuity{end+1}=declarations{k}.continuity;endfor
  elseif(isfield(model,'composition'))
    components=model.composition.recipe.components;
    if(isstruct(components)),components=num2cell(components);endif
    for k=1:numel(components)
      c=components{k};
      if(strcmp(c.model_id,'piecewise.linear_knee_v1')&&!any(strcmp(ids,c.bindings.breakpoint)))
        ids{end+1}=c.bindings.breakpoint;continuity{end+1}='C0';
      endif
    endfor
  endif
  if(isempty(ids)),return;endif
  indices=cellfun(@(id)find(strcmp(model.parameter_ids,id)),ids);
  [values,order]=sort(q(indices));ids=ids(order);continuity=continuity(order);indices=indices(order);
  membership=ones(rows(x),1);coincidences=zeros(numel(ids),1);
  for k=1:numel(ids),coincidences(k)=sum(x==values(k));membership=membership+(x>=values(k));endfor
  counts=zeros(numel(ids)+1,1);for k=1:numel(counts),counts(k)=sum(membership==k);endfor
  facts=struct('schema','gxtxt.regional_fit_receipt.v1','breakpoint_ids',{ids},'breakpoint_values',values(:), ...
    'breakpoint_fixed',double(fixed(indices(:))),'continuity',{continuity}, ...
    'sample_coincidence_counts',coincidences,'inference_region_counts',counts);
endfunction
