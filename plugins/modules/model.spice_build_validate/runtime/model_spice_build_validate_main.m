function model_spice_build_validate_main(args)
% GX-TXT v0.7.8 - generic mathematical-model SPICE build and validation.
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% This module never performs fitting. Model-specific electrical knowledge is
% delegated to the selected mathematical model's SPICE Adapter API v1.

  config_path=gxtxt_spice_arg_value(args,'--config','');
  if(isempty(config_path)), error('model.spice_build_validate: --config is required'); endif
  cfg=gxtxt_spice_read_ini(config_path);
  numeric_fn=spice_numeric_binding(cfg);
  statistics_lifetime=gxtxt_statistics_scope_v1();
  outdir=gxtxt_spice_ini_get(cfg,'runtime.output_dir','');
  if(isempty(outdir)), error('model.spice_build_validate: runtime.output_dir missing'); endif
  if(exist(outdir,'dir')!=7), mkdir(outdir); endif

  gxtxt_progress_start('loading_inputs','Loading SPICE build/validation inputs','indeterminate');
  try
    model_id=strtrim(gxtxt_spice_ini_get(cfg,'model.id',''));
    model_fun_name=strtrim(gxtxt_spice_ini_get(cfg,'model.function',''));
    model_script=strtrim(gxtxt_spice_ini_get(cfg,'model.script',''));
    model_descriptor=strtrim(gxtxt_spice_ini_get(cfg,'model.descriptor_path',''));
    model_plugin_dir=strtrim(gxtxt_spice_ini_get(cfg,'model.plugin_dir',''));
    if(isempty(model_id)||isempty(model_fun_name)||isempty(model_script)||isempty(model_descriptor)||isempty(model_plugin_dir))
      error('model.spice_build_validate: incomplete [model] runtime contract; v0.7.8 model descriptor/plugin paths are required');
    endif
    if(exist(model_descriptor,'file')!=2), error('Mathematical model descriptor not found: %s',model_descriptor); endif
    model_script=resolve_model_script(model_script,model_plugin_dir);
    if(exist(model_script,'file')!=2), error('Mathematical model script not found: %s',model_script); endif

    gxtxt_progress_stage('loading_model','Loading mathematical model','indeterminate');
    addpath(fileparts(model_script));
    model_fun=str2func(model_fun_name);
    mdesc=gxtxt_spice_read_ini(model_descriptor);
    model_version=strtrim(gxtxt_spice_ini_get(mdesc,'meta.version',''));
    model_x_name=strtrim(gxtxt_spice_ini_get(cfg,'model.x_column',gxtxt_spice_ini_get(mdesc,'meta.x_column','X')));
    model_family_name=strtrim(gxtxt_spice_ini_get(cfg,'model.family_column',gxtxt_spice_ini_get(mdesc,'meta.family_column','family')));
    model_y_name=strtrim(gxtxt_spice_ini_get(cfg,'model.y_column',gxtxt_spice_ini_get(mdesc,'meta.y_column','Y')));
    model_y_unit=strtrim(gxtxt_spice_ini_get(cfg,'model.y_unit',gxtxt_spice_ini_get(mdesc,'meta.y_unit','')));
    param_names=split_semicolon(gxtxt_spice_ini_get(cfg,'model.param_names',gxtxt_spice_ini_get(mdesc,'parameters.names','')));
    if(isempty(param_names)), error('model.spice_build_validate: mathematical model parameter names missing'); endif

    gxtxt_progress_stage('loading_parameters','Loading frozen parameter set','indeterminate');
    parameter_file=strtrim(gxtxt_spice_ini_get(cfg,'config.parameter_file',''));
    if(isempty(parameter_file)), error('model.spice_build_validate: frozen parameter file is required'); endif
    ps=gxtxt_read_parameter_set(parameter_file,param_names,model_id);
    ps=gxtxt_validate_parameter_set(ps,param_names,model_id);
    theta=ps.values(:).';

    gxtxt_progress_stage('loading_spice_adapter','Loading mathematical-model SPICE adapter','indeterminate');
    [adapter_fun,adapter_desc]=load_spice_adapter(mdesc,model_plugin_dir);
    adesc=adapter_fun('describe',struct());
    validate_adapter_description(adesc,adapter_desc);
    domain_input_roles=adesc.model_input_roles;
    if(ischar(domain_input_roles)), domain_input_roles=split_semicolon(domain_input_roles); endif
    if(!iscell(domain_input_roles) || numel(domain_input_roles)!=2)
      error('model.spice_build_validate: SPICE adapter must declare exactly two model_input_roles for x/family validation');
    endif

    domain=[]; domain_file=strtrim(gxtxt_spice_ini_get(cfg,'config.domain_file',''));
    if(!isempty(domain_file))
      gxtxt_progress_stage('loading_domain','Loading mathematical-model training domain','indeterminate');
      reject_legacy_domain_format(domain_file);
      domain=gxtxt_read_model_domain(domain_file,domain_input_roles,model_id);
      domain=gxtxt_validate_model_domain(domain,domain_input_roles,model_id);
    endif

    validation=empty_validation();
    validation.x_name=model_x_name; validation.family_name=model_family_name; validation.y_name=model_y_name;
    validation_dataset_id=strtrim(gxtxt_spice_ini_get(cfg,'config.dataset_id',''));
    if(!isempty(validation_dataset_id))
      gxtxt_progress_stage('loading_validation_data','Loading canonical validation dataset','indeterminate');
      data_path=strtrim(gxtxt_spice_ini_get(cfg,'dataset.path',''));
      if(isempty(data_path)||exist(data_path,'file')!=2)
        error('model.spice_build_validate: validation dataset selected but dataset.path is unavailable');
      endif
      xcol=resolved_binding(cfg,'x',model_x_name);
      fcol=resolved_binding(cfg,'family',model_family_name);
      ycol=resolved_binding(cfg,'y',model_y_name);
      validation.x_name=xcol; validation.family_name=fcol; validation.y_name=ycol;
      [vx,vf,vy]=gxtxt_spice_read_named_csv3(data_path,xcol,fcol,ycol);
      valid=isfinite(vx)&isfinite(vf)&isfinite(vy); vx=vx(valid); vf=vf(valid); vy=vy(valid);
      if(isempty(vy)), error('model.spice_build_validate: validation dataset has no finite rows'); endif
      validation.present=true; validation.x=vx(:); validation.family=vf(:); validation.y=vy(:);
      validation.dataset_id=validation_dataset_id; validation.path=data_path;
      validation.role=normalize_validation_role(gxtxt_spice_ini_get(cfg,'config.validation_dataset_role','unspecified'));
    endif

    timestamp=utc_timestamp();
    device_name=strtrim(gxtxt_spice_ini_get(cfg,'config.spice_device_name','GXTXT_MODEL'));
    if(isempty(device_name)), device_name='GXTXT_MODEL'; endif
    module_version='5';
    application_version=strtrim(gxtxt_spice_ini_get(cfg,'runtime.application_version','0.7.8'));

    gxtxt_progress_stage('exporting_spice_model','Exporting SPICE model','indeterminate');
    export_req=struct('output_path',fullfile(outdir,'spice_model.lib'), ...
                      'device_name',device_name,'theta',theta,'param_names',{param_names}, ...
                      'gx_version',application_version,'module_id','model.spice_build_validate', ...
                      'module_version',module_version,'model_id',model_id,'model_version',model_version, ...
                      'timestamp',timestamp,'parameter_source',parameter_file);
    export_res=adapter_fun('export',export_req);
    if(!isstruct(export_res) || !isfield(export_res,'device_name') || !isfield(export_res,'output_path'))
      error('SPICE adapter export response is incomplete');
    endif
    if(exist(export_res.output_path,'file')!=2), error('SPICE adapter did not create the requested model file'); endif
    device_name=export_res.device_name;

    bounds=derive_bounds(cfg,domain,validation);
    sweep_points=parse_integer(gxtxt_spice_ini_get(cfg,'config.sweep_points','41'),41,2);
    sweep_groups=parse_integer(gxtxt_spice_ini_get(cfg,'config.sweep_groups','7'),7,1);

    gxtxt_progress_stage('building_x_sweep','Building X-sweep verification points','indeterminate');
    xreq=struct('profile','x_sweep','bounds',bounds,'points_per_curve',sweep_points,'group_count',sweep_groups);
    xsample=adapter_fun('sample_points',xreq);
    xpoints=validate_points(xsample.points,'x_sweep');
    xrun=build_and_run_profile(adapter_fun,adesc,outdir,device_name,'x_sweep',xpoints, ...
                               'spice_testbench_x_sweep.cir','ngspice_x_sweep.dat','ngspice_x_sweep.log',cfg);

    gxtxt_progress_stage('building_family_sweep','Building family-sweep verification points','indeterminate');
    freq=struct('profile','family_sweep','bounds',bounds,'points_per_curve',sweep_points,'group_count',sweep_groups);
    fsample=adapter_fun('sample_points',freq);
    fpoints=validate_points(fsample.points,'family_sweep');
    frun=build_and_run_profile(adapter_fun,adesc,outdir,device_name,'family_sweep',fpoints, ...
                               'spice_testbench_family_sweep.cir','ngspice_family_sweep.dat','ngspice_family_sweep.log',cfg);

    gxtxt_progress_stage('evaluating_analytical_model','Evaluating analytical model at SPICE operating points','determinate',rows(xpoints)+rows(fpoints));
    xana=evaluate_model(model_fun,theta,xpoints); gxtxt_progress_update(rows(xpoints),rows(xpoints)+rows(fpoints),'evaluating_analytical_model','Evaluating analytical model');
    fana=evaluate_model(model_fun,theta,fpoints); gxtxt_progress_update(rows(xpoints)+rows(fpoints),rows(xpoints)+rows(fpoints),'evaluating_analytical_model','Evaluating analytical model');

    rows_data=empty_rows();
    if(!isempty(domain)), gxtxt_progress_stage('classifying_domain','Classifying generated verification points against training domain','indeterminate'); endif
    xroles=classify_domain(domain,xpoints);
    froles=classify_domain(domain,fpoints);
    rows_data=append_rows(rows_data,'verification','x_sweep',xpoints,NaN(rows(xpoints),1),xana,xrun.values,xroles);
    rows_data=append_rows(rows_data,'verification','family_sweep',fpoints,NaN(rows(fpoints),1),fana,frun.values,froles);

    validation_run=struct('present',false,'values',[],'log_path','','data_path','','testbench_path','');
    if(validation.present)
      gxtxt_progress_stage('running_validation_points','Running ngspice at measured validation points','indeterminate');
      vpoints=[validation.x validation.family];
      validation_run=build_and_run_profile(adapter_fun,adesc,outdir,device_name,'validation',vpoints, ...
                                           'spice_testbench_validation.cir','ngspice_validation.dat','ngspice_validation.log',cfg);
      gxtxt_progress_stage('evaluating_analytical_model','Evaluating analytical model on validation dataset','determinate',rows(vpoints));
      vana=evaluate_model(model_fun,theta,vpoints);
      gxtxt_progress_update(rows(vpoints),rows(vpoints),'evaluating_analytical_model','Evaluating validation dataset');
      if(!isempty(domain)), gxtxt_progress_stage('classifying_domain','Classifying measured validation points against training domain','indeterminate'); endif
      vroles=classify_domain(domain,vpoints);
      rows_data=append_rows(rows_data,'measured_validation','validation',vpoints,validation.y,vana,validation_run.values,vroles);
    endif

    gxtxt_progress_stage('comparing_spice_analytical','Comparing SPICE with analytical model','indeterminate');
    if(validation.present), gxtxt_progress_stage('comparing_spice_measured','Comparing SPICE with measured validation data','indeterminate'); endif
    abs_tol=parse_nonnegative(gxtxt_spice_ini_get(cfg,'config.absolute_tolerance','1e-6'),1e-6);
    rel_tol=parse_nonnegative(gxtxt_spice_ini_get(cfg,'config.relative_tolerance','1e-7'),1e-7);
    rel_floor=parse_nonnegative(gxtxt_spice_ini_get(cfg,'config.relative_error_floor','1e-9'),1e-9);

    gxtxt_progress_stage('computing_metrics','Computing SPICE validation metrics','indeterminate');
    metrics=compute_all_metrics(rows_data,abs_tol,rel_tol,rel_floor,numeric_fn,model_y_unit);
    family_metrics=compute_family_metrics(rows_data,rel_floor,validation.x_name,validation.family_name,numeric_fn,model_y_unit);

    statistical_results=struct();
    for k=1:numel(metrics.n),statistical_results.(sprintf('comparison_%04d',k))=metrics.core{k};endfor
    for k=1:numel(family_metrics.n),statistical_results.(sprintf('family_%04d',k))=family_metrics.core{k};endfor
    metadata=gxtxt_statistics_v1('publication_metadata',statistical_results);
    write_placeholder(fullfile(outdir,'spice_statistics.tcldict'),metadata);

    gxtxt_progress_stage('writing_outputs','Writing machine-readable outputs','indeterminate');
    write_predictions(fullfile(outdir,'spice_predictions.csv'),rows_data,rel_floor);
    write_metrics(fullfile(outdir,'spice_validation_metrics.csv'),metrics);
    write_family_metrics(fullfile(outdir,'spice_validation_metrics_by_family.csv'),family_metrics);
    if(!validation.present), write_validation_placeholders(outdir); endif
    ngpath=resolve_executable(spice_executable(cfg));
    ngversion=program_version(ngpath);
    if(isempty(strtrim(ngversion)) || strcmpi(strtrim(ngversion),'unavailable'))
      ngversion=program_version_from_logs({xrun.log_path,frun.log_path,validation_run.log_path});
    endif
    if(isempty(strtrim(ngversion))), ngversion='unavailable'; endif
    write_summary(fullfile(outdir,'spice_validation_summary.txt'),cfg,model_id,model_version,parameter_file,domain_file, ...
                  adapter_desc,adesc,device_name,ngpath,ngversion,metrics,validation,validation_run,timestamp, ...
                  abs_tol,rel_tol,model_y_unit,bounds);

    gxtxt_progress_stage('building_render_cache','Building render cache','indeterminate');
    input_x=rows_data.input_x; input_family=rows_data.input_family; measured_y=rows_data.measured_y;
    analytical_y=rows_data.analytical_y; spice_y=rows_data.spice_y;
    residual_spice_analytical=rows_data.residual_spice_analytical; residual_spice_measured=rows_data.residual_spice_measured;
    relative_residual_spice_measured_percent=NaN(size(residual_spice_measured));
    relmask=isfinite(measured_y)&isfinite(residual_spice_measured)&(measured_y!=0)&(abs(measured_y)>=rel_floor);
    relative_residual_spice_measured_percent(relmask)=100.*residual_spice_measured(relmask)./measured_y(relmask);
    comparison=rows_data.comparison; profile=rows_data.profile; domain_role=rows_data.domain_role;
    relative_error_floor=rel_floor; validation_dataset_role=validation.role; validation_dataset_id=validation.dataset_id;
    validation_x_name=validation.x_name; validation_family_name=validation.family_name; validation_y_name=validation.y_name;
    domain_vertices=zeros(0,2); domain_kind='unavailable';
    if(!isempty(domain))
      if(isfield(domain,'vertices')), domain_vertices=domain.vertices; endif
      if(isfield(domain,'kind')), domain_kind=domain.kind; endif
    endif
    save(fullfile(outdir,'render_cache.mat'),'input_x','input_family','measured_y','analytical_y','spice_y', ...
         'residual_spice_analytical','residual_spice_measured','relative_residual_spice_measured_percent', ...
         'comparison','profile','domain_role','relative_error_floor','validation_dataset_role','validation_dataset_id', ...
         'validation_x_name','validation_family_name','validation_y_name','domain_vertices','domain_kind','model_x_name','model_family_name','model_y_name','model_y_unit','model_id','device_name','statistical_results');

    gxtxt_progress_stage('rendering_graphs','Rendering enabled graphs','determinate',count_enabled_graphs(cfg));
    cache=load(fullfile(outdir,'render_cache.mat'));
    model_spice_render(outdir,cfg,cache);
    gxtxt_progress_update(count_enabled_graphs(cfg),count_enabled_graphs(cfg),'rendering_graphs','Rendering enabled graphs');
    gxtxt_progress_complete('completed','SPICE model build and validation completed');

  catch err
    try
      gxtxt_progress_fail('failed','SPICE build/validation failed; see technical log and generated artifacts');
    catch
    end_try_catch
    try
      write_failure_summary(fullfile(outdir,'spice_validation_summary.txt'),err);
    catch
    end_try_catch
    rethrow(err);
  end_try_catch
