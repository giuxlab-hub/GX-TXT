function demo_numeric_minimization_main(args,framework_root)
% Demonstrate Dataset-aware interpolation composed with public NUMERIC_API_v1 minimize_1d.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.numeric.minimization';
  module_version='1.0.2';
  publication_open=false;publication_finalized=false;P=struct();
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif

  gxtxt_progress_start('prepare','Preparing numerical one-dimensional minimization demonstration','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif

    x_binding=binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');
    y_binding=binding_column(gxtxt_ini_get(cfg,'bindings.function',''),'function');
    if(isempty(x_binding)||isempty(y_binding)),error('%s: Independent X and Function Y bindings are required',module_id);endif
    [x_unit,~,x_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);
    [y_unit,~,y_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',y_binding);
    if(!meta_found(x_meta)||!meta_found(y_meta)),error('%s: X or Function Y binding could not be resolved',module_id);endif
    x_id=strtrim(x_meta.variable_id);y_id=strtrim(y_meta.variable_id);
    x_name=strtrim(x_meta.name);y_name=strtrim(y_meta.name);
    if(isempty(x_id)||isempty(y_id)),error('%s: stable X/Y variable IDs are required',module_id);endif
    if(strcmp(x_id,y_id)),error('%s: X and Function Y variables must be different',module_id);endif

    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','error')));
    if(!any(strcmp(policy,{'error','omit'}))),error('%s: NaN / Inf policy must be error or omit',module_id);endif
    interpolation_method=lower(strtrim(gxtxt_ini_get(cfg,'config.interpolation_method','linear')));
    if(!any(strcmp(interpolation_method,{'linear','pchip','spline'}))),error('%s: public interpolation method must be linear, pchip or spline',module_id);endif
    lower_bound=cfg_finite(cfg,'config.lower_bound',-3,module_id);
    upper_bound=cfg_finite(cfg,'config.upper_bound',5,module_id);
    if(lower_bound>=upper_bound),error('%s: lower minimization bound must be smaller than upper minimization bound',module_id);endif
    tolerance=cfg_positive(cfg,'config.tolerance',1e-10,module_id);
    max_iterations=cfg_positive_integer(cfg,'config.max_iterations',400,module_id);
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.minimization.result'));
    if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid Minimum result Dataset ID',module_id);endif
    if(strcmp(output_dataset_id,source_dataset_id)),error('%s: output Dataset ID must differ from source Dataset ID',module_id);endif

    selection=struct('enabled',false);
    try selection=gxtxt_selection_from_runtime(cfg,'selection');catch selerr,error('%s: invalid Dataset Selection: %s',module_id,selerr.message);end_try_catch
    if(selection.enabled),validate_selection(selection,source_dataset_id,x_id,module_id);endif
    selection_id='';if(selection.enabled&&isfield(selection,'id')),selection_id=strtrim(selection.id);endif

    numeric=discover_numeric_api(framework_root,module_id);
    discover_plot_api(framework_root,module_id);
    metadata=read_optional_metadata(cfg);

    gxtxt_progress_stage('inspect_source','Inspecting selected Dataset curve through public Analysis Source transport','indeterminate');
    [raw_x,raw_y,source_provider]=read_selected_xy(cfg,x_id,y_id,selection);
    input_count=numel(raw_x);
    if(input_count<2),error('%s: selected source requires at least two rows',module_id);endif
    if(numel(raw_y)!=input_count),error('%s: bound X/Y variables have inconsistent row counts',module_id);endif
    finite_pair=isfinite(raw_x)&isfinite(raw_y);valid_count=sum(finite_pair);excluded_nonfinite=input_count-valid_count;
    if(strcmp(policy,'error')&&excluded_nonfinite>0),error('%s: selected Dataset contains NaN or Inf and nonfinite_policy=error',module_id);endif
    if(strcmp(policy,'omit')),usable_x=raw_x(finite_pair);else,usable_x=raw_x;endif
    if(numel(usable_x)<2),error('%s: fewer than two finite X/Y pairs remain for interpolation',module_id);endif
    data_min=min(usable_x);data_max=max(usable_x);
    if(lower_bound<data_min||upper_bound>data_max),error('%s: minimization bounds [%.17g, %.17g] must remain inside the selected Dataset X range [%.17g, %.17g]',module_id,lower_bound,upper_bound,data_min,data_max);endif

    interp_opts=struct('method',interpolation_method,'extrapolation','error','nonfinite',policy);
    if(selection.enabled),interp_opts.selection=selection;endif
    minimize_opts=struct('tolerance',tolerance,'max_iterations',max_iterations);

    gxtxt_progress_stage('numeric','Running public Dataset interpolation and bounded minimizer','determinate',1);
    probe=feval(numeric.function_name,'dataset_interpolate',session,source_dataset_id,x_id,y_id,[lower_bound;upper_bound],interp_opts);
    if(!isfield(probe,'yq')||numel(probe.yq)!=2),error('%s: public dataset_interpolate returned an invalid bound evaluation',module_id);endif
    source_count_from_api=double(probe.n_source);
    callback=@(z) dataset_curve_value(numeric.function_name,session,source_dataset_id,x_id,y_id,z,interp_opts,module_id);
    try
      rr=feval(numeric.function_name,'minimize_1d',callback,[lower_bound upper_bound],minimize_opts);
    catch merr
      error('%s: public minimize_1d failed for bounds [%.17g, %.17g]: %s',module_id,lower_bound,upper_bound,merr.message);
    end_try_catch
    if(!isfield(rr,'converged')||!rr.converged),error('%s: public minimize_1d did not converge for bounds [%.17g, %.17g]',module_id,lower_bound,upper_bound);endif
    minimum_x=double(rr.x);minimum_y=double(rr.fval);converged=double(logical(rr.converged));
    iterations=NaN;evaluations=NaN;exitflag=NaN;solver='';
    if(isfield(rr,'iterations')),iterations=double(rr.iterations);endif
    if(isfield(rr,'function_evaluations')),evaluations=double(rr.function_evaluations);endif
    if(isfield(rr,'exitflag')),exitflag=double(rr.exitflag);endif
    if(isfield(rr,'solver')),solver=strtrim(rr.solver);endif
    gxtxt_progress_update(1,1,'numeric','Public bounded minimization completed');

    demo_reference=is_canonical_demo(source_dataset_id,x_name,y_name);
    reference_x=1.75;reference_y=2.0;x_error=NaN;y_error=NaN;
    if(demo_reference),x_error=abs(minimum_x-reference_x);y_error=abs(minimum_y-reference_y);endif

    provenance=sprintf('%s %s via NUMERIC_API_v1 dataset_interpolate + minimize_1d; interpolation=%s; nonfinite=%s; bounds=[%.17g,%.17g]; tolerance=%.17g; max_iterations=%d; selection=%s',module_id,module_version,interpolation_method,policy,lower_bound,upper_bound,tolerance,max_iterations,selection_id);
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{x_id,y_id}},'source',source_dataset_id,'provenance',provenance,'notes','One-dimensional minimum produced by public Dataset interpolation and public NUMERIC_API_v1 minimize_1d. No private interpolation or minimizer is used.');
    gxtxt_progress_stage('publish','Publishing minimum result Dataset','determinate',1);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'minimum',0,true);
    P=declare_numeric(P,'minimum_id','minimum_id','identifier','1');
    % A minimum's X coordinate is an independent coordinate of the source
    % function. The more specific meaning is carried by the variable name;
    % the public Plot Dataset API requires equal X semantic roles when the
    % source curve and this point are drawn in one graph.
    P=declare_numeric(P,'minimum_x','minimum_x','independent',x_unit);
    P=declare_numeric(P,'minimum_y','minimum_y','function_value',y_unit);
    P=declare_numeric(P,'interval_start','interval_start','search_interval',x_unit);
    P=declare_numeric(P,'interval_end','interval_end','search_interval',x_unit);
    P=declare_numeric(P,'iterations','iterations','iteration_count','1');
    P=declare_numeric(P,'function_evaluations','function_evaluations','evaluation_count','1');
    P=declare_numeric(P,'exitflag','exitflag','solver_status','1');
    P=declare_numeric(P,'converged','converged','solver_status','1');
    P=gxtxt_publication_v2_append(P,'minimum',{'minimum_id',1;'minimum_x',minimum_x;'minimum_y',minimum_y;'interval_start',lower_bound;'interval_end',upper_bound;'iterations',iterations;'function_evaluations',evaluations;'exitflag',exitflag;'converged',converged});
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;
    gxtxt_progress_update(1,1,'publish','Minimum result Dataset published');

    gxtxt_progress_stage('graph','Creating public plot.dataset graph','indeterminate');
    spec=make_plotspec(source_dataset_id,x_id,y_id,output_dataset_id,x_name,y_name,x_unit,y_unit);
    graph=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
    if(!isfield(graph,'artifact')||isempty(strtrim(graph.artifact))||exist(graph.artifact,'file')!=2),error('%s: PLOT_DATASET_API_v2 did not produce the expected graph artifact',module_id);endif

    write_metrics(fullfile(outdir,'minimization_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,source_count_from_api,source_provider,numeric,interpolation_method,policy,lower_bound,upper_bound,tolerance,max_iterations,minimum_x,minimum_y,iterations,evaluations,exitflag,converged,solver,demo_reference,reference_x,reference_y,x_error,y_error,metadata,P.provider,graph);
    write_report(fullfile(outdir,'minimization_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,numeric,interpolation_method,policy,lower_bound,upper_bound,tolerance,max_iterations,minimum_x,minimum_y,iterations,evaluations,exitflag,converged,solver,demo_reference,reference_x,reference_y,x_error,y_error,metadata,pub_diag,pub_result,graph);
    gxtxt_progress_complete('done',sprintf('Published %s with minimum x=%.12g',output_dataset_id,minimum_x));
    fprintf('[%s] version=%s source=%s output=%s minimum_x=%.12g minimum_y=%.12g validation=PASS graph=%s\n',module_id,module_version,source_dataset_id,output_dataset_id,minimum_x,minimum_y,graph.artifact);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','One-dimensional minimization demonstration failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function y=dataset_curve_value(api_fn,session,dataset_id,xid,yid,z,opts,module_id)
  r=feval(api_fn,'dataset_interpolate',session,dataset_id,xid,yid,double(z),opts);
  if(!isfield(r,'yq')||numel(r.yq)!=1||!isfinite(r.yq(1))),error('%s: public dataset_interpolate did not return one finite callback value',module_id);endif
  y=double(r.yq(1));
endfunction
function spec=make_plotspec(source_dataset_id,xid,yid,result_dataset_id,xname,yname,xunit,yunit)
  source_series=struct('id','source_curve','dataset_id',source_dataset_id,'x_variable_id',xid,'y_variable_id',yid,'axis','left','kind','line','label','Source f(x)');
  marker_style=struct('marker','circle','marker_size',8,'marker_fill','full');
  minimum_series=struct('id','detected_minimum','dataset_id',result_dataset_id,'x_variable_id','minimum_x','y_variable_id','minimum_y','axis','left','kind','scatter','label','Detected minimum','style',marker_style);
  axes=struct('x',struct('label',label_with_unit(xname,xunit)),'y_left',struct('label',label_with_unit(yname,yunit)));
  panel=struct('id','minimization','axes',axes,'series',{{source_series,minimum_series}},'annotations',{{}});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','1D minimization demo','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
endfunction
function discover_plot_api(root,module_id)
  descriptor=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(descriptor,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif
  d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public standard_octave PLOT_DATASET_API_v2 bridge is unavailable',module_id);endif
endfunction
function api=discover_numeric_api(root,module_id)
  descriptor=fullfile(root,'plugins','modules','math.numeric','module.ini');if(exist(descriptor,'file')!=2),error('%s: math.numeric descriptor missing',module_id);endif
  d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: NUMERIC_API_v1 is not advertised',module_id);endif
  ver=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(ver,'1')),error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,ver);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));required={'optimization','octave_callback_functions','dataset_interpolation','dataset_selection','stable_variable_identity'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
  entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));if(isempty(entry)||isempty(fn)),error('%s: incomplete NUMERIC_API_v1 Octave binding',module_id);endif
  entry_path=fullfile(fileparts(descriptor),entry);if(exist(entry_path,'file')!=2),error('%s: advertised NUMERIC_API_v1 entrypoint missing',module_id);endif;addpath(fileparts(entry_path));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif
  api=struct('name','NUMERIC_API_v1','api_version',ver,'function_name',fn,'entrypoint',entry,'module_version',strtrim(gxtxt_ini_get(d,'meta.version','')));
