function demo_numeric_root_finding_main(args,framework_root)
% Demonstrate Dataset-aware interpolation composed with public NUMERIC_API_v1 root_find.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.numeric.root_finding';
  module_version='1.0.2';
  publication_open=false;publication_finalized=false;P=struct();
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif

  gxtxt_progress_start('prepare','Preparing numerical root-finding demonstration','indeterminate');
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
    intervals=parse_intervals(gxtxt_ini_get(cfg,'config.search_intervals','-3,-1;0,1;2,4'),module_id);
    tolerance=cfg_positive(cfg,'config.tolerance',1e-10,module_id);
    max_iterations=cfg_positive_integer(cfg,'config.max_iterations',400,module_id);
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.root_finding.roots'));
    if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid Root result Dataset ID',module_id);endif
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

    interp_opts=struct('method',interpolation_method,'extrapolation','error','nonfinite',policy);
    if(selection.enabled),interp_opts.selection=selection;endif
    root_opts=struct('tolerance',tolerance,'max_iterations',max_iterations);

    nroots=rows(intervals);
    root_x=zeros(nroots,1);f_at_root=zeros(nroots,1);iterations=NaN(nroots,1);evaluations=NaN(nroots,1);exitflag=NaN(nroots,1);converged=zeros(nroots,1);
    gxtxt_progress_stage('numeric','Running public Dataset interpolation and root solver','determinate',nroots);
    source_count_from_api=NaN;
    callback=@(z) dataset_curve_value(numeric.function_name,session,source_dataset_id,x_id,y_id,z,interp_opts,module_id);
    for k=1:nroots
      a=intervals(k,1);b=intervals(k,2);
      probe=feval(numeric.function_name,'dataset_interpolate',session,source_dataset_id,x_id,y_id,[a;b],interp_opts);
      if(!isfield(probe,'yq')||numel(probe.yq)!=2),error('%s: public dataset_interpolate returned an invalid bracket evaluation',module_id);endif
      source_count_from_api=double(probe.n_source);
      fa=double(probe.yq(1));fb=double(probe.yq(2));
      if(!(fa==0||fb==0||sign(fa)!=sign(fb)))
        error('%s: root-search interval [%.17g, %.17g] is not a valid public fzero bracket: endpoint values have the same non-zero sign',module_id,a,b);
      endif
      try
        rr=feval(numeric.function_name,'root_find',callback,[a b],root_opts);
      catch rerr
        error('%s: public root_find failed for interval [%.17g, %.17g]: %s',module_id,a,b,rerr.message);
      end_try_catch
      if(!isfield(rr,'converged')||!rr.converged),error('%s: public root_find did not converge for interval [%.17g, %.17g]',module_id,a,b);endif
      root_x(k)=double(rr.root);f_at_root(k)=double(rr.fval);converged(k)=double(logical(rr.converged));
      if(isfield(rr,'iterations')),iterations(k)=double(rr.iterations);endif
      if(isfield(rr,'function_evaluations')),evaluations(k)=double(rr.function_evaluations);endif
      if(isfield(rr,'exitflag')),exitflag(k)=double(rr.exitflag);endif
      gxtxt_progress_update(k,nroots,'numeric',sprintf('Solved explicit interval %d of %d',k,nroots));
    endfor

    demo_reference=is_canonical_demo(source_dataset_id,x_name,y_name);
    reference_roots=[-2;0.5;3];
    root_errors=NaN(nroots,1);
    if(demo_reference)
      for k=1:nroots,root_errors(k)=min(abs(reference_roots-root_x(k)));endfor
    endif

    provenance=sprintf('%s %s via NUMERIC_API_v1 dataset_interpolate + root_find; interpolation=%s; nonfinite=%s; tolerance=%.17g; max_iterations=%d; intervals=%s; selection=%s',module_id,module_version,interpolation_method,policy,tolerance,max_iterations,interval_text(intervals),selection_id);
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{x_id,y_id}},'source',source_dataset_id,'provenance',provenance,'notes','Roots produced by explicit user brackets, public Dataset interpolation and public callback-based NUMERIC_API_v1 root_find. No interval scanning or private root solver is used.');
    gxtxt_progress_stage('publish','Publishing root result Dataset','determinate',1);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'root',0,true);
    P=declare_numeric(P,'root_id','root_id','identifier','1');
    P=declare_numeric(P,'root_x','root_x','independent',x_unit);
    P=declare_numeric(P,'f_at_root','f_at_root','function_value',y_unit);
    P=declare_numeric(P,'interval_start','interval_start','search_interval',x_unit);
    P=declare_numeric(P,'interval_end','interval_end','search_interval',x_unit);
    P=declare_numeric(P,'iterations','iterations','iteration_count','1');
    P=declare_numeric(P,'function_evaluations','function_evaluations','evaluation_count','1');
    P=declare_numeric(P,'exitflag','exitflag','solver_status','1');
    P=declare_numeric(P,'converged','converged','solver_status','1');
    ids=(1:nroots)';
    P=gxtxt_publication_v2_append(P,'root',{'root_id',ids;'root_x',root_x;'f_at_root',f_at_root;'interval_start',intervals(:,1);'interval_end',intervals(:,2);'iterations',iterations;'function_evaluations',evaluations;'exitflag',exitflag;'converged',converged});
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;
    gxtxt_progress_update(1,1,'publish','Root result Dataset published');

    gxtxt_progress_stage('graph','Creating public plot.dataset graph','indeterminate');
    spec=make_plotspec(source_dataset_id,x_id,y_id,output_dataset_id,x_name,y_name,x_unit,y_unit);
    graph=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
    if(!isfield(graph,'artifact')||isempty(strtrim(graph.artifact))||exist(graph.artifact,'file')!=2),error('%s: PLOT_DATASET_API_v2 did not produce the expected graph artifact',module_id);endif

    write_metrics(fullfile(outdir,'root_finding_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,source_count_from_api,source_provider,numeric,interpolation_method,policy,intervals,tolerance,max_iterations,root_x,f_at_root,iterations,evaluations,exitflag,converged,demo_reference,reference_roots,root_errors,metadata,P.provider,graph);
    write_report(fullfile(outdir,'root_finding_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,numeric,interpolation_method,policy,intervals,tolerance,max_iterations,root_x,f_at_root,iterations,evaluations,exitflag,converged,demo_reference,reference_roots,root_errors,metadata,pub_diag,pub_result,graph);
    gxtxt_progress_complete('done',sprintf('Published %s with %d root(s)',output_dataset_id,nroots));
    fprintf('[%s] version=%s source=%s output=%s roots=%d validation=PASS graph=%s\n',module_id,module_version,source_dataset_id,output_dataset_id,nroots,graph.artifact);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Root-finding demonstration failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function y=dataset_curve_value(api_fn,session,dataset_id,xid,yid,z,opts,module_id)
  r=feval(api_fn,'dataset_interpolate',session,dataset_id,xid,yid,double(z),opts);
  if(!isfield(r,'yq')||numel(r.yq)!=1||!isfinite(r.yq(1))),error('%s: public dataset_interpolate did not return one finite callback value',module_id);endif
  y=double(r.yq(1));
endfunction
function intervals=parse_intervals(text,module_id)
  text=strtrim(char(text));if(isempty(text)),error('%s: at least one explicit root-search interval is required',module_id);endif
  parts=strsplit(text,';');rows_out=zeros(0,2);
  for k=1:numel(parts)
    p=strtrim(parts{k});if(isempty(p)),continue;endif
    ab=strsplit(p,',');if(numel(ab)!=2),error('%s: each root-search interval must use start,end syntax; invalid entry: %s',module_id,p);endif
    a=str2double(strtrim(ab{1}));b=str2double(strtrim(ab{2}));
    if(!isfinite(a)||!isfinite(b)||a>=b),error('%s: invalid root-search interval: %s',module_id,p);endif
    rows_out(end+1,:)=[a b];
  endfor
  if(isempty(rows_out)),error('%s: no valid root-search intervals were supplied',module_id);endif
  intervals=rows_out;
endfunction
function spec=make_plotspec(source_dataset_id,xid,yid,roots_dataset_id,xname,yname,xunit,yunit)
  source_series=struct('id','source_curve','dataset_id',source_dataset_id,'x_variable_id',xid,'y_variable_id',yid,'axis','left','kind','line','label','Source f(x)');
  root_style=struct('marker','circle','marker_size',7,'marker_fill','full');
  root_series=struct('id','detected_roots','dataset_id',roots_dataset_id,'x_variable_id','root_x','y_variable_id','f_at_root','axis','left','kind','scatter','label','Detected roots','style',root_style);
  annotation=struct('type','reference_line','axis','left','value',0,'label','y = 0','line_style','dashed');
  axes=struct('x',struct('label',label_with_unit(xname,xunit)),'y_left',struct('label',label_with_unit(yname,yunit)));
  panel=struct('id','root_finding','axes',axes,'series',{{source_series,root_series}},'annotations',{{annotation}});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title','Root finding demo','defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
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
  caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));required={'root_finding','octave_callback_functions','dataset_interpolation','dataset_selection','stable_variable_identity'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
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
function tf=is_canonical_demo(dataset_id,xname,yname),tf=strcmp(dataset_id,'root_finding.source')&&strcmp(strtrim(xname),'x')&&strcmp(strtrim(yname),'f');endfunction
function P=declare_numeric(P,id,name,role,unit),spec=struct('dtype','float64','dimension_ids','root','name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function write_metrics(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,source_count,provider,api,method,policy,intervals,tolerance,max_iterations,roots,fvals,iters,evals,flags,conv,demo_reference,refs,errors,md,out_provider,graph)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write root_finding_metrics.ini',id);endif
  fprintf(fid,'; GX-TXT demo.numeric.root_finding metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nx_name=%s\ny_name=%s\nx_unit=%s\ny_unit=%s\nstorage_provider=%s\nselection_id=%s\ninput_count=%d\nvalid_count=%d\nexcluded_nonfinite_count=%d\npublic_interpolation_source_count=%.0f\n',id,ver,src,xid,yid,ini_escape(xname),ini_escape(yname),ini_escape(xunit),ini_escape(yunit),provider,selection_id,input_count,valid_count,excluded,source_count);
  fprintf(fid,'\n[root_finding]\npublic_operations=dataset_interpolate;root_find\ninterpolation_method=%s\nnonfinite_policy=%s\nsearch_intervals=%s\ntolerance=%.17g\nmax_iterations=%d\nroot_count=%d\nroots=%s\nf_at_roots=%s\n',method,policy,ini_escape(interval_text(intervals)),tolerance,max_iterations,numel(roots),vector_text(roots),vector_text(fvals));
  fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\nmodule_version=%s\noctave_function=%s\n\n[output]\ndataset_id=%s\nstorage_provider=%s\n\n[graph]\ngraph_id=%s\nvariant_id=%s\nartifact=%s\n\n[validation_reference]\ncanonical_demo=%d\nreference_roots=%s\nroot_errors=%s\n\n[metadata]\nresource_found=%d\n',api.name,api.api_version,api.module_version,api.function_name,outid,out_provider,ini_escape(graph.graph_id),ini_escape(graph.variant_id),ini_escape(graph.artifact),double(demo_reference),vector_text(refs),vector_text(errors),double(logical(md.found)));
  fclose(fid);
endfunction
function write_report(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,api,method,policy,intervals,tolerance,max_iterations,roots,fvals,iters,evals,flags,conv,demo_reference,refs,errors,md,pub_diag,pub_result,graph)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write root_finding_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical Root Finding Demo\n==================================\n\nPlugin: %s %s\nSource Dataset: %s\nX variable: %s (%s) [%s]\nY variable: %s (%s) [%s]\nSelection: %s\n',id,ver,src,xname,xid,xunit,yname,yid,yunit,selection_text(selection_id));
  fprintf(fid,'Public numerical path: NUMERIC_API_v1 dataset_interpolate -> callback -> root_find\nmath.numeric version: %s\nInterpolation method: %s\nRoot solver: fzero through public root_find\nNaN / Inf policy: %s\nTolerance: %.12g %s\nMaximum iterations: %d\nInput rows after Selection: %d\nFinite X/Y pairs: %d\nNon-finite X/Y pairs: %d\n',api.module_version,method,policy,tolerance,xunit,max_iterations,input_count,valid_count,excluded);
  fprintf(fid,'\nExplicit search intervals\n-------------------------\n%s\n',interval_text(intervals));
  fprintf(fid,'\nDetected roots: %d\n\nID   interval [%s]                 root_x [%s]        f(root) [%s]      iter   eval   exit\n',numel(roots),xunit,xunit,yunit);
  for k=1:numel(roots),fprintf(fid,'%-4d [%-10.6g, %-10.6g] %-18.12g %-18.12g %-6.0f %-6.0f %-6.0f\n',k,intervals(k,1),intervals(k,2),roots(k),fvals(k),iters(k),evals(k),flags(k));endfor
  fprintf(fid,'\nDetected root positions: %s\nFunction values at roots: %s\n',vector_text(roots),vector_text(fvals));
  if(demo_reference)
    fprintf(fid,'\nCanonical demo validation\n-------------------------\nReference roots: %s\nAbsolute root errors: %s\n',vector_text(refs),vector_text(errors));
  else
    fprintf(fid,'\nCanonical demo validation\n-------------------------\nNot applicable to this source Dataset.\n');
  endif
  fprintf(fid,'\nPublished Dataset\n-----------------\nDataset ID: %s\nColumns: root_id, root_x, f_at_root, interval_start, interval_end, iterations, function_evaluations, exitflag, converged\nUnits: root_x/interval bounds use X units; f_at_root uses Y units; solver diagnostics are dimensionless.\n',outid);
  fprintf(fid,'\nGraph\n-----\nplot.dataset graph: %s / variant %s\nArtifact: %s\nThe graph uses the original source Dataset as a line, the published root Dataset as markers, and a public PlotSpec reference line at y = 0.\n',graph.graph_id,graph.variant_id,graph.artifact);
  fprintf(fid,'\nSemantics and limitations\n-------------------------\n- Search intervals are explicit user input. The plugin never scans the curve for sign changes.\n- Each interval is validated using public dataset_interpolate endpoint values and solved independently through public root_find.\n- X is never sorted or repaired; public interpolation requires strictly increasing finite X after the selected non-finite policy.\n- Linear/PCHIP/spline interpolation operates on the sampled Dataset; roots therefore belong to the chosen interpolant, not to an unknown analytical function.\n- A bracket must contain a sign change or an endpoint root. Even-multiplicity/tangent roots without a sign change are not guaranteed by the public fzero contract.\n- Overlapping explicit intervals may legitimately return the same root more than once; the plugin does not privately de-duplicate roots.\n- Dataset Metadata resource present: %s\n',bool_text(md.found));
  fprintf(fid,'\nWarnings\n--------\n');if(excluded>0),fprintf(fid,'- %d non-finite pair(s) are present after Selection; policy=%s controls public interpolation handling.\n',excluded,policy);else,fprintf(fid,'None.\n');endif
  fprintf(fid,'\nValidation: PASS\n');fclose(fid);
endfunction
function s=label_with_unit(name,unit),name=strtrim(name);unit=strtrim(unit);if(isempty(name)),name='Value';endif;if(isempty(unit)||strcmp(unit,'1')),s=name;else,s=sprintf('%s [%s]',name,unit);endif,endfunction
function s=interval_text(M),c=cell(rows(M),1);for k=1:rows(M),c{k}=sprintf('[%.12g, %.12g]',M(k,1),M(k,2));endfor;s=strjoin(c,'; ');endfunction
function s=selection_text(id),if(isempty(id)),s='Full Dataset';else,s=id;endif,endfunction
function s=bool_text(v),if(v),s='yes';else,s='no';endif,endfunction
function s=vector_text(v),if(isempty(v)),s='none';return;endif;c=arrayfun(@(z)sprintf('%.12g',z),double(v(:))','UniformOutput',false);s=strjoin(c,', ');endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('demo.numeric.root_finding: invalid %s binding',role);endif,endfunction
function v=cfg_positive(cfg,key,def,module_id),raw=strtrim(gxtxt_ini_get(cfg,key,num2str(def,17)));v=str2double(raw);if(!isfinite(v)||v<=0),error('%s: %s must be a finite positive number',module_id,key);endif,endfunction
function v=cfg_positive_integer(cfg,key,def,module_id),v=cfg_positive(cfg,key,def,module_id);if(round(v)!=v),error('%s: %s must be a positive integer',module_id,key);endif;v=round(v);endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
