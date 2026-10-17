% Resolve the established declarative fitting kinds at their Numeric owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function model=gxtxt_numeric_fit_model_v1(model,parameter_count)
  if(!isstruct(model)||numel(model)!=1),error('GXTXT:Numeric:Model','Fit model must be a scalar data struct');endif
  if(isfield(model,'formula_declaration'))
    if(isfield(model,'composition')||isfield(model,'regional_composition')||!isfield(model,'kind')||!strcmp(model.kind,'expression')),error('GXTXT:Numeric:Model','Formula declaration requires one unambiguous expression identity');endif
    model=gxtxt_numeric_fit_formula_v1('validate',model);
  elseif(isfield(model,'regional_composition'))
    if(isfield(model,'composition')||!isfield(model,'kind')||!strcmp(model.kind,'expression')),error('GXTXT:Numeric:Model','Frozen regions require one unambiguous declared expression identity');endif
    model=gxtxt_numeric_fit_regions_v1('validate',model);
  elseif(isfield(model,'composition'))
    if(!isfield(model,'kind')||!strcmp(model.kind,'expression')),error('GXTXT:Numeric:Model','Frozen components require the declared expression identity');endif
    model=gxtxt_numeric_fit_composition_v1('validate',model);
  elseif(isfield(model,'input_constraints'))
    error('GXTXT:Numeric:Model','Input constraints must come from a frozen component or regional declaration');
  endif
  if(!isfield(model,'kind')||strcmp(model.kind,'expression')),return;endif
  switch(model.kind)
    case 'linear'
      ids={'intercept','slope'};formula='intercept+slope*x';
    case 'exponential'
      ids={'amplitude','rate','offset'};formula='amplitude*exp(rate*x)+offset';
    case 'power_law'
      ids={'scale','exponent'};formula='scale*x^exponent';
    case 'gaussian'
      ids={'amplitude','center','width','offset'};formula='amplitude*exp(-0.5*((x-center)/width)^2)+offset';
    case 'polynomial_fit'
      if(parameter_count<1||parameter_count>128),error('GXTXT:Numeric:Model','Polynomial needs one to 128 coefficients');endif
      ids=cell(1,parameter_count);terms=ids;
      for k=1:parameter_count
        power=parameter_count-k;ids{k}=sprintf('power_%d',power);terms{k}=sprintf('%s*x^%d',ids{k},power);
        if(power==0),terms{k}=ids{k};endif
      endfor
      formula=strjoin(terms,'+');
    otherwise,error('GXTXT:Numeric:Model','Unknown declared fitting kind');
  endswitch
  if(numel(ids)!=parameter_count),error('GXTXT:Numeric:Model','Declared fitting kind has the wrong parameter count');endif
  if(isfield(model,'parameter_ids')&&!isequal(reshape(model.parameter_ids,1,[]),ids)),error('GXTXT:Numeric:Model','Builtin parameter order cannot be changed');endif
  if(isfield(model,'predictor_ids')&&!isequal(model.predictor_ids,{'x'})),error('GXTXT:Numeric:Model','Builtin fitting kinds require predictor x');endif
  if(isfield(model,'expression'))
    saved=model.expression;if(ischar(saved)),saved={saved};endif
    if(!isequal(saved,{formula})),error('GXTXT:Numeric:Model','Builtin formula cannot be changed; declare an expression model explicitly');endif
  endif
  model.expression={formula};model.parameter_ids=ids;model.predictor_ids={'x'};
endfunction