endfunction
function [x,y,provider]=read_selected_xy(cfg,x_id,y_id,selection)
  ids={x_id,y_id};S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false));provider=S.storage_provider;xp={};yp={};
  unwind_protect
    while(!S.eof),[S,C]=gxtxt_table_stream_next(S);if(C.nrows>0),xp{end+1}=double(C.values{1}(:));yp{end+1}=double(C.values{2}(:));endif,endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
  if(isempty(xp)),x=zeros(0,1);y=zeros(0,1);else,x=vertcat(xp{:});y=vertcat(yp{:});endif
  if(selection.enabled),mask=gxtxt_selection_mask(selection,x);x=x(mask);y=y(mask);endif
endfunction
function validate_selection(S,dataset_id,x_id,module_id)
  if(!S.enabled),return;endif
  if(!isfield(S,'source_dataset_id')||!strcmp(strtrim(S.source_dataset_id),dataset_id)),error('%s: Dataset Selection source does not match the bound Dataset',module_id);endif
  if(!isfield(S,'type')||!strcmp(lower(strtrim(S.type)),'x_range')),error('%s: only X-range Dataset Selection is supported',module_id);endif
  if(!isfield(S,'x_variable_id')||!strcmp(strtrim(S.x_variable_id),x_id)),error('%s: Dataset Selection X variable must match the bound X variable',module_id);endif
