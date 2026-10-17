% Fitter adapter: exact input and bounded manual display; no nonlinear optimization.
% SPDX-License-Identifier: GPL-3.0-or-later
function dataset_curve_fit_parameters(action,varargin)
  addpath(getenv('GXDCF_NUMERIC_API_DIR'));addpath(getenv('GXDCF_CORE_OCTAVE_DIR'));
  if(strcmp(action,'prepare'))
    [kind,x,y,query,du,dv,regional,frame]=deal(varargin{:});
    if(!any(strcmp(getenv('GXDCF_ORIENTATION'),{'y_of_x','x_of_y','r_of_theta','parametric'}))),error('Manual parameter view requires a declared functional orientation');endif
    if(strcmp(kind,'polynomial')),kind='polynomial_fit';endif
    opts=struct();initial=[];
    path=getenv('GXDCF_INITIAL');if(exist(path,'file')&&dir(path).bytes>1),initial=dlmread(path,',');initial=initial(:);endif
    if(!isempty(initial)),opts.initial_parameters=initial;endif
    if(strcmp(kind,'polynomial_fit')),opts.degree=str2double(getenv('GXDCF_DEGREE'));endif
    path=getenv('GXDCF_SOLVER_SETTINGS');
    if(!isempty(path))
      settings=gxtxt_scientific_result_read_v1(path).solver;
      for field={'lower_bounds','upper_bounds','fixed_mask'}
        if(isfield(settings,field{1})),opts.(field{1})=settings.(field{1});endif
      endfor
    endif
    if(strcmp(kind,'rational')),proposal=struct('status','unavailable','reason','Rational coefficients use their explicit physical declaration; no automatic degree or pole selection is implied.','parameters',[]);
    else,proposal=gxtxt_numeric_v1('fit_initial_guess',kind,x,y,opts);endif
    direct=any(strcmp(kind,{'circular_arc','quadratic_bezier','cubic_bezier','parametric_polynomial','fourier'}));
    if(direct)
      direct_options=struct();
      if(strcmp(kind,'parametric_polynomial'))
        direct_options.degree=str2double(getenv('GXDCF_DEGREE'));
        direct_options.parameterization=getenv('GXDCF_PARAMETERIZATION');direct_options.topology=getenv('GXDCF_TOPOLOGY');
        if(!isempty(getenv('GXDCF_CLOSURE_TOLERANCE'))),direct_options.closure_tolerance=str2double(getenv('GXDCF_CLOSURE_TOLERANCE'));endif
        if(strcmp(direct_options.parameterization,'user_parameter'))
          fid=fopen(getenv('GXDCF_TRAIN_PARAMETER'),'rb');if(fid<0),error('Manual model requires aligned source parameters');endif
          unwind_protect,direct_options.user_parameter=fread(fid,Inf,'double',0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
          if(!isempty(getenv('GXDCF_USER_PERIOD'))),direct_options.user_period=str2double(getenv('GXDCF_USER_PERIOD'));endif
        endif
      elseif(strcmp(kind,'fourier'))
        direct_options.order=str2double(getenv('GXDCF_DEGREE'));period=str2double(getenv('GXDCF_PERIOD'));
        if(isfinite(period)&&period>0),direct_options.period=period;endif
      endif
      % Existing closed-form/linear owner supplies a starting state. This is
      % an auxiliary initialization, with no nonlinear optimization or acceptance.
      base=gxtxt_numeric_v1('curve_model_fit',kind,x,y,direct_options);
      declared=gxtxt_numeric_v1('curve_model_parameter_state',base,[]);
      proposal.status='proposed';proposal.reason='Existing direct model solution provides the manual starting state; stored initials do not change its direct fitting algorithm.';
      proposal.parameters=declared.parameters;
      if(isempty(initial)),initial=declared.parameters;endif
      declared=gxtxt_numeric_v1('curve_model_parameter_state',base,initial);
      model=declared.model;model.parameter_ids=declared.parameter_ids;
      lower=declared.lower_bounds;upper=declared.upper_bounds;fixed=declared.fixed_mask;
    elseif(strcmp(kind,'registered'))
      definition=gxtxt_scientific_result_read_v1(getenv('GXDCF_PARAMETER_DEFINITION')).definition;
      model=struct('kind','registered_callback','parameters',initial,'parameter_ids',{definition.parameter_ids});
      lower=definition.lower_bounds(:);upper=definition.upper_bounds(:);fixed=logical(definition.fixed_mask(:));
      if(numel(initial)!=numel(lower)||numel(initial)!=numel(model.parameter_ids)),error('Registered parameter declaration size differs');endif
    elseif(strcmp(kind,'rational'))
      if(du!=0||dv!=0),error('Rational manual parameters require physical untranslated coordinates');endif
      captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_RATIONAL_RECIPE'));model=gxtxt_numeric_v1('rational_model_compose',captured.recipe);
      initial=model.initial_parameters(:);c=model.formula_model.parameter_constraints;lower=c.lower_bounds(:);upper=c.upper_bounds(:);fixed=logical(c.fixed_mask(:));
    elseif(any(strcmp(kind,{'formula','components','regions'})))
      if(strcmp(kind,'formula'))
        captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_FORMULA_RECIPE'));
        model=gxtxt_numeric_v1('fit_formula_compose',captured.recipe);
      elseif(strcmp(kind,'components'))
        captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_COMPONENT_RECIPE'));
        model=gxtxt_numeric_v1('fit_model_compose',captured.recipe);
      else,model=regional;endif
      policy=model.input_constraints.translation_policy;
      if((!strcmp(policy,'allowed')&&du!=0)||(strcmp(policy,'forbid_translation')&&dv!=0)),error('Declared physical model forbids these translations');endif
      initial=model.initial_parameters(:);c=model.parameter_constraints;
      lower=c.lower_bounds(:);upper=c.upper_bounds(:);fixed=logical(c.fixed_mask(:));
      for field={'lower_bounds','upper_bounds','fixed_mask'}
        if(isfield(opts,field{1}))
          value=opts.(field{1})(:);if(numel(value)!=numel(initial)),error('Parameter constraint size differs from the declared model');endif
          if(strcmp(field{1},'lower_bounds')),lower=max(lower,value);
          elseif(strcmp(field{1},'upper_bounds')),upper=min(upper,value);
          else,fixed=fixed|logical(value);endif
        endif
      endfor
    else
      if(!any(strcmp(kind,{'linear','polynomial_fit','exponential','power_law','gaussian'}))),error('This model has no editable finite parameter declaration');endif
      if(isempty(initial))
        if(!strcmp(proposal.status,'proposed')),error('%s',proposal.reason);endif
        initial=proposal.parameters(:);
      endif
      model=struct('kind',kind,'parameters',initial);
      lower=proposal.lower_bounds(:);upper=proposal.upper_bounds(:);fixed=logical(proposal.fixed_mask(:));
      % Public evaluation resolves canonical parameter IDs and validates kind.
      checked=gxtxt_numeric_v1('nonlinear_evaluate',model,query(1));
      model.parameter_ids=checked.parameter_ids;
    endif
    fixed=fixed|(lower==upper);
    if(any(lower>upper)||any(initial<lower)||any(initial>upper)),error('Current parameters violate the effective bounds');endif
    % Display sampling never changes the exact observations used for initials.
    indices=unique(round(linspace(1,numel(query),min(1024,numel(query)))));
    context=struct('model',model,'initial',initial,'lower',lower,'upper',upper,'fixed',fixed,...
      'query',query(indices),'du',du,'dv',dv,'orientation',getenv('GXDCF_ORIENTATION'),'frame',frame);
    context.declaration_kind=kind;context.direct_model=direct;
    if(strcmp(kind,'rational')),context.recipe=model.recipe;context.model=struct();endif
    if(any(strcmp(kind,{'formula','components','regions'})))
      % Cache the public authoring recipe. Recompose it at its Numeric owner;
      % the bounded result format intentionally treats cell lists as vectors.
      % Do not weaken immutable-model equality to accommodate that transport.
      if(strcmp(kind,'formula')),context.recipe=model.formula_declaration.recipe;
      elseif(strcmp(kind,'components')),context.recipe=model.composition.recipe;
      else,context.recipe=model.regional_composition.recipe;endif
      context.model=struct();
    endif
    gxtxt_scientific_result_write_v1(getenv('GXDCF_PARAMETER_CONTEXT'),struct('context',context));
    out=struct('schema','gxtxt.fitter_parameter_view.v1','status',proposal.status,'reason',proposal.reason,...
      'parameter_ids',{model.parameter_ids},'current_parameters',initial,'suggested_parameters',proposal.parameters,...
      'lower_bounds',lower,'upper_bounds',upper,'fixed_mask',fixed,'observation_count',numel(x),...
      'display_count',numel(context.query),'translation',[du,dv],'nonlinear_optimization',false,...
      'direct_model',direct,'initial_values_affect_direct_solver',false);
    if(direct),out.unit_roles=declared.unit_roles;endif
  elseif(strcmp(action,'evaluate'))
    context=gxtxt_scientific_result_read_v1(getenv('GXDCF_PARAMETER_CONTEXT')).context;
    values=gxtxt_scientific_result_read_v1(getenv('GXDCF_PARAMETER_VALUES')).parameters(:);
    if(numel(values)!=numel(context.initial)||any(!isfinite(values))||any(values<context.lower)||any(values>context.upper)||any(values(logical(context.fixed))!=context.initial(logical(context.fixed))))
      error('Manual parameters violate bounds, fixed values or the declared parameter count');
    endif
    model=context.model;
    if(strcmp(context.declaration_kind,'rational')),model=gxtxt_numeric_v1('rational_model_compose',context.recipe);
    elseif(strcmp(context.declaration_kind,'formula')),model=gxtxt_numeric_v1('fit_formula_compose',context.recipe);
    elseif(strcmp(context.declaration_kind,'components')),model=gxtxt_numeric_v1('fit_model_compose',context.recipe);
    elseif(strcmp(context.declaration_kind,'regions')),model=gxtxt_numeric_v1('fit_region_compose',context.recipe);endif
    model.parameters=values;
    if(strcmp(context.declaration_kind,'rational'))
      model.formula_model.parameters=values;evaluated=gxtxt_numeric_v1('rational_evaluate',model,context.query);u=context.query(:);v=evaluated.predicted(:);
    elseif(context.direct_model)
      declared=gxtxt_numeric_v1('curve_model_parameter_state',model,values);
      evaluated=gxtxt_numeric_v1('curve_model_evaluate',declared.model,context.query);
      u=evaluated.x(:)-context.du;v=evaluated.y(:)-context.dv;
    else
      evaluated=gxtxt_numeric_v1('nonlinear_evaluate',model,context.query);
      u=context.query(:)-context.du;v=evaluated.predicted(:)-context.dv;
    endif
    if(any(!isfinite(v))),error('Manual model is nonfinite on the displayed domain');endif
    if(strcmp(context.orientation,'r_of_theta'))
      if(any(v<0)),error('Radial manual model predicts a negative physical radius');endif
      physical=gxtxt_numeric_v1('cartesian_coordinates',u,v,context.frame);points=physical.points;
    elseif(strcmp(context.orientation,'x_of_y')),points=[v,u];else,points=[u,v];endif
    out=struct('schema','gxtxt.fitter_parameter_curve.v1','parameters',values,'points',points,...
      'display_count',rows(points),'nonlinear_optimization',false,'accepted',false);
  else,error('Unknown parameter view operation');endif
  gxtxt_scientific_result_write_v1(getenv('GXDCF_PARAMETER_RESULT'),struct('view',out));
endfunction
