% Fitter data adaptation only; Numeric owns logarithmic calculations.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=dataset_curve_fit_log_response_v1(family,action,geometry,prediction,unused,settings)
  if(!strcmp(family,'log_response')||!strcmp(action,'retransform')||!isa(geometry,'double')||!isreal(geometry)||rows(geometry)!=2||columns(geometry)<1||columns(geometry)>1000000||any(!isfinite(geometry(:))))
    error('GXTXT:Fitter:LogResponse','Owned log-response geometry must contain 1..1000000 finite XY rows');
  endif
  if(strcmp(settings.orientation,'y_of_x')),query=geometry(1,:)';response=geometry(2,:)';
  elseif(strcmp(settings.orientation,'x_of_y')),query=geometry(2,:)';response=geometry(1,:)';
  else error('GXTXT:Fitter:LogResponse','A logarithmic result requires one explicit scalar response');endif
  options=struct('reference',settings.reference);
  if(isfield(settings,'log_standard_deviation')),options.log_standard_deviation=settings.log_standard_deviation;endif
  coordinate_source='accepted_geometry';
  if(!isempty(prediction))
    if(!isa(prediction,'double')||!isreal(prediction)||!isequal(size(prediction),[8,numel(query)])||!isequal(prediction(1,:)',query)||any(abs(prediction(2,:)'-response)>8*eps.*max(1,abs(response))))
      error('GXTXT:Fitter:LogResponse','Captured log prediction rows differ from accepted geometry');
    endif
    response=prediction(2,:)';options.lower=prediction(3,:)';options.upper=prediction(4,:)';
    if(any(prediction(8,:)!=double(isfinite(options.lower')&isfinite(options.upper')))),error('GXTXT:Fitter:LogResponse','Captured interval availability differs from its bound rows');endif
    options.interval_kind=settings.interval_kind;options.confidence=settings.confidence;
    coordinate_source='captured_prediction';
  endif
  out=gxtxt_numeric_v1('log_response_retransform',response,options);
  out.query=query;out.coordinate_source=coordinate_source;
endfunction