endfunction


function p=resolve_model_script(script,plugin_dir)
  if(is_absolute_path(script)), p=script; return; endif
  % model.script is descriptor-relative-to-package-root in GX-TXT. plugin_dir
  % is guaranteed by v0.7.8, so derive the package root without relying on cwd.
  package_root=fileparts(fileparts(fileparts(plugin_dir)));
  p=fullfile(package_root,script);
  if(exist(p,'file')!=2)
    % Also accept a model-plugin-relative script for future plugin-local descriptors.
    candidate=fullfile(plugin_dir,script);
    if(exist(candidate,'file')==2), p=candidate; endif
  endif
endfunction

function [adapter_fun,ainfo]=load_spice_adapter(mdesc,plugin_dir)
  enabled=parse_bool(gxtxt_spice_ini_get(mdesc,'spice.enabled','0'),false);
  api=strtrim(gxtxt_spice_ini_get(mdesc,'spice.api_version',''));
  script=strtrim(gxtxt_spice_ini_get(mdesc,'spice.adapter_script',''));
  fn=strtrim(gxtxt_spice_ini_get(mdesc,'spice.adapter_function',''));
  aid=strtrim(gxtxt_spice_ini_get(mdesc,'spice.adapter_id',''));
  aver=strtrim(gxtxt_spice_ini_get(mdesc,'spice.adapter_version',''));
  if(!enabled), error('Selected mathematical model does not enable a SPICE capability'); endif
  if(!strcmp(api,'1')), error('Unsupported SPICE Adapter API version: %s',api); endif
  if(isempty(script)||isempty(fn)), error('SPICE capability is missing adapter_script or adapter_function'); endif
  if(is_absolute_path(script)), adapter_path=script; else adapter_path=fullfile(plugin_dir,script); endif
  if(exist(adapter_path,'file')!=2), error('SPICE adapter script not found: %s',adapter_path); endif
  addpath(fileparts(adapter_path)); adapter_fun=str2func(fn);
  ainfo=struct('api_version',api,'adapter_id',aid,'adapter_version',aver,'adapter_path',adapter_path,'adapter_function',fn);