endfunction
function md=read_optional_metadata(cfg),try md=gxtxt_analysis_source_dataset_metadata(cfg,'primary');catch,md=struct('found',false,'count',0,'keys',{{}},'values',{{}});end_try_catch;endfunction
function tf=is_canonical_demo(dataset_id,xname,yname),tf=strcmp(dataset_id,'minimization.source')&&strcmp(strtrim(xname),'x')&&strcmp(strtrim(yname),'f');endfunction
function P=declare_numeric(P,id,name,role,unit),spec=struct('dtype','float64','dimension_ids','minimum','name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function write_metrics(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,source_count,provider,api,method,policy,lower,upper,tolerance,max_iterations,minx,miny,iters,evals,flag,conv,solver,demo_reference,refx,refy,xerr,yerr,md,out_provider,graph)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write minimization_metrics.ini',id);endif
  fprintf(fid,'; GX-TXT demo.numeric.minimization metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nx_name=%s\ny_name=%s\nx_unit=%s\ny_unit=%s\nstorage_provider=%s\nselection_id=%s\ninput_count=%d\nvalid_count=%d\nexcluded_nonfinite_count=%d\npublic_interpolation_source_count=%.0f\n',id,ver,src,xid,yid,ini_escape(xname),ini_escape(yname),ini_escape(xunit),ini_escape(yunit),provider,selection_id,input_count,valid_count,excluded,source_count);
  fprintf(fid,'\n[minimization]\npublic_operations=dataset_interpolate;minimize_1d\ninterpolation_method=%s\nnonfinite_policy=%s\nlower_bound=%.17g\nupper_bound=%.17g\ntolerance=%.17g\nmax_iterations=%d\nminimum_x=%.17g\nminimum_y=%.17g\nsolver=%s\niterations=%.17g\nfunction_evaluations=%.17g\nexitflag=%.17g\nconverged=%d\n',method,policy,lower,upper,tolerance,max_iterations,minx,miny,solver,iters,evals,flag,conv);
  fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\nmodule_version=%s\noctave_function=%s\n\n[output]\ndataset_id=%s\nstorage_provider=%s\n\n[graph]\ngraph_id=%s\nvariant_id=%s\nartifact=%s\n\n[validation_reference]\ncanonical_demo=%d\nreference_x=%.17g\nreference_y=%.17g\nx_error=%.17g\ny_error=%.17g\n\n[metadata]\nresource_found=%d\n',api.name,api.api_version,api.module_version,api.function_name,outid,out_provider,ini_escape(graph.graph_id),ini_escape(graph.variant_id),ini_escape(graph.artifact),double(demo_reference),refx,refy,xerr,yerr,double(logical(md.found)));
  fclose(fid);
