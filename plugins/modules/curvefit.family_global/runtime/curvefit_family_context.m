function [context,units]=curvefit_family_context(cfg,x_name,fam_name,y_name,orientation)
% Resolve declared source metadata; never infer scientific units from names.
% SPDX-License-Identifier: GPL-3.0-or-later
  [xu,~,xm]=gxtxt_analysis_source_variable_meta(cfg,'primary',x_name);
  [fu,~,fm]=gxtxt_analysis_source_variable_meta(cfg,'primary',fam_name);
  [yu,~,ym]=gxtxt_analysis_source_variable_meta(cfg,'primary',y_name);
  model_unit=strtrim(gxtxt_ini_get(cfg,'model.y_unit',''));
  if(!isempty(yu)&&!isempty(model_unit)&&!strcmp(yu,model_unit))
    error('curvefit.family_global: source response unit %s differs from model output %s; convert the canonical source explicitly before fitting',yu,model_unit);
  endif
  if(isempty(yu)),yu=model_unit;endif
  units=struct('horizontal',xu,'group',fu,'response',yu);
  if(strcmp(orientation,'family_by_x')),units.horizontal=fu;units.group=xu;endif
  if(isempty(xu)),xu='unspecified';endif;if(isempty(yu)),yu='unspecified';endif
  context=struct('orientation','y_of_x','residual_sign','predicted_minus_observed','x_unit',xu,'y_unit',yu,'x_variable_id',xm.variable_id,'y_variable_id',ym.variable_id,'sample_role','evaluation');
endfunction