endfunction

function validate_adapter_description(d,ainfo)
  required={'api_version','adapter_id','adapter_version','terminal_names','model_input_roles','model_input_quantities', ...
            'output_quantity','model_output_unit','spice_output_unit','spice_to_model_scale','supported_profiles','supports_arbitrary_points'};
  for i=1:numel(required)
    if(!isfield(d,required{i})), error('SPICE adapter describe response missing field: %s',required{i}); endif
  endfor
  if(d.api_version!=1), error('SPICE adapter describe api_version must be 1'); endif
  if(!isempty(ainfo.adapter_id)&&!strcmp(d.adapter_id,ainfo.adapter_id)), error('SPICE adapter descriptor/describe ID mismatch'); endif
  if(!any(strcmp(d.supported_profiles,'x_sweep')) || !any(strcmp(d.supported_profiles,'family_sweep')))
    error('SPICE adapter must support x_sweep and family_sweep profiles');
  endif
  if(!d.supports_arbitrary_points), error('SPICE adapter must support arbitrary operating points for measured validation'); endif
  if(!isfinite(d.spice_to_model_scale)||d.spice_to_model_scale==0), error('Invalid SPICE-to-model output scale'); endif
endfunction

function run=build_and_run_profile(adapter_fun,adesc,outdir,device_name,profile,points,cir_name,data_name,log_name,cfg)
  stage=['running_' profile];
  if(strcmp(profile,'x_sweep')), msg='Running ngspice X sweep';
  elseif(strcmp(profile,'family_sweep')), msg='Running ngspice family sweep';
  else msg='Running ngspice validation operating points'; endif
  treq=struct('profile',profile,'points',points,'output_path',fullfile(outdir,cir_name), ...
              'result_file',data_name,'model_file','spice_model.lib','device_name',device_name);
  tres=adapter_fun('testbench',treq);
  if(!isstruct(tres) || !isfield(tres,'output_path') || !isfield(tres,'result_vector_count'))
    error('SPICE adapter testbench response is incomplete for %s',profile);
  endif
  if(tres.result_vector_count!=rows(points)), error('SPICE adapter testbench vector-count mismatch for %s',profile); endif
  if(isfield(tres,'spice_to_model_scale') && abs(tres.spice_to_model_scale-adesc.spice_to_model_scale)>eps(max(1,abs(adesc.spice_to_model_scale))))
    error('SPICE adapter testbench/describe scale mismatch for %s',profile);
  endif
  if(exist(tres.output_path,'file')!=2), error('SPICE adapter did not create testbench for %s',profile); endif
  gxtxt_progress_stage(stage,msg,'indeterminate');
  exe=resolve_executable(spice_executable(cfg));
  launch_program(exe,{'-b','-o',log_name,cir_name},outdir,fullfile(outdir,log_name));
  data_path=fullfile(outdir,data_name);
  raw=gxtxt_spice_parse_wrdata(data_path,rows(points));
  values=raw .* adesc.spice_to_model_scale;
  if(numel(values)!=rows(points)), error('SPICE result length mismatch for %s',profile); endif
  run=struct('present',true,'values',values(:),'testbench_path',tres.output_path,'data_path',data_path,'log_path',fullfile(outdir,log_name));
