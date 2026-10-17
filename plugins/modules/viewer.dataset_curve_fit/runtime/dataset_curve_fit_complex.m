% Exact source adaptation only; public Numeric owns model/fit/residual science.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=dataset_curve_fit_complex(train,source,query,solver_options)
  path=getenv('GXDCF_COMPLEX_RECIPE');captured=gxtxt_scientific_result_read_v1(path);
  model=gxtxt_numeric_v1('complex_model_compose',captured.recipe);
  channels=captured.channels;if(isstruct(channels)),channels=num2cell(channels);endif
  if(numel(channels)!=numel(model.channel_ids)),error('Complex captured channel count changed');endif
  [train_z,train_conversion]=observations(channels,model,'training',rows(train));
  [source_z,source_conversion]=observations(channels,model,'source',rows(source));
  measurement=captured.measurement;source_measurement=measurement;
  if(strcmp(measurement.layout,'per_observation'))
    C=gxtxt_scientific_array_read_v1(fileparts(path),captured.covariance_descriptor);
    train_ids=row_ids(captured.training_rows_file,rows(train),size(C,3));source_ids=row_ids(captured.source_rows_file,rows(source),size(C,3));
    measurement.covariance=double(C(:,:,train_ids));source_measurement.covariance=double(C(:,:,source_ids));
  endif
  display=captured.display;channel=find(strcmp(display.channel_id,model.channel_ids));
  if(numel(channel)!=1),error('Captured complex display channel changed');endif
  % The source trace is immutable. A selected display projection must describe
  % those exact observed Y values before any optimization is started.
  train_display=project_observations(train_z(:,channel),display);source_display=project_observations(source_z(:,channel),display);
  for pair={train(:,2),train_display;source(:,2),source_display}.'
    scale=max(1,max(abs(pair{1}),abs(pair{2})));
    if(any(abs(pair{1}-pair{2})>128*eps*scale)),error('Source Y does not represent the declared complex projection; choose the matching source Variable or explicitly publish that projection first');endif
  endfor
  for key={'lower_bounds','upper_bounds','fixed_mask'}
    if(isfield(solver_options,key{1})&&!isempty(solver_options.(key{1}))),error('Complex parameter bounds and fixed values belong to the physical recipe');endif
    if(isfield(solver_options,key{1})),solver_options=rmfield(solver_options,key{1});endif
  endfor
  if(isfield(solver_options,'loss')&&!strcmp(solver_options.loss,'linear')),error('Complex covariance requires the quadratic Cartesian objective');endif
  if(isfield(solver_options,'loss_scale')&&solver_options.loss_scale!=1),error('Complex covariance does not use a robust loss scale');endif
  if(isfield(solver_options,'multistart_mode')&&!strcmp(solver_options.multistart_mode,'single')),error('Complex fitting requires one declared bounded start');endif
  for key=fieldnames(solver_options).'
    if(strncmp(key{1},'multistart_',11)||any(strcmp(key{1},{'loss','loss_scale'}))),solver_options=rmfield(solver_options,key{1});endif
  endfor
  fit=gxtxt_numeric_v1('complex_fit',model,train(:,1),train_z,measurement,solver_options);
  evaluation=gxtxt_numeric_v1('complex_residuals',fit.model,source(:,1),source_z,source_measurement);
  saved=struct('schema','gxtxt.complex_projection_model.v1','kind','complex_projection',...
    'recipe',fit.model.recipe,'parameters',fit.parameters,'declaration_sha256',fit.model.declaration_sha256,...
    'channel_id',display.channel_id,'projection',display.projection);
  if(isfield(display,'reference')),saved.reference=display.reference;endif
  domain=[min([train(:,1);source(:,1);query(:)]);max([train(:,1);source(:,1);query(:)])];
  options=struct('domain',domain,'derivative',false);
  all_queries=[train(:,1);source(:,1);query(:)];predicted=struct('predicted',NaN(size(all_queries)));
  for first=1:65536:numel(all_queries)
    last=min(first+65535,numel(all_queries));part=gxtxt_numeric_v1('model_query',saved,all_queries(first:last),options);
    if(!all(part.valid)),error('The declared complex output projection is unavailable at one or more physical frequencies');endif
    predicted.predicted(first:last)=part.predicted;
  endfor
  nt=rows(train);ns=rows(source);
  out=struct('fit',fit,'evaluation',evaluation,'saved',saved,'training_y',predicted.predicted(1:nt),...
    'source_y',predicted.predicted(nt+(1:ns)),'output_y',predicted.predicted(nt+ns+1:end),...
    'training_observed_components',components(train_z),'source_observed_components',components(source_z),...
    'training_covariance',measurement.covariance,'source_covariance',source_measurement.covariance,...
    'training_conversion',{train_conversion},'source_conversion',{source_conversion});
