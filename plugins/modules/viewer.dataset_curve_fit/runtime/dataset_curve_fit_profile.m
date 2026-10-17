% SPDX-License-Identifier: GPL-3.0-or-later
% Fitter data adaptation; the public Numeric/CORE owners define the inference.
function facts=dataset_curve_fit_profile(facts,model,fit,X,y,weights,orientation,settings,profile)
  addpath(fullfile(getenv('GXDCF_CORE_OCTAVE_DIR'),'util'));
  context=settings.context;context.orientation=orientation;context.constraints='none';context.coefficient_space='translated_fit';context.sample_role='training';context.noise_model=settings.noise_model;
  raw=facts.fit;if(isfield(facts,'numeric_model_state')),raw.model=facts.numeric_model_state;endif
  model_id=['math.numeric.',model];if(any(strcmp(model,{'components','regions','formula'}))),model_id='math.numeric.nonlinear';endif
  source=gxtxt_statistics_v1('from_numeric',model_id,raw.operation,raw,context,facts.training);
  plan=gxtxt_statistics_v1('profile_plan',source,profile);
  if(!strcmp(plan.status,'value')),error('GXTXT:Fitter:Profile','Requested profile likelihood is unavailable: %s',plan.reason);endif
  options=struct();if(!isempty(weights)),options.weights=weights;endif
  result=gxtxt_numeric_v1('fit_profile',fit.model,X,y,plan,options);
  gxtxt_statistics_v1('profile_interpretation',source,result);
  directory=fileparts(getenv('GXDCF_STATISTICS'));
  write_owned(fullfile(directory,'profile_values.bin'),result.trial_values.','double');
  write_owned(fullfile(directory,'profile_parameters.bin'),result.trial_parameters.','double');
  write_owned(fullfile(directory,'profile_status.bin'),result.trial_status,'uint8');
  write_owned(fullfile(directory,'profile_messages.json'),unicode2native(jsonencode(result.trial_messages),'UTF-8'),'uint8');
  facts.profile=result.summary;
endfunction
function write_owned(path,values,type)
  fid=fopen(path,'wb');if(fid<0),error('Cannot create owned profile resource');endif
  unwind_protect
    count=fwrite(fid,values,type,0,'ieee-le');if(count!=numel(values)),error('Incomplete profile resource');endif
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