endfunction
function write_report(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,api,method,policy,lower,upper,tolerance,max_iterations,minx,miny,iters,evals,flag,conv,solver,demo_reference,refx,refy,xerr,yerr,md,pub_diag,pub_result,graph)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write minimization_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical 1D Minimization Demo\n======================================\n\nPlugin: %s %s\nSource Dataset: %s\nX variable: %s (%s) [%s]\nY variable: %s (%s) [%s]\nSelection: %s\n',id,ver,src,xname,xid,xunit,yname,yid,yunit,selection_text(selection_id));
  fprintf(fid,'Public numerical path: NUMERIC_API_v1 dataset_interpolate -> callback -> minimize_1d\nmath.numeric version: %s\nInterpolation method: %s\nMinimizer: %s through public minimize_1d\nSemantics: bounded scalar local minimization on the selected interpolated curve; no claim of exhaustive/global optimization for multimodal functions.\nNaN / Inf policy: %s\nBounds: [%.12g, %.12g] %s\nTolerance: %.12g %s\nMaximum iterations: %d\nInput rows after Selection: %d\nFinite X/Y pairs: %d\nNon-finite X/Y pairs: %d\n',api.module_version,method,solver,policy,lower,upper,xunit,tolerance,xunit,max_iterations,input_count,valid_count,excluded);
  fprintf(fid,'\nComputed minimum\n----------------\nminimum_x = %.15g %s\nminimum_y = %.15g %s\niterations = %.0f\nfunction evaluations = %.0f\nexitflag = %.0f\nconverged = %s\n',minx,xunit,miny,yunit,iters,evals,flag,bool_text(conv));
  if(demo_reference)
    fprintf(fid,'\nCanonical demo validation\n-------------------------\nReference minimum: x=%.15g %s, f=%.15g %s\nAbsolute X error: %.12g %s\nAbsolute Y error: %.12g %s\n',refx,xunit,refy,yunit,xerr,xunit,yerr,yunit);
  else
    fprintf(fid,'\nCanonical demo validation\n-------------------------\nNot applicable to this source Dataset.\n');
  endif
  fprintf(fid,'\nPublished Dataset\n-----------------\nDataset ID: %s\nColumns: minimum_id, minimum_x, minimum_y, interval_start, interval_end, iterations, function_evaluations, exitflag, converged\nUnits: minimum_x/interval bounds use X units; minimum_y uses Y units; solver diagnostics are dimensionless.\n',outid);
  fprintf(fid,'\nGraph\n-----\nplot.dataset graph: %s / variant %s\nArtifact: %s\nThe graph uses the original source Dataset as a line and the published minimum Dataset as a marker series.\n',graph.graph_id,graph.variant_id,graph.artifact);
  fprintf(fid,'\nSemantics and limitations\n-------------------------\n- The objective callback is built only from public NUMERIC_API_v1 dataset_interpolate.\n- The optimizer is public minimize_1d, implemented by math.numeric with GNU Octave fminbnd.\n- The supplied bounds must remain inside the selected Dataset X range; extrapolation is disabled.\n- X is never sorted or repaired; public interpolation requires strictly increasing X after the chosen non-finite policy.\n- Linear/PCHIP/spline minimization operates on the sampled Dataset interpolant, not on an unknown analytical function.\n- fminbnd is a bounded scalar minimizer. It can converge to a local minimum on a multimodal objective and is not presented as an exhaustive global optimizer.\n- A flat objective has non-unique minimizers; the returned point is solver-dependent and should not be interpreted as uniquely identified.\n- Dataset Metadata resource present: %s\n',bool_text(md.found));
  fprintf(fid,'\nWarnings\n--------\n');if(excluded>0),fprintf(fid,'- %d non-finite pair(s) are present after Selection; policy=%s controls public interpolation handling.\n',excluded,policy);else,fprintf(fid,'None.\n');endif
  fprintf(fid,'\nValidation: PASS\n');fclose(fid);
endfunction
function s=label_with_unit(name,unit),name=strtrim(name);unit=strtrim(unit);if(isempty(name)),name='Value';endif;if(isempty(unit)||strcmp(unit,'1')),s=name;else,s=sprintf('%s [%s]',name,unit);endif,endfunction
function s=selection_text(id),if(isempty(id)),s='Full Dataset';else,s=id;endif,endfunction
function s=bool_text(v),if(v),s='yes';else,s='no';endif,endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('demo.numeric.minimization: invalid %s binding',role);endif,endfunction
function v=cfg_finite(cfg,key,def,module_id),raw=strtrim(gxtxt_ini_get(cfg,key,num2str(def,17)));v=str2double(raw);if(!isfinite(v)),error('%s: %s must be a finite number',module_id,key);endif,endfunction
function v=cfg_positive(cfg,key,def,module_id),v=cfg_finite(cfg,key,def,module_id);if(v<=0),error('%s: %s must be a finite positive number',module_id,key);endif,endfunction
function v=cfg_positive_integer(cfg,key,def,module_id),v=cfg_positive(cfg,key,def,module_id);if(round(v)!=v),error('%s: %s must be a positive integer',module_id,key);endif;v=round(v);endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