endfunction
function [z,receipts]=observations(channels,model,sample,n)
  z=complex(zeros(n,numel(channels)));receipts=cell(1,numel(channels));
  for k=1:numel(channels)
    channel=channels{k};if(!strcmp(channel.channel_id,model.channel_ids{k})),error('Captured complex channel order changed');endif
    first=read_values(channel.([sample '_first_file']),n,'double=>double');second=read_values(channel.([sample '_second_file']),n,'double=>double');
    if(any(!isfinite(first))||any(!isfinite(second))),error('Complex channel contains a nonfinite observation; exact rows are not silently omitted');endif
    if(strcmp(channel.representation,'cartesian'))
      z(:,k)=complex(first,second);receipts{k}=struct('representation','cartesian','conversion','none');
    else
      scale='linear';if(strcmp(channel.representation,'polar_db20')),scale='db20';elseif(!strcmp(channel.representation,'polar_linear')),error('Unknown captured complex representation');endif
      opts=struct('phase_unit',channel.phase_unit,'magnitude_scale',scale,'channel_units',{{model.channel_units{k}}});
      if(strcmp(scale,'db20')),opts.reference=channel.reference;endif
      converted=gxtxt_numeric_v1('complex_from_polar',first,second,opts);z(:,k)=converted.values;
      receipts{k}=rmfield(converted,{'values','phase_valid'});
    endif
  endfor
endfunction
function values=read_values(path,n,precision)
  info=dir(path);if(numel(info)!=1||info.bytes!=8*n),error('Captured complex input byte length changed');endif
  fid=fopen(path,'rb','ieee-le');if(fid<0),error('Cannot read captured complex input');endif
  unwind_protect,values=fread(fid,n,precision);unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(numel(values)!=n),error('Captured complex input was truncated');endif
endfunction
function positions=row_ids(path,n,total)
  identities=read_values(path,n,'uint64=>uint64');
  if(any(identities>=uint64(total))||numel(unique(identities))!=n),error('Complex covariance lost exact unique original source-row alignment');endif
  positions=double(identities)+1;
endfunction
function values=components(z)
  values=zeros(rows(z),2*columns(z));values(:,1:2:end)=real(z);values(:,2:2:end)=imag(z);
endfunction
function values=project_observations(z,display)
  projection=display.projection;
  if(strcmp(projection,'imaginary')),projection='imag';endif
  if(strcmp(projection,'db20')),projection='magnitude';endif
  values=gxtxt_numeric_v1('complex_unary',projection,real(z),imag(z),struct()).values;
  if(strcmp(display.projection,'db20'))
    if(any(values<=0)),error('Zero-amplitude dB observations are unavailable');endif
    logarithm=gxtxt_numeric_v1('array_unary','log10',values,struct()).values;
    reference=gxtxt_numeric_v1('array_unary','log10',display.reference.value,struct()).values;
    difference=gxtxt_numeric_v1('array_binary','subtract',logarithm,reference,struct()).values;
    values=gxtxt_numeric_v1('array_binary','multiply',20,difference,struct()).values;
  endif
endfunction
