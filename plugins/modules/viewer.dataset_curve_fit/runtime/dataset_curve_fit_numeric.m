% Data-only worker for viewer.dataset_curve_fit. All fitting, evaluation and
% residual metrics are delegated to the public NUMERIC_API_v1 dispatcher.
% SPDX-License-Identifier: GPL-3.0-or-later
function dataset_curve_fit_numeric()
  addpath(getenv('GXDCF_NUMERIC_API_DIR'));
  train=numeric_read_input(getenv('GXDCF_TRAIN'),getenv('GXDCF_TRAIN_FORMAT'));
  source=numeric_read_input(getenv('GXDCF_SOURCE'),getenv('GXDCF_SOURCE_FORMAT'));
  train=reshape(train,[],2);source=reshape(source,[],2);
  model=getenv('GXDCF_MODEL');
  orientation=getenv('GXDCF_ORIENTATION');
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
      train_ids=numeric_read_row_ids(getenv('GXDCF_TRAIN_ROW_IDS'));source_ids=numeric_read_row_ids(getenv('GXDCF_SOURCE_ROW_IDS'));
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
  new_model=any(strcmp(model,{'circular_arc','quadratic_bezier','cubic_bezier','pchip','smoothing_spline','fourier','parametric_polynomial','parametric_spline'}));
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
  initial=[];
  model_state_json='';
  if(new_model)
    options=struct();
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
    endif
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
      source_eval=gxtxt_numeric_v1('curve_model_evaluate',fit,sx);
      fitted=gxtxt_numeric_v1('curve_model_evaluate',fit,dx);
      ty=train_eval.y;source_y=source_eval.y;fy=fitted.y;
    endif
  else
    if(!any(strcmp(model,{'linear','polynomial'})))
    initial=dlmread(getenv('GXDCF_INITIAL'),',');initial=initial(:);
    endif
  degree=str2double(getenv('GXDCF_DEGREE'));
  if(strcmp(model,'linear'))
    fit=gxtxt_numeric_v1('linear_regression',x,y,[],struct());
    coefficients=[fit.slope;fit.intercept];
    polynomial=struct('coefficients',coefficients);
    evaluate=@(q) gxtxt_numeric_v1('polynomial_evaluate',polynomial,q,struct());
    ty=evaluate(x);fy=evaluate(dx);source_y=evaluate(sx);
    ty=ty.yq;fy=fy.yq;source_y=source_y.yq;
    converged=1;
  elseif(strcmp(model,'polynomial'))
    fit=gxtxt_numeric_v1('polynomial_fit',x,y,degree,[],struct());
    coefficients=fit.coefficients(:);
    ty=gxtxt_numeric_v1('polynomial_evaluate',fit,x,struct());
    fy=gxtxt_numeric_v1('polynomial_evaluate',fit,dx,struct());
    source_y=gxtxt_numeric_v1('polynomial_evaluate',fit,sx,struct());
    ty=ty.yq;fy=fy.yq;source_y=source_y.yq;
    converged=1;
  else
    if(strcmp(model,'exponential'))
      callback=@(p,q) p(1)*exp(p(2)*q)+p(3);
    elseif(strcmp(model,'power_law'))
      if(any(x<=0)||any(sx<=0)||any(dx<=0)),error('Power-law requires positive X throughout the fit and output domain');endif
      callback=@(p,q) p(1)*q.^p(2);
    elseif(strcmp(model,'gaussian'))
      callback=@(p,q) p(1)*exp(-0.5*((q-p(2))/p(3)).^2)+p(4);
    else
      error('Unsupported fit model');
    endif
    fit=gxtxt_numeric_v1('nonlinear_fit',callback,x,y,initial,struct('solver','auto','max_iterations',1200));
    coefficients=fit.parameters(:);converged=fit.converged;
    ty=numeric_evaluate(model,coefficients,x);
    fy=numeric_evaluate(model,coefficients,dx);
    source_y=numeric_evaluate(model,coefficients,sx);
  endif
  endif
  if(parametric)
    train_metrics=train_eval;source_metrics=source_eval;
    residual=struct('values',source_eval.signed_residual);
    residual_rows=[sx,sy,source_y(:),residual.values(:),source_eval.x,source_eval.parameter];
    residual_columns='source_x,source_y,projected_y,signed_geometric_distance,projected_x,parameter';
  else
    train_metrics=gxtxt_numeric_v1('residual_metrics',y,ty,struct());
    source_metrics=gxtxt_numeric_v1('residual_metrics',sy,source_y,struct());
    residual=gxtxt_numeric_v1('array_binary','subtract',sy,source_y,struct());
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
  output=getenv('GXDCF_RESULT');
  fid=fopen(output,'w');if(fid<0),error('Cannot write fit result');endif
  unwind_protect
    fprintf(fid,'model\t%s\n',model);
    fprintf(fid,'orientation\t%s\n',orientation);
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
    fprintf(fid,'\ntrain_n\t%d\ntrain_rmse\t%.17g\ntrain_r2\t%.17g\n',numel(x),train_metrics.rmse,train_metrics.r2);
    fprintf(fid,'source_rmse\t%.17g\nsource_r2\t%.17g\nconverged\t%d\n',source_metrics.rmse,source_metrics.r2,converged);
    fprintf(fid,'output_n\t%d\nsource_n\t%d\ngrid_kind\t%s\nparametric\t%d\n',numel(dx),numel(sx),grid_kind,parametric);
    if(parametric)
      fprintf(fid,'residual_convention\t%s\n',source_eval.residual_convention);
      fprintf(fid,'r2_convention\t%s\n',source_eval.r2_convention);
      fprintf(fid,'zero_normal_sign_policy\t%s\n',source_eval.zero_normal_sign_policy);
      fprintf(fid,'train_geometric_rmse\t%.17g\nsource_geometric_rmse\t%.17g\n',train_eval.rmse,source_eval.rmse);
      fprintf(fid,'train_max_geometric_distance\t%.17g\nsource_max_geometric_distance\t%.17g\n',train_eval.max_abs_error,source_eval.max_abs_error);
    else
      if(polar_mode),fprintf(fid,'residual_convention\tradial_difference_at_source_theta\n');
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

function y=numeric_evaluate(model,p,x)
  binary=@(name,a,b) gxtxt_numeric_v1('array_binary',name,a,b,struct());
  unary=@(name,a) gxtxt_numeric_v1('array_unary',name,a,struct());
  if(strcmp(model,'exponential'))
    v=binary('multiply',p(2),x);v=unary('exp',v.values);
    v=binary('multiply',p(1),v.values);v=binary('add',v.values,p(3));
  elseif(strcmp(model,'power_law'))
    v=binary('power',x,p(2));v=binary('multiply',p(1),v.values);
  else
    v=binary('subtract',x,p(2));v=binary('divide',v.values,p(3));
    v=unary('square',v.values);v=binary('multiply',-0.5,v.values);
    v=unary('exp',v.values);v=binary('multiply',p(1),v.values);
    v=binary('add',v.values,p(4));
  endif
  y=v.values(:);
endfunction
