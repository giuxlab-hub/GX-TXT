% Model-owned description of preprocessing; no fit or statistical computation.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_fit_input_policy_v1(name,state)
  names={'linear','polynomial','exponential','power_law','gaussian','components','regions','formula','rational','implicit','complex_response','registered','circular_arc','quadratic_bezier','cubic_bezier','pchip','smoothing_spline','akima','bspline','fourier','parametric_polynomial','parametric_spline'};
  if(!ischar(name)||!any(strcmp(name,names))||!isstruct(state)||numel(state)!=1)
    error('GXTXT:Numeric','Input policy requires a supported model and scalar captured state');
  endif
  out=struct('schema','gxtxt.fit_input_policy.v1','model',name,'order','preserve_observation_order',...
    'duplicates','preserve_distinct_observations','aggregation','none','endpoint','preserve',...
    'removed_terminal_endpoint',false,'parameterization','not_applicable');
  if(any(strcmp(name,{'akima','bspline'})))
    out.order='require_strictly_increasing_independent_coordinate';out.duplicates='reject_repeated_independent_coordinate';
  elseif(any(strcmp(name,{'pchip','smoothing_spline'})))
    out.order='ascending_independent_coordinate';out.duplicates='reject_repeated_independent_coordinate';
  elseif(strcmp(name,'fourier'))
    if(!isfield(state,'solver')||!any(strcmp(state.solver,{'orthogonal_dft','least_squares'})))
      error('GXTXT:Numeric','Fourier input policy requires its captured solver branch');
    endif
    if(strcmp(state.solver,'orthogonal_dft')),out.order='ascending_independent_coordinate_for_orthogonal_dft';endif
  elseif(any(strcmp(name,{'parametric_polynomial','parametric_spline'})))
    for key={'parameterization','repeated_endpoint_removed'}
      if(!isfield(state,key{1})),error('GXTXT:Numeric','Parametric input policy requires captured parameterization and endpoint decision');endif
    endfor
    if(!ischar(state.parameterization)||!any(strcmp(state.parameterization,{'row_order','path_length','user_parameter'})))
      error('GXTXT:Numeric','Invalid captured parameterization');
    endif
    flag=state.repeated_endpoint_removed;
    if(!(islogical(flag)||isnumeric(flag))||!isscalar(flag)||!isreal(flag)||!ismember(flag,[0,1]))
      error('GXTXT:Numeric','Captured endpoint removal must be boolean');
    endif
    out.parameterization=state.parameterization;out.removed_terminal_endpoint=logical(flag);
    if(flag),out.endpoint='remove_repeated_terminal_closure_node';endif
    if(strcmp(state.parameterization,'path_length')),out.duplicates='reject_zero_length_consecutive_segments';
    elseif(strcmp(state.parameterization,'user_parameter')),out.duplicates='require_strictly_monotone_user_parameter';endif
  elseif(any(strcmp(name,{'quadratic_bezier','cubic_bezier'})))
    out.parameterization='normalized_source_row_order';
  elseif(strcmp(name,'circular_arc'))
    out.parameterization='unwrapped_angle_in_source_order';
  endif
endfunction