endfunction

function launch_program(exe,args,workdir,log_path)
% Launch without shell interpolation using Octave popen2(command,args).
  old=pwd(); captured='';
  unwind_protect
    cd(workdir);
    [pin,pout,pid]=popen2(exe,args);
    if(pid<0), error('Cannot launch external process: %s',exe); endif
    fclose(pin);
    eagain=errno('EAGAIN'); done=false;
    while(!done)
      s=fgets(pout);
      if(ischar(s)), captured=[captured s];
      elseif(feof(pout)), done=true;
      elseif(errno()==eagain), pause(0.05); fclear(pout);
      else done=true; endif
    endwhile
    fclose(pout);
    [wpid,status,msg]=waitpid(pid);
    if(wpid<0), error('waitpid failed for %s: %s',exe,msg); endif
    if(exist(log_path,'file')!=2)
      fid=fopen(log_path,'w'); if(fid>=0), fputs(fid,captured); fclose(fid); endif
    elseif(!isempty(captured))
      fid=fopen(log_path,'a'); if(fid>=0), fprintf(fid,'\n--- process stdout ---\n%s',captured); fclose(fid); endif
    endif
    if(WIFEXITED(status))
      code=WEXITSTATUS(status);
      if(code!=0), error('External process failed with exit status %d: %s (see %s)',code,exe,log_path); endif
    elseif(WIFSIGNALED(status))
      error('External process terminated by signal %d: %s (see %s)',WTERMSIG(status),exe,log_path);
    else
      error('External process ended abnormally: %s (see %s)',exe,log_path);
    endif
  unwind_protect_cleanup
    cd(old);
  end_unwind_protect
