% Calibration consumer adapter. Numeric owns all propagation and covariance.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_digitizer_uncertainty_v1(family,action,linearization,specification,unused,options)
  if(!strcmp(family,'digitizer')||!any(strcmp(action,{'propagate','covariance'})))
    error('GXTXT:Digitizer:Operation','Unsupported uncertainty staging operation');
  endif
  if(strcmp(action,'covariance'))
    captured=load(fullfile(options.workspace,'state.mat'));
    result=gxtxt_numeric_v1('digitization_covariance',captured.state,specification);
    fd=fopen(fullfile(options.workspace,'covariance.bin'),'wb','ieee-le');
    if(fd<0),error('GXTXT:Digitizer:IO','Cannot stage response covariance');endif
    unwind_protect
      if(fwrite(fd,result.covariance,'double')!=numel(result.covariance)),error('GXTXT:Digitizer:IO','Incomplete covariance artifact');endif
    unwind_protect_cleanup,fclose(fd);end_unwind_protect
    out=struct('source_state_sha256',result.source_state_sha256,'point_count',captured.state.point_count);
    return;
  endif
  state=gxtxt_numeric_v1('digitization_uncertainty',linearization,specification);
  save('-mat7-binary',fullfile(options.workspace,'state.mat'),'state');
  values=[state.coordinates,state.standard_uncertainty,state.covariance_blocks(:,2)];
  fd=fopen(fullfile(options.workspace,'values.bin'),'wb','ieee-le');
  if(fd<0),error('GXTXT:Digitizer:IO','Cannot stage physical uncertainty columns');endif
  unwind_protect
    if(fwrite(fd,values,'double')!=numel(values)),error('GXTXT:Digitizer:IO','Incomplete uncertainty columns');endif
  unwind_protect_cleanup,fclose(fd);end_unwind_protect
  out=struct('summary',state.summary);
endfunction
