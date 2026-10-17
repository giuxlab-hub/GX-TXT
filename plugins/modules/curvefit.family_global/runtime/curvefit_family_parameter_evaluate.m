function predicted=curvefit_family_parameter_evaluate(model,plan,values,x,family)
% Apply one joint vector to original mathematical parameter/member identities.
% SPDX-License-Identifier: GPL-3.0-or-later
  values=values(:);x=x(:);family=family(:);
  if(numel(values)!=numel(plan.slot_ids)||any(!isfinite(values))||numel(x)!=numel(family))
    error('curvefit.family_global: parameter vector or physical predictor alignment differs from its plan');
  endif
  if(!plan.has_local)
    predicted=model(values(plan.parameter_indices(:,1)),x,family);predicted=checked(predicted,numel(x));return;
  endif
  [found,member]=ismember(family,plan.member_values);
  if(any(!found)),error('curvefit.family_global: local parameters are unavailable for an undeclared physical family member');endif
  predicted=zeros(numel(x),1);
  for j=1:numel(plan.member_values)
    rows_for_member=find(member==j);if(isempty(rows_for_member)),continue;endif
    theta=values(plan.parameter_indices(:,j));
    predicted(rows_for_member)=checked(model(theta,x(rows_for_member),family(rows_for_member)),numel(rows_for_member));
  endfor
endfunction
function values=checked(values,count)
  if(!isnumeric(values)||!isreal(values)||numel(values)!=count||any(!isfinite(values(:))))
    error('curvefit.family_global: mathematical model must return one finite real response per physical input row');
  endif
  values=values(:);
endfunction
