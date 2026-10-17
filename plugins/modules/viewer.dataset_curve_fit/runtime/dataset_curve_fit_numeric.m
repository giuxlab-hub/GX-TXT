% Data-only worker for viewer.dataset_curve_fit. All fitting, evaluation and
% residual metrics are delegated to the public NUMERIC_API_v1 dispatcher.
% SPDX-License-Identifier: GPL-3.0-or-later
function dataset_curve_fit_numeric()
  addpath(getenv('GXDCF_NUMERIC_API_DIR'));
  addpath(getenv('GXDCF_CORE_OCTAVE_DIR'));
  train=numeric_read_input(getenv('GXDCF_TRAIN'),getenv('GXDCF_TRAIN_FORMAT'));
  if(!isempty(getenv('GXDCF_CHARACTERISTICS_RESULT')))
    orientation=getenv('GXDCF_ORIENTATION');
    if(strcmp(orientation,'x_of_y')),train=train(:,[2,1]);elseif(!strcmp(orientation,'y_of_x')),error('Source suggestions require a functional X or Y response orientation');endif
    settings=gxtxt_scientific_result_read_v1(getenv('GXDCF_CHARACTERISTIC_THRESHOLDS')).thresholds;
    characteristics=gxtxt_numeric_v1('fit_characteristics',train(:,1),train(:,2),settings);
    gxtxt_scientific_result_write_v1(getenv('GXDCF_CHARACTERISTICS_RESULT'),struct('characteristics',characteristics));return;
  endif
  source=numeric_read_input(getenv('GXDCF_SOURCE'),getenv('GXDCF_SOURCE_FORMAT'));
  train=reshape(train,[],2);source=reshape(source,[],2);
  model=getenv('GXDCF_MODEL');implicit=strcmp(model,'implicit');is_complex=strcmp(model,'complex_response');is_rational=strcmp(model,'rational');
  orientation=getenv('GXDCF_ORIENTATION');
  region_model=struct();region_selection=struct();
  if(strcmp(model,'regions')),[train,region_model,region_selection]=dataset_curve_fit_regions(train,orientation);endif
  [train,measurement_weights,measurement_receipt,xy_sigma]=dataset_curve_fit_measurements(train);
  odr=!isempty(xy_sigma);
  covariance=[];covariance_options=struct();
  if(!isempty(getenv('GXDCF_COVARIANCE_INPUT')))
    if(!isempty(measurement_weights)||!isempty(xy_sigma)),error('Full covariance cannot be combined with independent measurement errors');endif
    declared_covariance=gxtxt_scientific_result_read_v1(getenv('GXDCF_COVARIANCE_INPUT')).descriptor;
    covariance=gxtxt_scientific_array_read_v1(fileparts(getenv('GXDCF_COVARIANCE_INPUT')),declared_covariance);
    identities=numeric_read_row_ids(getenv('GXDCF_TRAIN_ROW_IDS'));
    if(rows(covariance)!=columns(covariance)||numel(identities)!=rows(train)||any(identities>=uint64(rows(covariance)))||numel(unique(identities))!=numel(identities)),error('Covariance axes lost their exact original training-row identities');endif
    positions=double(identities)+1;covariance=double(covariance(positions,positions));
    covariance_options=struct('covariance_semantics',getenv('GXDCF_COVARIANCE_SEMANTICS'),'singular_policy',getenv('GXDCF_COVARIANCE_SINGULAR'));
    fid=fopen(fullfile(fileparts(getenv('GXDCF_COVARIANCE_INPUT')),'covariance-used.bin'),'wb','ieee-le');if(fid<0),error('Cannot retain selected covariance');endif
    unwind_protect,written=fwrite(fid,covariance,'double');if(written!=numel(covariance)),error('Incomplete selected covariance write');endif;unwind_protect_cleanup,fclose(fid);end_unwind_protect
  endif
  measurement_options=struct();
  if(!isempty(measurement_weights)),measurement_options.weight_semantics=measurement_receipt.weight_semantics;endif
  if(strcmp(getenv('GXDCF_INFLUENCE'),'1'))
    if(odr||!any(strcmp(model,{'linear','polynomial'}))||!any(strcmp(orientation,{'y_of_x','x_of_y'}))),error('Exact influence requires ordinary or weighted linear/polynomial response fitting');endif
    measurement_options.influence_diagnostics=true;
  endif
  original_source=source;
  if(strcmp(orientation,'x_of_y')),train=train(:,[2,1]);source=source(:,[2,1]);endif
  polar_mode=strcmp(orientation,'r_of_theta');
  if(polar_mode)
    frame=struct('origin',[str2double(getenv('GXDCF_POLAR_ORIGIN_X')),str2double(getenv('GXDCF_POLAR_ORIGIN_Y'))],...
      'theta_zero',str2double(getenv('GXDCF_POLAR_ZERO')),'clockwise',str2double(getenv('GXDCF_POLAR_CLOCKWISE')),...
      'angle_unit',getenv('GXDCF_POLAR_UNIT'),'unwrap_policy',getenv('GXDCF_POLAR_POLICY'),'angle_cut',str2double(getenv('GXDCF_POLAR_CUT')));
    polar_source=gxtxt_numeric_v1('polar_coordinates',source(:,1),source(:,2),frame);
    if(any(polar_source.angle_undefined)),error('Radial fitting is undefined at the polar origin; move the fitting frame or use Parametric mode');endif
    angular_min=min(polar_source.theta);angular_max=max(polar_source.theta);
    tolerance=32*eps(max([abs(polar_source.theta);polar_source.period]));
    angular_delta=diff(polar_source.theta);
    if(angular_max-angular_min>polar_source.period+tolerance||!(all(angular_delta>tolerance)||all(angular_delta< -tolerance)))
      error('Source is not ordered and single-valued in this angular branch; choose another cut/unwrap policy or use Parametric mode');
    endif
    % Selected training points must use the same angular branch as the complete
    % source, even when the first selected point lies across the cut.
    training_frame=frame;training_frame.unwrap_policy='cut';
    polar_train=gxtxt_numeric_v1('polar_coordinates',train(:,1),train(:,2),training_frame);
    center=(angular_min+angular_max)/2;
    train_theta=center+mod(polar_train.theta-center+polar_source.period/2,polar_source.period)-polar_source.period/2;
    if(isequal(train,original_source))
      train_theta=polar_source.theta;
    elseif(!isempty(getenv('GXDCF_TRAIN_ROW_IDS'))&&!isempty(getenv('GXDCF_SOURCE_ROW_IDS')))
      train_row_file=getenv('GXDCF_TRAIN_ROW_IDS');if(!isempty(measurement_weights)),train_row_file=getenv('GXDCF_MEASUREMENT_FIT_ROWS_OUTPUT');endif
      train_ids=numeric_read_row_ids(train_row_file);source_ids=numeric_read_row_ids(getenv('GXDCF_SOURCE_ROW_IDS'));
      if(numel(unique(source_ids))!=numel(source_ids)),error('Radial selected fitting requires unambiguous exact source-row identity');endif
      [found,positions]=ismember(train_ids,source_ids);
      if(!all(found)||numel(positions)!=rows(train)),error('Radial selected input lost its exact source-row alignment');endif
      train_theta=polar_source.theta(positions);
    elseif(angular_max-angular_min>=polar_source.period-tolerance)
      error('Closed radial selected fitting requires exact source-row identity');
    endif
    train=[train_theta,polar_train.radius];source=polar_source.points;
  endif
  x=train(:,1);y=train(:,2);sx=source(:,1);sy=source(:,2);
  is_knot=any(strcmp(model,{'akima','bspline'}));
  new_model=any(strcmp(model,{'circular_arc','quadratic_bezier','cubic_bezier','pchip','smoothing_spline','akima','bspline','fourier','parametric_polynomial','parametric_spline'}));
  parametric=any(strcmp(model,{'circular_arc','quadratic_bezier','cubic_bezier','parametric_polynomial','parametric_spline'}));
  if(strcmp(getenv('GXDCF_DOMAIN_MODE'),'source')&&parametric)
    q=linspace(0,1,numel(sx)).';dx=q;grid_kind='parameter_source';
  elseif(strcmp(getenv('GXDCF_DOMAIN_MODE'),'source'))
    % The source fit curve is drawn in X order. Keep the original source order
    % separately for residuals and Dataset-row identity.
    dx=unique(sx);grid_kind='source';
  else
    grid=gxtxt_numeric_v1('uniform_grid',str2double(getenv('GXDCF_DOMAIN_MIN')),...
      str2double(getenv('GXDCF_DOMAIN_MAX')),str2double(getenv('GXDCF_DOMAIN_SAMPLES')),struct('mode','count'));
    dx=grid.x;grid_kind=ternary_grid(parametric);
    if(parametric),q=dx;endif
  endif
  if(numel(dx)<2),error('Output domain needs at least two distinct X values');endif
  export_domain=[min(dx),max(dx)];
  output_query=dx; % Original independent coordinate, or normalized parameter.
  % Resolve each coordinate independently over every value the worker evaluates.
  % A geometric model's parameter q is dimensionless and remains untouched.
  modes={getenv('GXDCF_TRANSLATION_U_MODE'),getenv('GXDCF_TRANSLATION_V_MODE')};
  manual=[str2double(getenv('GXDCF_TRANSLATION_U_DELTA')),str2double(getenv('GXDCF_TRANSLATION_V_DELTA'))];
  for axis=1:2
    if(isempty(modes{axis})),modes{axis}='auto';endif
  endfor
  u_values=[x;sx];if(!parametric),u_values=[u_values;dx];endif
  translation_u=gxtxt_numeric_v1('positive_translation',u_values,struct('mode',modes{1},'delta',manual(1)));
  translation_v=gxtxt_numeric_v1('positive_translation',[y;sy],struct('mode',modes{2},'delta',manual(2)));
  du=translation_u.delta;dv=translation_v.delta;
  physical_observations=struct();
  if(!odr&&!parametric&&!polar_mode&&!implicit&&!is_complex)
    physical_observations=gxtxt_numeric_v1('fit_observation_signature',y,measurement_weights,dv,x);
  endif
  x=numeric_shift(x,du);sx=numeric_shift(sx,du);y=numeric_shift(y,dv);sy=numeric_shift(sy,dv);
  if(!parametric),dx=numeric_shift(dx,du);endif
  if(strcmp(getenv('GXDCF_PARAMETER_ACTION'),'prepare'))
    parameter_frame=struct();if(polar_mode),parameter_frame=frame;endif
    dataset_curve_fit_parameters('prepare',model,x,y,dx,du,dv,region_model,parameter_frame);return;
  endif
  initial=[];
  model_state_json='';
  numeric_model_state=struct();
  if(new_model)
    options=struct();evaluation_options=struct();
    if(is_knot)
      options=gxtxt_scientific_result_read_v1(getenv('GXDCF_KNOT_SETTINGS')).settings;
      evaluation_options.extrapolation=options.extrapolation;options=rmfield(options,'extrapolation');
    endif
    if(any(strcmp(model,{'parametric_polynomial','parametric_spline'})))
      options.parameterization=getenv('GXDCF_PARAMETERIZATION');options.topology=getenv('GXDCF_TOPOLOGY');
      options.degree=str2double(getenv('GXDCF_DEGREE'));
      if(!isempty(getenv('GXDCF_CLOSURE_TOLERANCE'))),options.closure_tolerance=str2double(getenv('GXDCF_CLOSURE_TOLERANCE'));endif
      if(strcmp(options.parameterization,'user_parameter'))
        path=getenv('GXDCF_TRAIN_PARAMETER');if(isempty(path)),error('User parameter mode requires an aligned Dataset parameter variable');endif
        fid=fopen(path,'rb');if(fid<0),error('Cannot open owned Numeric parameters');endif
        unwind_protect,options.user_parameter=fread(fid,Inf,'double',0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
        if(!isempty(getenv('GXDCF_USER_PERIOD'))),options.user_period=str2double(getenv('GXDCF_USER_PERIOD'));endif
      endif
    elseif(strcmp(model,'fourier'))
      options.order=str2double(getenv('GXDCF_DEGREE'));
      period=str2double(getenv('GXDCF_PERIOD'));
      if(isfinite(period)&&period>0),options.period=period;endif
      if(polar_mode&&!(isfinite(period)&&period>0)),options.period=polar_source.period;endif
    elseif(strcmp(model,'smoothing_spline'))
      options.smoothing_lambda=str2double(getenv('GXDCF_SMOOTHING'));
      settings_path=getenv('GXDCF_SMOOTHING_SETTINGS');
      if(!isempty(settings_path))
        settings=gxtxt_scientific_result_read_v1(settings_path).settings;
        for key=fieldnames(settings).',options.(key{1})=settings.(key{1});endfor
      endif
    endif
    numerical_operation='curve_model_fit';
    fit=gxtxt_numeric_v1('curve_model_fit',model,x,y,options);
    model_state_json=jsonencode(fit);
    coefficients=fit.parameters(:);converged=1;
    if(parametric)
      train_eval=gxtxt_numeric_v1('curve_model_residual',fit,x,y);
      source_eval=gxtxt_numeric_v1('curve_model_residual',fit,sx,sy);
      fitted=gxtxt_numeric_v1('curve_model_evaluate',fit,q);
      dx=fitted.x;fy=fitted.y;ty=train_eval.y;source_y=source_eval.y;
    else
      train_eval=gxtxt_numeric_v1('curve_model_evaluate',fit,x);
      source_eval=gxtxt_numeric_v1('curve_model_evaluate',fit,sx,evaluation_options);
      fitted=gxtxt_numeric_v1('curve_model_evaluate',fit,dx,evaluation_options);
      ty=train_eval.y;source_y=source_eval.y;fy=fitted.y;
    endif
  else
    if(!any(strcmp(model,{'linear','polynomial','components','regions','formula','rational','implicit','complex_response'})))
    initial=dlmread(getenv('GXDCF_INITIAL'),',');initial=initial(:);
    endif
  degree=str2double(getenv('GXDCF_DEGREE'));
  solver_options=struct('solver','auto','max_iterations',1200);
  if(!isempty(getenv('GXDCF_SOLVER_SETTINGS')))
    configured=gxtxt_scientific_result_read_v1(getenv('GXDCF_SOLVER_SETTINGS'));
    names=fieldnames(configured.solver);
    for k=1:numel(names),solver_options.(names{k})=configured.solver.(names{k});endfor
  endif
  declared=struct('kind',model);
  if(strcmp(model,'regions'))
    declared=region_model;initial=declared.initial_parameters;
    if(du!=0||dv!=0),error('Regional models require physical coordinates and zero translation');endif
  endif
  if(strcmp(model,'formula'))
    captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_FORMULA_RECIPE'));
    declared=gxtxt_numeric_v1('fit_formula_compose',captured.recipe);initial=declared.initial_parameters;
    if(du!=0||dv!=0),error('Formula models require physical coordinates and zero translation');endif
  endif
  if(strcmp(model,'components'))
    captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_COMPONENT_RECIPE'));
    declared=gxtxt_numeric_v1('fit_model_compose',captured.recipe);initial=declared.initial_parameters;
    translation_policy=declared.input_constraints.translation_policy;
    if((!strcmp(translation_policy,'allowed')&&du!=0)||(strcmp(translation_policy,'forbid_translation')&&dv!=0))
      error('Physical component model forbids these coordinate translations; use the declared absolute units and zero translation');
    endif
  endif
  if(is_rational)
    if(odr||!isempty(covariance)||du!=0||dv!=0),error('Rational fitting requires untranslated physical response coordinates and independent response uncertainty');endif
    captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_RATIONAL_RECIPE'));declared=gxtxt_numeric_v1('rational_model_compose',captured.recipe);
    if(!exist('configured','var')||!isfield(configured.solver,'max_iterations')),solver_options.max_iterations=400;endif
    if(!isfield(solver_options,'max_seconds')),solver_options.max_seconds=30;endif
    for item=fieldnames(solver_options).',if(strncmp(item{1},'multistart_',11)||any(strcmp(item{1},{'loss','loss_scale'}))),solver_options=rmfield(solver_options,item{1});endif;endfor
    if(!isempty(measurement_weights)),solver_options.weights=measurement_weights;solver_options.weight_semantics=measurement_receipt.weight_semantics;endif
    fit=gxtxt_numeric_v1('rational_fit',declared,x,y,solver_options);numerical_operation='rational_fit';numeric_model_state=fit.solver_model;
    coefficients=fit.parameters(:);converged=fit.converged;ty=fit.predicted;
    extrapolation=getenv('GXDCF_RATIONAL_EXTRAPOLATION');if(isempty(extrapolation)),extrapolation='error';endif
    rational_evaluation=gxtxt_numeric_v1('rational_residuals',fit.model,sx,sy,struct('extrapolation',extrapolation));source_y=rational_evaluation.predicted;
    fy=gxtxt_numeric_v1('rational_evaluate',fit.model,dx,struct('extrapolation',extrapolation)).predicted;
  elseif(is_complex)
    if(odr||!isempty(covariance)||!isempty(measurement_weights)||du!=0||dv!=0||!strcmp(orientation,'y_of_x')),error('Complex responses require physical frequency coordinates and their explicit Cartesian covariance');endif
    if(exist('configured','var')&&!isfield(configured.solver,'max_iterations')),solver_options.max_iterations=400;endif
    if(!isfield(solver_options,'max_seconds')),solver_options.max_seconds=30;endif
    complex_result=dataset_curve_fit_complex(train,source,dx,solver_options);
    fit=complex_result.fit;numerical_operation='complex_fit';numeric_model_state=fit.solver_model;
    coefficients=fit.parameters(:);converged=fit.converged;ty=complex_result.training_y;source_y=complex_result.source_y;fy=complex_result.output_y;
    model_state_json=jsonencode(complex_result.saved);
    for role={'training','source'}
      name=role{1};numeric_write_output(fullfile(fileparts(getenv('GXDCF_RESULT')),['complex-' name '-observations.bin']),complex_result.([name '_observed_components']));
      numeric_write_output(fullfile(fileparts(getenv('GXDCF_RESULT')),['complex-' name '-covariance.bin']),complex_result.([name '_covariance'])(:));
    endfor
  elseif(implicit)
    if(odr||!isempty(covariance)||!isempty(measurement_weights)||du!=0||dv!=0),error('Implicit equations require physical coordinates without separate measurement weights');endif
    captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_IMPLICIT_RECIPE'));declared=gxtxt_numeric_v1('implicit_model_compose',captured.recipe);
    branch=captured.branch;physical_train=[x,y];physical_source=[sx,sy];
    if(strcmp(orientation,'x_of_y')),physical_train=physical_train(:,[2,1]);physical_source=physical_source(:,[2,1]);endif
    if(numel(dx)>256),error('Implicit branch output is bounded to256 points; choose an explicit Output range with2..256 samples');endif
    if(exist('configured','var')&&!isfield(configured.solver,'max_iterations')),solver_options.max_iterations=400;endif
    if(!isfield(solver_options,'max_seconds')),solver_options.max_seconds=30;endif
    for item=fieldnames(solver_options).',if(strncmp(item{1},'multistart_',11)),solver_options=rmfield(solver_options,item{1});endif;endfor
    fit=gxtxt_numeric_v1('implicit_fit',declared,physical_train(:,1),physical_train(:,2),solver_options);
    numerical_operation='implicit_fit';numeric_model_state=fit.equation_model;coefficients=fit.parameters(:);converged=fit.converged;ty=fit.equation_values;
    source_y=gxtxt_numeric_v1('implicit_evaluate',fit.model,physical_source(:,1),physical_source(:,2)).equation_values;
    fy=NaN(size(dx));branch.derivative=false;
    for first=1:64:numel(dx)
      last=min(first+63,numel(dx));found=gxtxt_numeric_v1('implicit_query',fit.model,dx(first:last),branch);
      if(!all(found.valid)),error('Declared implicit output branch is unavailable: %s',found.reasons{find(!found.valid,1)});endif
      fy(first:last)=found.predicted;
    endfor
  elseif(!isempty(covariance))
    if(strcmp(model,'linear'))
      numerical_operation='generalized_least_squares';fit=gxtxt_numeric_v1(numerical_operation,[ones(numel(x),1),x],y,covariance,covariance_options);
      coefficients=fit.coefficients([2,1]);polynomial=struct('coefficients',coefficients);
    elseif(strcmp(model,'polynomial'))
      numerical_operation='polynomial_gls';fit=gxtxt_numeric_v1(numerical_operation,x,y,degree,covariance,covariance_options);
      coefficients=fit.coefficients;polynomial=struct('coefficients',coefficients,'scaled_coefficients',fit.scaled_coefficients,'x_center',fit.x_center,'x_scale',fit.x_scale);
    else,error('Full covariance requires a linear or polynomial model');endif
    polynomial.kind='polynomial_export';model_state_json=jsonencode(polynomial);
    ty=fit.predicted;fy=gxtxt_numeric_v1('polynomial_evaluate',polynomial,dx).yq;source_y=gxtxt_numeric_v1('polynomial_evaluate',polynomial,sx).yq;converged=1;
  elseif(odr)
    if(!any(strcmp(model,{'linear','polynomial','exponential','power_law','gaussian','components','regions','formula'}))||!any(strcmp(orientation,{'y_of_x','x_of_y'}))),error('Unsupported model or orientation for both-axis uncertainty fitting');endif
    if(any(strcmp(model,{'linear','polynomial'}))),initial=dlmread(getenv('GXDCF_INITIAL'),',');initial=initial(:);endif
    if(strcmp(model,'polynomial')),declared.kind='polynomial_fit';endif
    solver_options.fit_geometry='orthogonal_xy';solver_options.sigma_x=xy_sigma(:,1);solver_options.sigma=xy_sigma(:,2);
    fit=gxtxt_numeric_v1('nonlinear_fit',declared,x,y,initial,solver_options);
    numerical_operation='nonlinear_fit';numeric_model_state=fit.model;coefficients=fit.parameters(:);
    if(strcmp(model,'linear')),coefficients=coefficients([2,1]);endif
    converged=fit.converged;
    evaluation=gxtxt_numeric_v1('nonlinear_evaluate',fit.model,dx);fy=evaluation.predicted;
    evaluation=gxtxt_numeric_v1('nonlinear_evaluate',fit.model,sx);source_y=evaluation.predicted;
    ty=fit.predicted;
  elseif(strcmp(model,'linear'))
    numerical_operation='linear_regression';
    fit=gxtxt_numeric_v1('linear_regression',x,y,measurement_weights,measurement_options);
    coefficients=[fit.slope;fit.intercept];
    model_state_json=jsonencode(struct('kind','polynomial_export','coefficients',coefficients));
    polynomial=struct('coefficients',coefficients);
    evaluate=@(q) gxtxt_numeric_v1('polynomial_evaluate',polynomial,q,struct());
    ty=evaluate(x);fy=evaluate(dx);source_y=evaluate(sx);
    ty=ty.yq;fy=fy.yq;source_y=source_y.yq;
    converged=1;
  elseif(strcmp(model,'polynomial'))
    numerical_operation='polynomial_fit';
    fit=gxtxt_numeric_v1('polynomial_fit',x,y,degree,measurement_weights,measurement_options);
    coefficients=fit.coefficients(:);
    model_state_json=jsonencode(struct('kind','polynomial_export','coefficients',coefficients,'scaled_coefficients',fit.scaled_coefficients,'x_center',fit.x_center,'x_scale',fit.x_scale));
    ty=gxtxt_numeric_v1('polynomial_evaluate',fit,x,struct());
    fy=gxtxt_numeric_v1('polynomial_evaluate',fit,dx,struct());
    source_y=gxtxt_numeric_v1('polynomial_evaluate',fit,sx,struct());
    ty=ty.yq;fy=fy.yq;source_y=source_y.yq;
    converged=1;
  else
    if(strcmp(model,'power_law'))
      if(any(x<=0)||any(sx<=0)||any(dx<=0))
        axis_name='physical X';if(strcmp(orientation,'x_of_y')),axis_name='physical Y';elseif(polar_mode),axis_name='theta';endif
        error('Power-law requires strictly positive transformed independent %s throughout training, residual evaluation and output domain',axis_name);
      endif
    elseif(!any(strcmp(model,{'exponential','gaussian','components','regions','formula'})))
      error('Unsupported fit model');
    endif
    numerical_operation='nonlinear_fit';
    if(!isempty(measurement_weights)),solver_options.weights=measurement_weights;solver_options.weight_semantics=measurement_receipt.weight_semantics;endif
    fit=gxtxt_numeric_v1('nonlinear_fit',declared,x,y,initial,solver_options);
    numeric_model_state=fit.model;
    coefficients=fit.parameters(:);converged=fit.converged;
    ty=fit.predicted;
    evaluation=gxtxt_numeric_v1('nonlinear_evaluate',fit.model,dx);fy=evaluation.predicted;
    evaluation=gxtxt_numeric_v1('nonlinear_evaluate',fit.model,sx);source_y=evaluation.predicted;
  endif
  endif
  fit_query=dx;
  % Retain the exact solver coordinates before physical display inversion.
  % Undoing then reapplying a translation need not preserve binary64 identity.
  if(!isempty(getenv('GXDCF_BOOTSTRAP_SETTINGS'))||!isempty(getenv('GXDCF_PROFILE_SETTINGS')))
    bootstrap_x=x;bootstrap_y=y;
  endif
  % Inverse exactly once, before physical residuals, Preview, accepted geometry,
  % CSV or Dataset publication. Model coefficients remain in documented fit-space.
  dx=numeric_shift(dx,-du);fy=numeric_shift(fy,-dv);
  x=numeric_shift(x,-du);sx=numeric_shift(sx,-du);y=numeric_shift(y,-dv);sy=numeric_shift(sy,-dv);
  ty=numeric_shift(ty,-dv);source_y=numeric_shift(source_y,-dv);
  if(parametric)
    train_eval.x=numeric_shift(train_eval.x,-du);train_eval.y=numeric_shift(train_eval.y,-dv);
    source_eval.x=numeric_shift(source_eval.x,-du);source_eval.y=numeric_shift(source_eval.y,-dv);
  endif
  if(parametric)
    train_metrics=train_eval;source_metrics=source_eval;
    residual=struct('values',source_eval.signed_residual);
    residual_rows=[sx,sy,source_y(:),residual.values(:),source_eval.x,source_eval.parameter];
    residual_columns='source_x,source_y,projected_y,signed_geometric_distance,projected_x,parameter';
  elseif(is_complex)
    % Scalar source trace deviations stay in their displayed physical unit.
    % Joint fit/evaluation diagnostics come only from the captured Numeric owners.
    train_metrics=struct('rmse',NaN,'r2',NaN,'mae',NaN,'max_abs_error',NaN,'response_variance',NaN);source_metrics=train_metrics;
    residual=gxtxt_numeric_v1('array_binary','subtract',sy,source_y,struct());
    residual_rows=[original_source,source_y(:),residual.values(:)];residual_columns='source_x,source_y,fitted_projection,projection_residual';
    evaluation=complex_result.evaluation;
    for channel=1:numel(fit.model.channel_ids)
      names={'observed_real','observed_imaginary','predicted_real','predicted_imaginary','residual_real','residual_imaginary','wrapped_phase_residual','phase_residual_valid'};
      observed=complex_result.source_observed_components(:,2*channel-1:2*channel);
      residual_rows=[residual_rows,observed,real(evaluation.predicted(:,channel)),imag(evaluation.predicted(:,channel)),real(evaluation.residuals(:,channel)),imag(evaluation.residuals(:,channel)),evaluation.wrapped_phase_residual(:,channel),double(evaluation.phase_residual_valid(:,channel))];
      for name=names,residual_columns=[residual_columns ',' fit.model.channel_ids{channel} '_' name{1}];endfor
    endfor
  elseif(implicit)
    train_metrics=gxtxt_numeric_v1('residual_metrics',zeros(size(ty)),ty,struct());
    source_metrics=gxtxt_numeric_v1('residual_metrics',zeros(size(source_y)),source_y,struct());
    residual=gxtxt_numeric_v1('array_binary','subtract',zeros(size(source_y)),source_y,struct());
    residual_rows=[original_source,source_y(:),residual.values(:)];
    residual_columns='source_x,source_y,equation_value,equation_residual';
  else
    if(odr)
      train_metrics=struct('rmse',NaN,'r2',NaN,'mae',NaN,'max_abs_error',NaN,'response_variance',NaN);
      corrected_x=numeric_shift(fit.adjusted_x,-du);corrected_y=numeric_shift(fit.predicted,-dv);
      corrections=[corrected_x,corrected_y,fit.coordinate_corrections,fit.normalized_corrections];
      fid=fopen(getenv('GXDCF_ORTHOGONAL_OUTPUT'),'wb');if(fid<0),error('Cannot create owned XY corrections');endif
      unwind_protect
        written=fwrite(fid,corrections.','double',0,'ieee-le');if(written!=numel(corrections)),error('Incomplete XY correction resource');endif
      unwind_protect_cleanup,fclose(fid);end_unwind_protect
    elseif(is_knot)
      % The constructor already computed these once through residual_metrics.
      train_metrics=struct('sse',fit.sse,'rmse',fit.rmse,'mae',fit.mae,'max_abs_error',fit.max_abs_error,'r2',NaN);
    else
      train_metrics=gxtxt_numeric_v1('residual_metrics',y,ty,struct());
    endif
    if(is_rational),source_metrics=rational_evaluation;residual=struct('values',rational_evaluation.residuals);
    else
    source_metrics=gxtxt_numeric_v1('residual_metrics',sy,source_y,struct());
    residual=gxtxt_numeric_v1('array_binary','subtract',sy,source_y,struct());
    endif
    residual_rows=[original_source,source_y(:),residual.values(:)];
    if(polar_mode)
      residual_rows=[original_source,source_y(:),residual.values(:),sy,sx];
      residual_columns='source_x,source_y,fitted_radius,radial_residual,observed_radius,theta';
    elseif(strcmp(orientation,'x_of_y'))
      residual_columns='source_x,source_y,fitted_x,x_residual';
    else
    residual_columns='source_x,source_y,fitted_y,y_residual';
    endif
  endif
  if(polar_mode)
    if(any(fy<0)||any(source_y<0)),error('Radial model predicts a negative radius; choose another model or angular interval');endif
    physical=gxtxt_numeric_v1('cartesian_coordinates',dx,fy,frame);
    output_topology='open';
    extent=max(max(physical.points)-min(physical.points));
    if(norm(physical.points(end,:)-physical.points(1,:))<=1e-9*max(1,extent)),output_topology='closed';endif
  endif
  model_state_bytes=numel(unicode2native(model_state_json,'UTF-8'));
  model_state_external=strcmp(getenv('GXDCF_BINARY_OUTPUT'),'1')&&model_state_bytes>65536;
  if(model_state_external)
    fid=fopen(getenv('GXDCF_MODEL_STATE'),'wb');if(fid<0),error('Cannot create owned Numerical model state');endif
    unwind_protect
      bytes=unicode2native(model_state_json,'UTF-8');written=fwrite(fid,bytes,'uint8');
      if(written!=numel(bytes)),error('Incomplete Numerical model state');endif
    unwind_protect_cleanup,fclose(fid);end_unwind_protect
  endif
  parameters_external=model_state_external&&numel(coefficients)>4096;
  % Carry bounded Numeric-owned facts; interpretation belongs to the public CORE
  % statistical result API. Never reorder covariance separately from parameters.
  statistical_fit=struct('operation',numerical_operation);
  for field={'n','p','rank','dof','edf','smoothing_lambda','gcv_score','gcv_available','smoothing_selection','trace_method','precision','workspace_bytes_bound','smoother_dof_convention','residual_mean_dof','smoother_trace_squared','residual_variance_dof','sse','rmse','residual_rmse','response_rmse','observation_signature','knot_summary','mae','max_abs_error','rational_summary','complex_summary','implicit_summary','regional_fit','response_variance','r_squared','adjusted_r_squared','reduced_chi_squared','covariance','standard_errors','condition_number','scaled_coefficients','scaled_covariance','x_center','x_scale','converged','solver','solver_receipt','fit_geometry','free_parameter_count','fixed_mask','active_bounds','response_count','loss','weight_semantics','has_intercept','covariance_scale','status'}
    if(isfield(fit,field{1})),statistical_fit.(field{1})=fit.(field{1});endif
  endfor
  if(!isempty(covariance)),statistical_fit.gls_summary=fit.summary;endif
  if(isfield(fit,'coefficients')),parameter_values=fit.coefficients(:);elseif(isfield(fit,'parameters')),parameter_values=fit.parameters(:);else parameter_values=coefficients;endif
  if(numel(parameter_values)<=4096),statistical_fit.parameter_values=parameter_values;endif
  addpath(getenv('GXDCF_CORE_OCTAVE_DIR'));
  % Scalar metrics only; the full source residual arrays stay in binary resources.
  statistical_metrics=struct('n',numel(x),'rmse',train_metrics.rmse,'r_squared',train_metrics.r2);
  source_statistical_metrics=struct('n',numel(sx),'rmse',source_metrics.rmse,'r_squared',source_metrics.r2);
  for metric={'mae','max_abs_error'}
    name=metric{1};statistical_metrics.(name)=train_metrics.(name);source_statistical_metrics.(name)=source_metrics.(name);
  endfor
  if(isfield(train_metrics,'response_variance')),statistical_metrics.response_variance=train_metrics.response_variance;source_statistical_metrics.response_variance=source_metrics.response_variance;endif
  facts=struct('fit',statistical_fit,'training',statistical_metrics,'evaluation',source_statistical_metrics);
  if(is_knot)
    facts.knot_evaluation=struct('operation','residual_metrics','n',numel(sx),'sse',source_metrics.sse,'rmse',source_metrics.rmse,'mae',source_metrics.mae,'max_abs_error',source_metrics.max_abs_error);
  endif
  if(is_rational)
    raw=rational_evaluation;bounded=struct('operation','rational_residuals','parameter_values',fit.parameters(:));
    for field={'n','sse','rmse','mae','max_abs_error','r2','response_variance','weight_semantics','rational_summary'},if(isfield(raw,field{1})),bounded.(field{1})=raw.(field{1});endif;endfor
    facts.rational_evaluation=bounded;
  endif
  if(is_complex)
    facts.training=struct('n',fit.n);facts.evaluation=struct('n',complex_result.evaluation.n);
    raw=complex_result.evaluation;bounded=struct('operation','complex_residuals','parameter_values',fit.parameters(:));
    for field={'n','p','sse','rmse','mae','max_abs_error','weight_semantics','covariance_scale','complex_summary'},bounded.(field{1})=raw.(field{1});endfor
    facts.complex_evaluation=bounded;facts.complex_model_state=fit.model;
    facts.complex_conversion=struct('training',{complex_result.training_conversion},'evaluation',{complex_result.source_conversion});
  endif
  if(strcmp(model,'regions'))
    if(numel(fit.source_row_positions)!=numel(x)||!isequal(fit.source_row_positions,(1:numel(x))')),error('Joint regional fit changed the already aligned training rows');endif
    facts.fit.regional_fit=fit.regional_fit;facts.region_selection=region_selection;
    numeric_write_output(fullfile(fileparts(getenv('GXDCF_REGION_RECIPE')),'region_membership.bin'),fit.region_indices);
  endif
  if(!isempty(fieldnames(physical_observations))),facts.physical_observation_signature=physical_observations;endif
  if(!isempty(measurement_weights)||odr)
    facts.measurement=measurement_receipt;
    % Training fit criteria retain Numeric's weighted definition. Descriptive
    % residual RMSE/MAE remain in physical units over the retained fit rows.
    facts.training.r_squared=fit.r_squared;facts.training.response_variance=fit.response_variance;
  endif
  if(!isempty(fieldnames(numeric_model_state))),facts.numeric_model_state=numeric_model_state;endif
  if(!isempty(getenv('GXDCF_PREDICTION_SETTINGS')))
    configured=gxtxt_scientific_result_read_v1(getenv('GXDCF_PREDICTION_SETTINGS'));
    if(!strcmp(configured.settings.prediction_band,'none'))
      facts=dataset_curve_fit_prediction(facts,model,fit,fit_query,dx,dv,orientation,configured.settings);
    endif
  endif
  if(isfield(fit,'influence')),facts.influence=dataset_curve_fit_influence(fit.influence,dv);endif
  if(!isempty(getenv('GXDCF_BOOTSTRAP_SETTINGS')))
    bootstrap=gxtxt_scientific_result_read_v1(getenv('GXDCF_BOOTSTRAP_SETTINGS'));
    facts=dataset_curve_fit_bootstrap(facts,model,fit,bootstrap_x,bootstrap_y,measurement_weights,orientation,configured.settings,bootstrap.settings);
  endif
  if(!isempty(getenv('GXDCF_PROFILE_SETTINGS')))
    profile=gxtxt_scientific_result_read_v1(getenv('GXDCF_PROFILE_SETTINGS'));
    facts=dataset_curve_fit_profile(facts,model,fit,bootstrap_x,bootstrap_y,measurement_weights,orientation,configured.settings,profile.settings);
  endif
  facts.input_policy=dataset_curve_fit_preprocessing(model,fit,measurement_receipt);
  gxtxt_scientific_result_write_v1(getenv('GXDCF_STATISTICS'),facts);

  if(parametric)
    training_domain=[0,1];training_domain_basis='normalized_fitted_parameter';
  else
    training_receipt=gxtxt_numeric_v1('positive_translation',train(:,1),struct('mode','off'));
    training_domain=training_receipt.original_bounds;training_domain_basis='exact_eligible_observations';
  endif
  below=gxtxt_numeric_v1('array_compare','less_than',output_query,training_domain(1));
  above=gxtxt_numeric_v1('array_compare','greater_than',output_query,training_domain(2));
  outside=gxtxt_numeric_v1('array_mask','logical_or',below.values,above.values).values;
  outside_count=gxtxt_numeric_v1('array_reduce','count_true',outside).values;
  numeric_write_output(fullfile(fileparts(getenv('GXDCF_RESULT')),'output_domain.bin'),[output_query,double(outside)]);
  output=getenv('GXDCF_RESULT');
  fid=fopen(output,'w');if(fid<0),error('Cannot write fit result');endif
  unwind_protect
    fprintf(fid,'model\t%s\n',model);
    fprintf(fid,'orientation\t%s\n',orientation);
    fprintf(fid,'export_domain\t%.17g,%.17g\n',export_domain);
    fprintf(fid,'training_domain\t%.17g,%.17g\n',training_domain);
    fprintf(fid,'training_domain_basis\t%s\n',training_domain_basis);
    fprintf(fid,'output_extrapolated_count\t%d\n',outside_count);
    for axis=1:2
      receipt=translation_u;axis_name='u';if(axis==2),receipt=translation_v;axis_name='v';endif
      fprintf(fid,'translation_%s_mode\t%s\ntranslation_%s_delta\t%.17g\n',axis_name,receipt.mode,axis_name,receipt.delta);
      fprintf(fid,'translation_%s_original_bounds\t%.17g,%.17g\n',axis_name,receipt.original_bounds);
      fprintf(fid,'translation_%s_transformed_bounds\t%.17g,%.17g\n',axis_name,receipt.transformed_bounds);
      fprintf(fid,'translation_%s_margin\t%.17g\n',axis_name,receipt.margin);
    endfor
    fprintf(fid,'translation_algorithm\tadditive_positive_v1\ntranslation_inverse_applied\t1\n');
    if(polar_mode)
      fprintf(fid,'coordinate_mode\tpolar\nindependent_axis\ttheta\nangle_unit\t%s\nunwrap_policy\t%s\n',frame.angle_unit,frame.unwrap_policy);
      fprintf(fid,'angular_min\t%.17g\nangular_max\t%.17g\ntopology\t%s\n',angular_min,angular_max,output_topology);
    endif
    if(any(strcmp(model,{'parametric_polynomial','parametric_spline'})))
      fprintf(fid,'topology\t%s\nparameterization\t%s\n',fit.topology,fit.parameterization);
    endif
    fprintf(fid,'parameters\t');
    if(!isempty(coefficients)&&!parameters_external)
      fprintf(fid,'%.17g',coefficients(1));
      for i=2:numel(coefficients),fprintf(fid,',%.17g',coefficients(i));endfor
    endif
    fprintf(fid,'\nconverged\t%d\n',converged);
    fprintf(fid,'output_n\t%d\nsource_n\t%d\ngrid_kind\t%s\nparametric\t%d\n',numel(dx),numel(sx),grid_kind,parametric);
    if(parametric)
      fprintf(fid,'residual_convention\t%s\n',source_eval.residual_convention);
      fprintf(fid,'r2_convention\t%s\n',source_eval.r2_convention);
      fprintf(fid,'zero_normal_sign_policy\t%s\n',source_eval.zero_normal_sign_policy);
    else
      if(implicit),fprintf(fid,'residual_convention\tzero_minus_equation_value_at_observed_coordinates\n');
      elseif(polar_mode),fprintf(fid,'residual_convention\tradial_difference_at_source_theta\n');
      elseif(strcmp(orientation,'x_of_y')),fprintf(fid,'residual_convention\tx_difference_at_source_y\n');else fprintf(fid,'residual_convention\ty_difference_at_source_x\n');endif
    endif
    fprintf(fid,'residual_stride\t%d\nresidual_columns\t%s\n',columns(residual_rows),residual_columns);
    fprintf(fid,'model_state_bytes\t%d\nparameter_count\t%d\n',model_state_bytes,numel(coefficients));
    if(model_state_external),fprintf(fid,'model_state_storage\tdocument_resource\n');
    elseif(!isempty(model_state_json)),fprintf(fid,'model_state_json\t%s\n',model_state_json);endif
    if(parameters_external),fprintf(fid,'parameters_storage\tmodel_state_resource\n');endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  fitted_points=[dx,fy(:)];
  if(strcmp(orientation,'x_of_y')),fitted_points=fitted_points(:,[2,1]);endif
  if(polar_mode),fitted_points=physical.points;endif
  if(strcmp(getenv('GXDCF_BINARY_OUTPUT'),'1'))
    numeric_write_output(getenv('GXDCF_FITTED'),fitted_points);
    numeric_write_output(getenv('GXDCF_RESIDUAL'),residual_rows);
  else
    dlmwrite(getenv('GXDCF_FITTED'),fitted_points,'delimiter',',','precision','%.17g');
    dlmwrite(getenv('GXDCF_RESIDUAL'),residual_rows,'delimiter',',','precision','%.17g');
  endif
endfunction

function result=numeric_shift(values,delta)
  mapped=gxtxt_numeric_v1('array_binary','add',values,delta,struct());result=mapped.values;
endfunction

function ids=numeric_read_row_ids(path)
  fid=fopen(path,'rb');if(fid<0),error('Cannot open owned exact source rows');endif
  unwind_protect,ids=fread(fid,Inf,'uint64=>uint64',0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function rows=numeric_read_input(path,format)
  if(strcmp(format,'interleaved_float64_le'))
    fid=fopen(path,'rb');if(fid<0),error('Cannot open bounded Numeric input');endif
    unwind_protect
      values=fread(fid,Inf,'double',0,'ieee-le');
      if(mod(numel(values),2)!=0),error('Incomplete Numeric XY input');endif
      rows=reshape(values,2,[]).';
    unwind_protect_cleanup
      fclose(fid);
    end_unwind_protect
  else
    rows=dlmread(path,',');
  endif
endfunction

function numeric_write_output(path,rows)
  fid=fopen(path,'wb');if(fid<0),error('Cannot create bounded Numeric result');endif
  unwind_protect
    n=fwrite(fid,rows.','double',0,'ieee-le');
    if(n!=numel(rows)),error('Incomplete Numeric result write');endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function kind=ternary_grid(parametric)
  if(parametric),kind='parameter_range';else kind='range';endif
endfunction
