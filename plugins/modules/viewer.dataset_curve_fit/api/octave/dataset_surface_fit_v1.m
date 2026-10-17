% Canonical resource adaptation only. Numeric and CORE own scientific meaning.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=dataset_surface_fit_v1(mode)
  if(nargin!=1||!strcmp(mode,'file')),error('GXTXT:Fitter:Surface','Use the owned surface request envelope');endif
  core=getenv('GXDCF_CORE_OCTAVE_DIR');addpath(core);
  for part={'util','io','analysis'},addpath(fullfile(core,part{1}));endfor
  addpath(getenv('GXDCF_NUMERIC_API_DIR'));
  request_path=getenv('GXDCF_SURFACE_REQUEST');request=gxtxt_scientific_result_read_v1(request_path);
  workspace=fileparts(request_path);action=request.action;
  if(strcmp(action,'fit'))
    model=gxtxt_numeric_v1('surface_model_compose',request.recipe);
    values=struct();
    for key={'x','y','z','sigma'}
      field=key{1};if(isfield(request.source,field)),values.(field)=gxtxt_scientific_array_read_v1(workspace,request.source.(field));endif
    endfor
    settings=request.settings;if(isfield(values,'sigma')),settings.sigma=values.sigma;endif
    fit=gxtxt_numeric_v1('surface_fit',model,values.x,values.y,values.z,settings);
    saved=gxtxt_numeric_v1('surface_model_state',fit.model);
    gxtxt_scientific_result_write_v1(fullfile(workspace,'surface-state.ini'),saved,true);
    observations=[fit.observed_coordinates,fit.observed_response,fit.predicted,fit.residuals];
    write_array(fullfile(workspace,'surface-observations.bin'),observations,'double');
    write_array(fullfile(workspace,'surface-indices.bin'),fit.source_linear_indices,'uint64');
    scope=gxtxt_statistics_scope_v1(getenv('GXDCF_SURFACE_SESSION'));
    meaning=gxtxt_statistics_v1('from_numeric','math.numeric.surface','surface_fit',fit,request.context);
    plan=gxtxt_statistics_v1('parameter_inference_plan',meaning,.95);
    if(strcmp(plan.interval_status,'value'))
      uncertainty=gxtxt_numeric_v1('parameter_uncertainty',plan);
      meaning=gxtxt_statistics_v1('with_parameter_uncertainty',meaning,.95,uncertainty);
    endif
    out=struct('schema','gxtxt.fitter_surface_capture.v1','statistics',meaning,...
      'report',gxtxt_statistics_v1('report',meaning,{'n','sse','r_squared','dof','rmse'}),...
      'parameter_report',gxtxt_statistics_v1('parameter_report',meaning),...
      'observation_count',rows(observations),'observation_columns',{{'x','y','observed_z','predicted_z','residual_z'}},...
      'observation_units',{{fit.model.predictor_units{1},fit.model.predictor_units{2},fit.model.response_unit,fit.model.response_unit,fit.model.response_unit}},...
      'state_schema',saved.schema,'domain',fit.model.observation_domain.bounds,...
      'declaration_sha256',fit.model.declaration_sha256,'fit_performed',true);
  else
    saved=gxtxt_scientific_result_read_v1(fullfile(workspace,'surface-state.ini'));
    model=gxtxt_numeric_v1('surface_model_restore',saved);
    switch(action)
      case 'query'
        evaluated=gxtxt_numeric_v1('surface_evaluate',model,request.coordinates,request.options);
        out=struct('schema','gxtxt.fitter_surface_query.v1','exact_query_count',rows(request.coordinates));
        for key={'predicted','points','coordinates','is_extrapolated','coordinate_units','domain',...
          'domain_meaning','fit_performed','interpolation_performed','declaration_sha256',...
          'source_sha256','binding_sha256','parameter_ids','predictor_ids','jacobian'}
          field=key{1};if(isfield(evaluated,field)),out.(field)=evaluated.(field);endif
        endfor
      case 'grid'
        grid=gxtxt_numeric_v1('surface_grid',model,request.x,request.y,request.options);
        for field={'x','y','z'},write_array(fullfile(workspace,['surface-grid-' field{1} '.bin']),grid.(field{1}),'double');endfor
        out=struct('schema','gxtxt.fitter_surface_grid.v1','shape',grid.shape,'layout',grid.layout,...
          'representation',grid.representation,'coordinate_units',{grid.coordinate_units},...
          'domain',grid.domain,'domain_meaning',grid.domain_meaning,'fit_performed',false,...
          'interpolation_performed',false,'declaration_sha256',model.declaration_sha256);
      case 'export'
        out=gxtxt_numeric_v1('model_export',model,request.options);
      otherwise,error('GXTXT:Fitter:Surface','Unknown retained surface action');
    endswitch
  endif
  gxtxt_scientific_result_write_v1(getenv('GXDCF_SURFACE_RESULT'),out,true);
endfunction
function write_array(path,values,type)
  fd=fopen(path,'wb','ieee-le');if(fd<0),error('GXTXT:Fitter:Surface','Cannot create owned surface artifact');endif
  unwind_protect
    if(fwrite(fd,values,type)!=numel(values)),error('GXTXT:Fitter:Surface','Incomplete owned surface artifact');endif
  unwind_protect_cleanup,fclose(fd);end_unwind_protect
endfunction