endfunction

function cmd=spice_executable(cfg)
% An explicit module override takes precedence; the default follows Linux
% Configuration > Runtime selection copied into this module runtime file.
  cmd=strtrim(gxtxt_spice_ini_get(cfg,'config.ngspice_executable','ngspice'));
  if(strcmp(cmd,'ngspice'))
    configured=strtrim(gxtxt_spice_ini_get(cfg,'runtime.spice_cmd',''));
    if(!isempty(configured)), cmd=configured; endif
  endif
endfunction

function p=resolve_executable(cmd)
  if(isempty(cmd)), cmd='ngspice'; endif
  if(any(cmd==filesep) || (!isempty(regexp(cmd,'^[A-Za-z]:[\\/]','once'))))
    if(exist(cmd,'file')!=2), error('ngspice executable not found: %s',cmd); endif
    p=cmd; return;
  endif
  envp=getenv('PATH'); dirs=strsplit(envp,pathsep());
  for i=1:numel(dirs)
    if(isempty(dirs{i})), continue; endif
    candidate=fullfile(dirs{i},cmd);
    if(exist(candidate,'file')==2), p=candidate; return; endif
  endfor
  error('ngspice executable not found in PATH: %s',cmd);
endfunction

function v=program_version(exe)
  old=pwd(); captured=''; v='unavailable';
  unwind_protect
    [pin,pout,pid]=popen2(exe,{'--version'});
    if(pid<0), return; endif
    fclose(pin); eagain=errno('EAGAIN'); done=false;
    while(!done)
      s=fgets(pout);
      if(ischar(s)), captured=[captured s];
      elseif(feof(pout)), done=true;
      elseif(errno()==eagain), pause(0.05); fclear(pout);
      else done=true; endif
    endwhile
    fclose(pout); waitpid(pid);
  unwind_protect_cleanup
    cd(old);
  end_unwind_protect
  parsed=extract_ngspice_version(captured);
  if(!isempty(parsed)), v=parsed; endif
endfunction

function v=program_version_from_logs(paths)
  v='unavailable';
  for i=1:numel(paths)
    path=paths{i};
    if(!ischar(path) || isempty(strtrim(path)) || exist(path,'file')!=2), continue; endif
    fid=fopen(path,'r');
    if(fid<0), continue; endif
    txt='';
    unwind_protect
      while(true)
        s=fgets(fid);
        if(!ischar(s)), break; endif
        txt=[txt s];
      endwhile
    unwind_protect_cleanup
      fclose(fid);
    end_unwind_protect
    parsed=extract_ngspice_version(txt);
    if(!isempty(parsed)), v=parsed; return; endif
  endfor
endfunction

function v=extract_ngspice_version(txt)
  v='';
  if(!ischar(txt) || isempty(strtrim(txt))), return; endif
  tok=regexp(lower(txt),'ngspice[- ]+([0-9]+([.][0-9]+)*)','tokens','once');
  if(!isempty(tok)), v=tok{1}; return; endif
  tok=regexp(txt,'([0-9]+([.][0-9]+)+)','tokens','once');
  if(!isempty(tok)), v=tok{1}; endif
endfunction

function y=evaluate_model(fun,theta,points)
  y=fun(theta,points(:,1),points(:,2)); y=y(:);
  if(numel(y)!=rows(points)), error('Mathematical model output length mismatch'); endif
  if(any(!isfinite(y))), error('Mathematical model produced NaN/Inf'); endif
endfunction

function bounds=derive_bounds(cfg,domain,validation)
  derived=NaN(2,2);
  if(!isempty(domain) && isfield(domain,'vertices') && columns(domain.vertices)>=2)
    derived(1,:)=[min(domain.vertices(:,1)) max(domain.vertices(:,1))];
    derived(2,:)=[min(domain.vertices(:,2)) max(domain.vertices(:,2))];
  elseif(validation.present)
    derived(1,:)=[min(validation.x) max(validation.x)];
    derived(2,:)=[min(validation.family) max(validation.family)];
  endif
  keys={'x_min','x_max','family_min','family_max'};
  vals=NaN(1,4);
  for i=1:4, vals(i)=str2double(strtrim(gxtxt_spice_ini_get(cfg,['config.' keys{i}],''))); endfor
  bounds=derived;
  if(isfinite(vals(1))), bounds(1,1)=vals(1); endif
  if(isfinite(vals(2))), bounds(1,2)=vals(2); endif
  if(isfinite(vals(3))), bounds(2,1)=vals(3); endif
  if(isfinite(vals(4))), bounds(2,2)=vals(4); endif
  if(any(!isfinite(bounds(:))) || bounds(1,2)<=bounds(1,1) || bounds(2,2)<=bounds(2,1))
    error(['Unable to derive non-degenerate verification bounds. Provide a v0.7.8 model-domain file, ' ...
           'a validation dataset spanning both model inputs, or explicit X/family bounds.']);
  endif
endfunction

function roles=classify_domain(domain,points)
  n=rows(points); roles=repmat({'unknown'},n,1);
  if(isempty(domain)), return; endif
  [inside,~]=gxtxt_classify_model_domain(domain,points,[]);
  inside=logical(inside(:));
  if(numel(inside)!=n), error('Model-Domain API returned an unexpected classification length'); endif
  roles(inside)=repmat({'in_domain'},sum(inside),1);
  roles(!inside)=repmat({'out_of_domain'},sum(!inside),1);
endfunction

function r=empty_rows()
  r=struct('comparison',{{}},'profile',{{}},'input_x',zeros(0,1),'input_family',zeros(0,1),'measured_y',zeros(0,1), ...
           'analytical_y',zeros(0,1),'spice_y',zeros(0,1),'residual_spice_analytical',zeros(0,1), ...
           'residual_spice_measured',zeros(0,1),'domain_role',{{}});
endfunction

