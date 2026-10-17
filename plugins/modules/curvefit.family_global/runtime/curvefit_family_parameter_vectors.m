function [initial,lower,upper,fixed]=curvefit_family_parameter_vectors(cfg,plan,base_initial,base_lower,base_upper)
% Expand model constraints in the plan's explicit, stable parameter order.
% SPDX-License-Identifier: GPL-3.0-or-later
  count=numel(plan.base_parameter_ids);
  if(numel(base_initial)!=count||numel(base_lower)!=count||numel(base_upper)!=count)
    error('curvefit.family_global: model parameter vectors differ from original parameter order');
  endif
  initial=base_initial(plan.slot_base_indices)(:);lower=base_lower(plan.slot_base_indices)(:);upper=base_upper(plan.slot_base_indices)(:);
  initial=override(cfg,'parameter_initial_values',initial);lower=override(cfg,'parameter_lower_bounds',lower);upper=override(cfg,'parameter_upper_bounds',upper);
  if(any(!isfinite(initial))||any(isnan(lower))||any(isnan(upper))||any(lower>upper)||any(initial<lower)||any(initial>upper))
    error('curvefit.family_global: expanded initial values must be finite and within valid parameter bounds');
  endif
  fixed=plan.fixed_mask;
  extra=override(cfg,'parameter_fixed_mask',zeros(size(fixed)));
  if(any(!ismember(extra,[0,1]))),error('curvefit.family_global: expanded fixed mask must contain boolean values');endif
  fixed=fixed|logical(extra)|(lower==upper);
endfunction
function values=override(cfg,name,values)
  raw=strtrim(gxtxt_ini_get(cfg,['config.' name],''));if(isempty(raw)),return;endif
  pieces=strsplit(raw,';','collapsedelimiters',false);parsed=cellfun(@str2double,pieces)(:);
  if(numel(parsed)!=numel(values)),error('curvefit.family_global: %s must match the reported expanded parameter order',name);endif
  values=parsed;
endfunction
