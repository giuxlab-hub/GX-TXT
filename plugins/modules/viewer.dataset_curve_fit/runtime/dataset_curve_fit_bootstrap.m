% Fitter adaptation only: public CORE/Numeric own bootstrap inference/refits.
% SPDX-License-Identifier: GPL-3.0-or-later
function facts=dataset_curve_fit_bootstrap(facts,model,fit,X,y,weights,orientation,settings,bootstrap)
  addpath(fullfile(getenv('GXDCF_CORE_OCTAVE_DIR'),'util'));
  context=settings.context;context.orientation=orientation;context.constraints='none';
  context.coefficient_space='translated_fit';context.sample_role='training';context.noise_model=settings.noise_model;
  raw=facts.fit;if(isfield(facts,'numeric_model_state')),raw.model=facts.numeric_model_state;endif
  model_id=['math.numeric.',model];if(any(strcmp(model,{'components','regions','formula'}))),model_id='math.numeric.nonlinear';endif
  source=gxtxt_statistics_v1('from_numeric',model_id,raw.operation,raw,context,facts.training);
  plan=gxtxt_statistics_v1('bootstrap_plan',source,bootstrap);
  if(!strcmp(plan.status,'value')),error('GXTXT:Fitter:Bootstrap','Requested parameter bootstrap is unavailable: %s',plan.reason);endif
  if(strcmp(model,'linear')),fitted=struct('kind','linear','parameters',fit.coefficients);
  elseif(strcmp(model,'polynomial')),fitted=struct('kind','polynomial_fit','parameters',fit.coefficients);
  else fitted=fit.model;endif
  options=struct();if(!isempty(weights)),options.weights=weights;endif
  result=gxtxt_numeric_v1('fit_bootstrap',fitted,X,y,plan,options);
  % Validate before exporting any retained draw. Meaning is captured again by
  % the host against the authoritative retained training result and provenance.
  gxtxt_statistics_v1('bootstrap_interpretation',source,result);
  directory=fileparts(getenv('GXDCF_STATISTICS'));
  write_owned(fullfile(directory,'bootstrap_parameters.bin'),result.parameter_samples.','double');
  write_owned(fullfile(directory,'bootstrap_status.bin'),result.replicate_status,'uint8');
  write_owned(fullfile(directory,'bootstrap_seed.bin'),result.replicate_seed,'uint32');
  facts.bootstrap=rmfield(result,{'parameter_samples','replicate_status','replicate_seed'});
endfunction
function write_owned(path,values,type)
  fid=fopen(path,'wb');if(fid<0),error('Cannot create owned bootstrap resource');endif
  unwind_protect
    count=fwrite(fid,values,type,0,'ieee-le');if(count!=numel(values)),error('Incomplete bootstrap resource');endif
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