function r=append_rows(r,comparison,profile,points,measured,analytical,spice,roles)
  n=rows(points); measured=measured(:); analytical=analytical(:); spice=spice(:);
  if(numel(measured)!=n||numel(analytical)!=n||numel(spice)!=n||numel(roles)!=n), error('Internal row assembly length mismatch'); endif
  r.comparison=[r.comparison; repmat({comparison},n,1)]; r.profile=[r.profile; repmat({profile},n,1)];
  r.input_x=[r.input_x; points(:,1)]; r.input_family=[r.input_family; points(:,2)]; r.measured_y=[r.measured_y; measured];
  r.analytical_y=[r.analytical_y; analytical]; r.spice_y=[r.spice_y; spice];
  r.residual_spice_analytical=[r.residual_spice_analytical; spice-analytical];
  rm=NaN(n,1); mask=isfinite(measured); rm(mask)=spice(mask)-measured(mask); r.residual_spice_measured=[r.residual_spice_measured; rm];
  r.domain_role=[r.domain_role; roles(:)];
endfunction

function metrics=compute_all_metrics(r,abs_tol,rel_tol,rel_floor,numeric_fn,yunit)
  metrics=struct('comparison',{{}},'profile',{{}},'domain_role',{{}},'n',zeros(0,1),'rmse',zeros(0,1), ...
                 'mae',zeros(0,1),'max_abs_error',zeros(0,1),'r2',zeros(0,1),'max_relative_error',zeros(0,1), ...
                 'rms_relative_error',zeros(0,1),'pass',{{}});
  vidx=find(strcmp(r.comparison,'verification'));
  profiles={'all','x_sweep','family_sweep'};
  for i=1:numel(profiles)
    if(strcmp(profiles{i},'all')), idx=vidx; else idx=intersect(vidx,find(strcmp(r.profile,profiles{i}))); endif
    metrics=add_metric(metrics,'spice_vs_analytical',profiles{i},'all',r.analytical_y,r.spice_y,r.residual_spice_analytical,idx,abs_tol,rel_tol,rel_floor,true,numeric_fn,yunit);
  endfor
  midx=find(strcmp(r.comparison,'measured_validation'));
  if(!isempty(midx))
    roles={'all','in_domain','out_of_domain','unknown'};
    for i=1:numel(roles)
      if(strcmp(roles{i},'all')), idx=midx; else idx=intersect(midx,find(strcmp(r.domain_role,roles{i}))); endif
      metrics=add_metric(metrics,'spice_vs_measured','validation',roles{i},r.measured_y,r.spice_y,r.residual_spice_measured,idx,NaN,NaN,rel_floor,false,numeric_fn,yunit);
    endfor
  endif
endfunction

function m=add_metric(m,comparison,profile,domain_role,y,predicted,resid,idx,abs_tol,rel_tol,rel_floor,with_pass,numeric_fn,yunit)
  row=numel(m.n)+1; n=numel(idx);
  m.comparison{row,1}=comparison; m.profile{row,1}=profile; m.domain_role{row,1}=domain_role; m.n(row,1)=n;
  m.pass{row,1}='';
  raw=struct('n',0,'relative_n',0,'relative_floor',rel_floor);
  if(n>0),raw=feval(numeric_fn,'residual_metrics',y(idx),predicted(idx),struct('relative_floor',rel_floor));endif
  provenance=struct('producer','model.spice_build_validate','comparison',comparison,'profile',profile,'domain_role',domain_role);
  record=gxtxt_statistics_v1('from_numeric','math.numeric.comparison','residual_metrics',raw,struct('y_unit',yunit,'sample_role','evaluation'),struct(),provenance);
  m=store_core_values(m,row,record);
  if(n==0),return;endif
  rr=resid(idx);yy=y(idx);
  if(with_pass)
    ok=all(abs(rr) <= abs_tol + rel_tol.*abs(yy)); if(ok), m.pass{row}='PASS'; else m.pass{row}='FAIL'; endif
  endif
endfunction

function write_predictions(path,r,rel_floor)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'row_id,comparison,profile,input_x,input_family,measured_y,analytical_y,spice_y,residual_spice_analytical,residual_spice_measured,relative_residual_spice_measured_percent,domain_role\n');
    for i=1:numel(r.input_x)
      fprintf(fid,'%d,%s,%s,%.17g,%.17g,',i,r.comparison{i},r.profile{i},r.input_x(i),r.input_family(i));
      write_num(fid,r.measured_y(i)); fprintf(fid,','); write_num(fid,r.analytical_y(i)); fprintf(fid,','); write_num(fid,r.spice_y(i)); fprintf(fid,',');
      write_num(fid,r.residual_spice_analytical(i)); fprintf(fid,','); write_num(fid,r.residual_spice_measured(i)); fprintf(fid,',');
      rel=NaN; if(isfinite(r.measured_y(i)) && r.measured_y(i)!=0 && abs(r.measured_y(i))>=rel_floor), rel=100.*r.residual_spice_measured(i)./r.measured_y(i); endif
      write_num(fid,rel); fprintf(fid,',%s\n',r.domain_role{i});
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_metrics(path,m)
  write_core_csv(path,m,false);
endfunction

