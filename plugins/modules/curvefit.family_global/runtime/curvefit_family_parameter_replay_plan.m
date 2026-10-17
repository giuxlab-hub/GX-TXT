function [plan,parameters]=curvefit_family_parameter_replay_plan(cfg,base_ids,family,parameter_set,model_id)
% Interpret qualified identities after CORE has parsed the Parameter Set file.
% Retain unobserved fitted members; never invent parameters for an unseen member.
% SPDX-License-Identifier: GPL-3.0-or-later
  plan=curvefit_family_parameter_plan(cfg,base_ids,family);
  if(plan.has_local)
    members=[];
    for i=1:numel(base_ids)
      if(!strcmp(plan.scopes{i},'local')),continue;endif
      prefix=[base_ids{i} '@family='];current=[];
      for j=1:numel(parameter_set.names)
        id=parameter_set.names{j};
        if(!strncmp(id,prefix,numel(prefix))),continue;endif
        value=str2double(id(numel(prefix)+1:end));
        if(!isfinite(value)||!strcmp(id,sprintf('%s%.17g',prefix,value)))
          error('curvefit.family_global: local parameter has a noncanonical physical family identity');
        endif
        current(end+1,1)=value;
      endfor
      current=sort(current);
      if(isempty(current)||numel(unique(current))!=numel(current))
        error('curvefit.family_global: local parameter set has missing or duplicate physical members');
      endif
      if(isempty(members)),members=current;
      elseif(!isequal(members,current)),error('curvefit.family_global: local parameters describe different member sets');endif
    endfor
    if(any(!ismember(family,members)))
      error('curvefit.family_global: frozen local parameters are unavailable for an unseen physical family member');
    endif
    plan=curvefit_family_parameter_plan(cfg,base_ids,members);
  endif
  parameter_set=gxtxt_validate_parameter_set(parameter_set,plan.slot_ids,model_id);
  parameters=parameter_set.values(:)';
endfunction
