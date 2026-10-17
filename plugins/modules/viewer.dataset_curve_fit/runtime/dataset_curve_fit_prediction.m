% Fitter data adaptation; public CORE and Numeric own inference and calculation.
% SPDX-License-Identifier: GPL-3.0-or-later
function facts=dataset_curve_fit_prediction(facts,model,fit,query,physical_query,response_delta,orientation,settings)
  addpath(fullfile(getenv('GXDCF_CORE_OCTAVE_DIR'),'util'));
  context=settings.context;context.orientation=orientation;context.constraints='none';
  context.coefficient_space='translated_fit';context.sample_role='training';context.noise_model=settings.noise_model;
  raw=facts.fit;if(isfield(facts,'numeric_model_state')),raw.model=facts.numeric_model_state;endif
  model_id=['math.numeric.',model];if(any(strcmp(model,{'components','regions','formula'}))),model_id='math.numeric.nonlinear';endif
  source=gxtxt_statistics_v1('from_numeric',model_id,raw.operation,raw,context,facts.training);
  parameter_plan=gxtxt_statistics_v1('parameter_inference_plan',source,settings.confidence);
  if(strcmp(parameter_plan.status,'value'))
    facts.parameter_uncertainty=gxtxt_numeric_v1('parameter_uncertainty',parameter_plan);
    source=gxtxt_statistics_v1('with_parameter_uncertainty',source,settings.confidence,facts.parameter_uncertainty);
  else
    source=gxtxt_statistics_v1('with_parameter_uncertainty',source,settings.confidence);
  endif
  plan=gxtxt_statistics_v1('prediction_inference_plan',source,settings.prediction_band,settings.confidence);
  facts.prediction_plan=plan;
  if(!strcmp(plan.status,'value')),return;endif
  if(isfield(fit,'fit_geometry')&&strcmp(fit.fit_geometry,'orthogonal_xy'))
    prediction_model=fit.model;
  elseif(strcmp(model,'linear'))
    prediction_model=struct('expression','intercept+slope*x','parameter_ids',{{'intercept','slope'}},'parameters',fit.coefficients);
  elseif(strcmp(model,'polynomial'))
    prediction_model=struct('kind','polynomial_fit','parameters',fit.coefficients);
  else
    prediction_model=fit.model;
  endif
  options=struct();
  for field={'prediction_sigma','prediction_weights'}
    if(!isempty(settings.(field{1}))),options.(field{1})=settings.(field{1});endif
  endfor
  prediction=gxtxt_numeric_v1('prediction_uncertainty',prediction_model,query,plan,options);
  % Validate the exact captured receipt before exporting physical-coordinate data.
  gxtxt_statistics_v1('prediction_interpretation',source,prediction);
  center=gxtxt_numeric_v1('array_binary','subtract',prediction.predicted,response_delta,struct());
  lower=gxtxt_numeric_v1('array_binary','subtract',prediction.lower,response_delta,struct('nonfinite','ieee'));
  upper=gxtxt_numeric_v1('array_binary','subtract',prediction.upper,response_delta,struct('nonfinite','ieee'));
  available=logical(prediction.bounds_available);
  if(any(!isfinite(center.values))||any(!isfinite(lower.values(available)))||any(!isfinite(upper.values(available))))
    error('GXTXT:Fitter:PredictionCoordinates','Physical interval coordinates are not finitely representable');
  endif
  rows=[physical_query(:),center.values,lower.values,upper.values,prediction.mean_standard_error,prediction.standard_error,prediction.observation_standard_deviation,prediction.bounds_available];
  fid=fopen(getenv('GXDCF_PREDICTION_OUTPUT'),'wb');if(fid<0),error('Cannot create owned prediction result');endif
  unwind_protect
    count=fwrite(fid,rows.','double',0,'ieee-le');if(count!=numel(rows)),error('Incomplete prediction result write');endif
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
  display_valid=available;
  facts.prediction_display_note='Boundary curves show the recorded pointwise interval; they do not form a simultaneous confidence region';
  if(strcmp(orientation,'r_of_theta'))
    display_valid=display_valid & lower.values>=0;
    if(any(available & !display_valid)),facts.prediction_display_note='Radial intervals crossing negative radius remain in the scientific columns; their Cartesian boundary display is omitted';endif
    frame=struct('origin',[str2double(getenv('GXDCF_POLAR_ORIGIN_X')),str2double(getenv('GXDCF_POLAR_ORIGIN_Y'))],...
      'theta_zero',str2double(getenv('GXDCF_POLAR_ZERO')),'clockwise',str2double(getenv('GXDCF_POLAR_CLOCKWISE')),...
      'angle_unit',getenv('GXDCF_POLAR_UNIT'),'unwrap_policy',getenv('GXDCF_POLAR_POLICY'),'angle_cut',str2double(getenv('GXDCF_POLAR_CUT')));
  endif
  if(any(display_valid))
    selected=find(display_valid);gaps=uint8([0;diff(selected)>1]);
    fid=fopen([getenv('GXDCF_PREDICTION_OUTPUT'),'.gaps'],'wb');if(fid<0),error('Cannot create interval gap identity');endif
    unwind_protect
      count=fwrite(fid,gaps,'uint8');if(count!=numel(gaps)),error('Incomplete interval gap identity');endif
    unwind_protect_cleanup,fclose(fid);end_unwind_protect
    for boundary={'lower','upper'}
      name=boundary{1};value=lower.values;if(strcmp(name,'upper')),value=upper.values;endif
      points=NaN(numel(query),2);
      if(strcmp(orientation,'r_of_theta'))
        converted=gxtxt_numeric_v1('cartesian_coordinates',physical_query(display_valid),value(display_valid),frame);points(display_valid,:)=converted.points;
      elseif(strcmp(orientation,'x_of_y'))
        points(display_valid,:)=[value(display_valid),physical_query(display_valid)];
      else
        points(display_valid,:)=[physical_query(display_valid),value(display_valid)];
      endif
      points=points(display_valid,:);
      fid=fopen([getenv('GXDCF_PREDICTION_OUTPUT'),'.',name],'wb');if(fid<0),error('Cannot create owned interval boundary');endif
      unwind_protect
        count=fwrite(fid,points.','double',0,'ieee-le');if(count!=numel(points)),error('Incomplete interval boundary write');endif
      unwind_protect_cleanup,fclose(fid);end_unwind_protect
    endfor
  endif
  for field={'predicted','mean_standard_error','observation_standard_deviation','standard_error','lower','upper','bounds_available','query_index'}
    prediction=rmfield(prediction,field{1});
  endfor
  facts.prediction_receipt=prediction;
endfunction