function write_summary(path,cfg,model_id,model_version,parameter_file,domain_file,ainfo,adesc,device_name,ngpath,ngversion,m,validation,vrun,timestamp,abs_tol,rel_tol,yunit,bounds)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'GX-TXT SPICE BUILD AND VALIDATION\n'); fprintf(fid,'Generated: %s\n\n',timestamp);
    fprintf(fid,'MODEL\n'); fprintf(fid,'Mathematical model: %s\n',model_id); fprintf(fid,'Model version: %s\n',model_version);
    fprintf(fid,'Parameter source: %s\n',parameter_file); if(!isempty(domain_file)),fprintf(fid,'Training domain: %s\n',domain_file);else fprintf(fid,'Training domain: not supplied\n');endif
    fprintf(fid,'SPICE adapter: %s v%s (API %d)\n',adesc.adapter_id,adesc.adapter_version,adesc.api_version);
    fprintf(fid,'Generated model: spice_model.lib / .SUBCKT %s\n',device_name);
    fprintf(fid,'ngspice executable: %s\n',ngpath); fprintf(fid,'ngspice version: %s\n',ngversion);
    fprintf(fid,'Model output unit: %s\n',yunit); fprintf(fid,'Verification bounds: X=[%.12g, %.12g], family=[%.12g, %.12g]\n\n',bounds(1,1),bounds(1,2),bounds(2,1),bounds(2,2));
    fprintf(fid,'SPICE <-> ANALYTICAL VERIFICATION\n'); fprintf(fid,'Absolute tolerance: %.12g\nRelative tolerance: %.12g\n',abs_tol,rel_tol);
    print_metric_block(fid,m,'spice_vs_analytical','all','all');
    print_metric_block(fid,m,'spice_vs_analytical','x_sweep','all');
    print_metric_block(fid,m,'spice_vs_analytical','family_sweep','all');
    if(validation.present)
      fprintf(fid,'\nSPICE <-> MEASURED VALIDATION\nDataset: %s\n',validation.dataset_id);
      fprintf(fid,'Dataset relationship to fitting data: %s\n',validation.role);
      fprintf(fid,'Validation columns: x=%s, family=%s, y=%s\n',validation.x_name,validation.family_name,validation.y_name);
      fprintf(fid,'Interpretation: %s\n',validation_role_description(validation.role));
      print_metric_block(fid,m,'spice_vs_measured','validation','all');
      print_metric_block(fid,m,'spice_vs_measured','validation','in_domain');
      print_metric_block(fid,m,'spice_vs_measured','validation','out_of_domain');
      print_metric_block(fid,m,'spice_vs_measured','validation','unknown');
      fprintf(fid,'Per-curve/family metrics: spice_validation_metrics_by_family.csv\n');
      fprintf(fid,'Validation testbench: %s\n',vrun.testbench_path);
      fprintf(fid,'Validation ngspice data: %s\n',vrun.data_path);
      fprintf(fid,'Validation ngspice log: %s\n',vrun.log_path);
    else
      fprintf(fid,'\nSPICE <-> MEASURED VALIDATION\nNot requested (no validation dataset selected).\n');
    endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function print_metric_block(fid,m,comparison,profile,role)
  idx=find(strcmp(m.comparison,comparison)&strcmp(m.profile,profile)&strcmp(m.domain_role,role),1);
  if(isempty(idx)), return; endif
  fprintf(fid,'\n[%s / %s]\n',profile,role);
  fprintf(fid,'%s\n',gxtxt_statistics_v1('report',m.core{idx},struct2cell(metric_mapping())));
  if(!isempty(m.pass{idx})), fprintf(fid,'Result: %s\n',m.pass{idx}); endif
endfunction

function fm=compute_family_metrics(r,rel_floor,x_name,family_name,numeric_fn,yunit)
  fm=struct('group_input',{{}},'group_value',zeros(0,1),'domain_role',{{}},'n',zeros(0,1),'rmse',zeros(0,1),'mae',zeros(0,1), ...
            'max_abs_error',zeros(0,1),'r2',zeros(0,1),'max_relative_error',zeros(0,1),'rms_relative_error',zeros(0,1));
  midx=find(strcmp(r.comparison,'measured_validation'));
  if(isempty(midx)), return; endif
  xv=r.input_x(midx); fv=r.input_family(midx);
  ux=unique(xv(isfinite(xv))); uf=unique(fv(isfinite(fv)));
  if(numel(uf)<=numel(ux))
    group_all=r.input_family; group_values=uf; group_name=family_name;
  else
    group_all=r.input_x; group_values=ux; group_name=x_name;
  endif
  roles={'all','in_domain','out_of_domain','unknown'};
  for fi=1:numel(group_values)
    fidx=intersect(midx,find(group_all==group_values(fi)));
    for ri=1:numel(roles)
      if(strcmp(roles{ri},'all')), idx=fidx; else idx=intersect(fidx,find(strcmp(r.domain_role,roles{ri}))); endif
      if(isempty(idx) && !strcmp(roles{ri},'all')), continue; endif
      row=numel(fm.n)+1; fm.group_input{row,1}=group_name; fm.group_value(row,1)=group_values(fi); fm.domain_role{row,1}=roles{ri}; fm.n(row,1)=numel(idx);
      raw=struct('n',0,'relative_n',0,'relative_floor',rel_floor);
      if(!isempty(idx)),raw=feval(numeric_fn,'residual_metrics',r.measured_y(idx),r.spice_y(idx),struct('relative_floor',rel_floor));endif
      provenance=struct('producer','model.spice_build_validate','group_input',group_name,'group_value',group_values(fi),'domain_role',roles{ri});
      record=gxtxt_statistics_v1('from_numeric','math.numeric.comparison','residual_metrics',raw,struct('y_unit',yunit,'sample_role','evaluation'),struct(),provenance);
      fm=store_core_values(fm,row,record);
    endfor
  endfor
endfunction

function write_family_metrics(path,m)
  write_core_csv(path,m,true);
endfunction

function mapping=metric_mapping()
  mapping=struct('n','n','rmse','rmse','mae','mae','max_abs_error','max_abs_error','r2','centered_comparison_score', ...
    'max_relative_error','max_relative_error','rms_relative_error','rms_relative_error');
endfunction
function m=store_core_values(m,index,record)
  rows=gxtxt_statistics_v1('scalar_rows',record,metric_mapping());
  for k=1:numel(rows),m.(rows{k}.id)(index,1)=rows{k}.value;endfor
  m.core{index}=record;
