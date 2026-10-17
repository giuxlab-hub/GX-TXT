function plan=curvefit_family_parameter_plan(cfg,base_ids,family)
% Family-owned parameter binding; Numeric remains the sole fitting authority.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!iscellstr(base_ids)||isempty(base_ids)||numel(base_ids)>128||numel(unique(base_ids))!=numel(base_ids)||any(cellfun(@isempty,base_ids)))
    error('curvefit.family_global: model requires 1..128 distinct parameter identities');
  endif
  base_ids=base_ids(:)';p=numel(base_ids);
  scopes=split_list(gxtxt_ini_get(cfg,'config.parameter_scopes','shared'));
  if(numel(scopes)==1),scopes=repmat(scopes,1,p);endif
  if(numel(scopes)!=p||!all(ismember(scopes,{'shared','local','fixed'})))
    error('curvefit.family_global: parameter_scopes must be shared, local or fixed in original model order');
  endif
  units=split_list(gxtxt_ini_get(cfg,'model.param_units',''));
  if(isempty(units)),units=repmat({'unspecified'},1,p);endif
  if(numel(units)!=p),error('curvefit.family_global: declared parameter units do not match the mathematical model');endif
  units(cellfun(@isempty,units))={'unspecified'};
  has_local=any(strcmp(scopes,'local'));members=[];width=1;
  if(has_local)
    if(!isnumeric(family)||!isreal(family)||isempty(family)||any(!isfinite(family(:))))
      error('curvefit.family_global: local parameters require finite real physical family values');
    endif
    if(any(cellfun(@(id)!isempty(strfind(id,'@family='))||any(id==','|id==';'|id==char(10)|id==char(13)),base_ids)))
      error('curvefit.family_global: local parameter identities cannot contain CSV delimiters or the reserved @family= qualifier');
    endif
    members=unique(family(:));width=numel(members);
    if(width>64),error('curvefit.family_global: local parameter mapping is bounded to 64 family members');endif
  endif
  indices=zeros(p,width);slot_ids={};slot_units={};slot_base=[];slot_member=[];fixed=[];
  for i=1:p
    count=1;if(strcmp(scopes{i},'local')),count=width;endif
    for j=1:count
      slot=numel(slot_ids)+1;name=base_ids{i};member=0;
      if(strcmp(scopes{i},'local')),name=sprintf('%s@family=%.17g',name,members(j));member=j;indices(i,j)=slot;
      else indices(i,:)=slot;endif
      slot_ids{slot}=name;slot_units{slot}=units{i};slot_base(slot)=i;slot_member(slot)=member;fixed(slot)=strcmp(scopes{i},'fixed');
    endfor
  endfor
  if(numel(slot_ids)>128||numel(unique(slot_ids))!=numel(slot_ids))
    error('curvefit.family_global: expanded parameter mapping requires at most 128 distinct slots');
  endif
  plan=struct('schema','gxtxt.family_parameters.v1','version',1,'base_parameter_ids',{base_ids}, ...
    'base_parameter_units',{units},'scopes',{scopes},'has_local',has_local,'member_values',members, ...
    'member_policy','exact_physical_value_sorted_ascending','slot_ids',{slot_ids},'slot_units',{slot_units}, ...
    'slot_base_indices',slot_base,'slot_member_indices',slot_member,'parameter_indices',indices, ...
    'index_base',1,'fixed_mask',logical(fixed(:)),'slot_limit',128,'local_member_limit',64);
endfunction
function items=split_list(raw)
  if(isempty(strtrim(raw))),items={};else items=cellfun(@strtrim,strsplit(raw,';','collapsedelimiters',false),'UniformOutput',false);endif
endfunction