endfunction
function write_core_csv(path,m,family)
  mapping=metric_mapping();names=fieldnames(mapping);
  if(family),prefix={'group_input','group_value','domain_role'};suffix={};
  else prefix={'comparison','profile','domain_role'};suffix={'pass'};endif
  headers=[prefix(:);names(:);suffix(:)];
  for k=1:numel(names)
    for field={'status','quantity','unit','reason'},headers{end+1}=[names{k} '.' field{1}];endfor
  endfor
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif
  unwind_protect
    fprintf(fid,'%s\n',strjoin(headers,','));
    for i=1:numel(m.n)
      if(family),cells={m.group_input{i},sprintf('%.17g',m.group_value(i)),m.domain_role{i}};
      else cells={m.comparison{i},m.profile{i},m.domain_role{i}};endif
      rows=gxtxt_statistics_v1('scalar_rows',m.core{i},mapping);
      for k=1:numel(rows)
        value='';if(strcmp(rows{k}.status,'value')),value=sprintf('%.17g',rows{k}.value);endif
        cells{end+1}=value;
      endfor
      if(!family),cells{end+1}=m.pass{i};endif
      for k=1:numel(rows)
        for field={'status','quantity','unit_text','reason'},cells{end+1}=rows{k}.(field{1});endfor
      endfor
      for k=1:numel(cells),cells{k}=['"' strrep(cells{k},'"','""') '"'];endfor
      fprintf(fid,'%s\n',strjoin(cells,','));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_validation_placeholders(outdir)
  write_placeholder(fullfile(outdir,'spice_testbench_validation.cir'),'* Validation dataset not selected; no validation testbench generated.');
  write_placeholder(fullfile(outdir,'ngspice_validation.log'),'Validation dataset not selected; ngspice validation was not run.');
  write_placeholder(fullfile(outdir,'ngspice_validation.dat'),'# Validation dataset not selected; no ngspice validation data.');
endfunction

function write_placeholder(path,text)
  fid=fopen(path,'w'); if(fid<0), error('Cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'%s\n',text);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function role=normalize_validation_role(s)
  role=lower(strtrim(s));
  if(!any(strcmp(role,{'unspecified','independent','training_reused','other'}))), role='unspecified'; endif
endfunction

function s=validation_role_description(role)
  switch role
    case 'independent'
      s='Independent physical/model validation dataset; suitable for reporting model predictive performance.';
    case 'training_reused'
      s='Training/reused dataset; this is a consistency re-check, not an independent validation.';
    case 'other'
      s='Dataset relationship was explicitly marked as other; interpret with the experiment provenance.';
    otherwise
      s='Dataset relationship to the fitting data is unspecified; do not claim independent validation from this run alone.';
  endswitch
endfunction

function write_failure_summary(path,err)
  fid=fopen(path,'w'); if(fid<0), return; endif
  fprintf(fid,'GX-TXT SPICE BUILD AND VALIDATION\nSTATUS: EXECUTION ERROR\n\n%s\n',err.message); fclose(fid);
endfunction

function write_num(fid,v), if(isfinite(v)), fprintf(fid,'%.17g',v); endif; endfunction

function p=validate_points(p,label)
  if(!isnumeric(p)||columns(p)!=2||rows(p)<1||any(!isfinite(p(:)))), error('SPICE adapter returned invalid %s points',label); endif
endfunction

function r=empty_validation(), r=struct('present',false,'x',[],'family',[],'y',[],'dataset_id','','path','','role','unspecified','x_name','','family_name','','y_name',''); endfunction

function name=resolved_binding(cfg,role,def)
  name=strtrim(gxtxt_spice_ini_get(cfg,['bindings.' role],'')); if(isempty(name)), name=def; endif
  % GUI Analysis Source bindings carry the primary role; the source CSV does not.
  if(strncmp(name,'primary.',8)),name=name(9:end);endif
endfunction

function a=split_semicolon(s)
  if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif
endfunction

function n=parse_integer(s,def,minv), n=round(str2double(s));if(!isfinite(n)||n<minv),n=def;endif;endfunction
function v=parse_nonnegative(s,def),v=str2double(s);if(!isfinite(v)||v<0),v=def;endif;endfunction
function b=parse_bool(s,def),s=lower(strtrim(s));if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif;endfunction
function tf=is_absolute_path(p),tf=(!isempty(p)&&p(1)==filesep)||!isempty(regexp(p,'^[A-Za-z]:[\\/]','once'));endfunction
function t=utc_timestamp(),t=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time()));endfunction

function reject_legacy_domain_format(path)
  fid=fopen(path,'r'); if(fid<0), error('Cannot open model-domain file: %s',path); endif
  unwind_protect
    line=fgetl(fid);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  if(ischar(line) && !isempty(strfind(lower(line),'record_type,key,value,vertex_index')))
    error(['Legacy pre-v0.7.8 fit_domain.csv detected. Convert the artifact to Model-Domain API v1 format ' ...
           '(input columns + convex-hull vertices) without refitting; see tools/convert_legacy_fit_domain_v077_to_v078.py.']);
  endif
endfunction

function n=count_enabled_graphs(cfg)
  raw=gxtxt_spice_ini_get(cfg,'graph_provider.enabled','model.spice.overlay;model.spice.residuals;model.spice.parity');
  parts=strsplit(strrep(raw,',',';'),';'); parts=cellfun(@strtrim,parts,'UniformOutput',false); n=sum(!cellfun(@isempty,parts));
  if(n<1), n=1; endif
endfunction

function fn=spice_numeric_binding(cfg)
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(gxtxt_spice_ini_get(cfg,[prefix 'module_id'],''));
  version=strtrim(gxtxt_spice_ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(gxtxt_spice_ini_get(cfg,[prefix 'octave_entrypoint'],''));
  fn=strtrim(gxtxt_spice_ini_get(cfg,[prefix 'octave_function'],''));
  caps=split_semicolon(strrep(gxtxt_spice_ini_get(cfg,[prefix 'capabilities'],''),',',';'));
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(fn)||exist(entry,'file')!=2||!any(strcmp(caps,'residual_metrics')))
    error('model.spice_build_validate: public NUMERIC_API_v1 residual_metrics binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2),error('model.spice_build_validate: public numeric Octave function is unavailable');endif
endfunction
