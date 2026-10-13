function analysis_statistics_pca_main(args,framework_root)
% Focused PCA through public NUMERIC_API matrix SVD and Dataset APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.pca';version='1.0.1';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing principal-component analysis','indeterminate');
  try
    variables=resolve_variables(cfg,source_id);
    ids={variables.variable_id};p=numel(ids);
    center=parse_bool(gxtxt_ini_get(cfg,'config.center','1'));
    scaling=lower(strtrim(gxtxt_ini_get(cfg,'config.scaling','standardize')));
    if(!any(strcmp(scaling,{'none','standardize'}))),error('%s: scaling must be none or standardize',module_id);endif
    component_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.component_mode','count')));
    if(!any(strcmp(component_mode,{'count','variance_target'}))),error('%s: invalid component selection mode',module_id);endif
    component_count=str2double(gxtxt_ini_get(cfg,'config.component_count','2'));
    target=str2double(gxtxt_ini_get(cfg,'config.variance_target','0.95'));
    if(strcmp(component_mode,'count')&&(!isfinite(component_count)||component_count<1||component_count!=fix(component_count)))
      error('%s: component count must be a positive integer',module_id);
    endif
    if(strcmp(component_mode,'variance_target')&&(!isfinite(target)||target<=0||target>1))
      error('%s: explained-variance target must lie in (0,1]',module_id);
    endif
    missing=lower(strtrim(gxtxt_ini_get(cfg,'config.missing_policy','listwise_omit')));
    if(!any(strcmp(missing,{'listwise_omit','error'}))),error('%s: missing policy must be listwise_omit or error',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','statistics.pca'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected multivariate Dataset rows','indeterminate');
    [X,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',ids,selection,65536);
    n_input=rows(X);if(n_input<2),error('%s: PCA requires at least two selected rows',module_id);endif
    finite=all(isfinite(X),2);
    if(strcmp(missing,'error')&&any(!finite)),error('%s: selected PCA variables contain NaN or Inf',module_id);endif
    X=X(finite,:);source_rows=source_rows(finite);n=rows(X);
    if(n<2),error('%s: PCA requires at least two complete rows',module_id);endif
    if(strcmp(scaling,'none'))
      base=variables(1).unit;
      for j=1:p
        if(!gxtxt_unit_compatible(variables(j).unit,base))
          error('%s: unscaled PCA requires compatible variable units; choose standardize explicitly',module_id);
        endif
        if(!strcmp(variables(j).unit,base)),X(:,j)=gxtxt_unit_convert(X(:,j),variables(j).unit,base);endif
        variables(j).analysis_unit=base;
      endfor
      score_unit=base;
    else
      for j=1:p,variables(j).analysis_unit=variables(j).unit;endfor
      score_unit='1';
    endif
    gxtxt_progress_stage('compute','Centering/scaling and running public matrix SVD','indeterminate');
    descriptive=gxtxt_numeric_v1('matrix_statistics',X,struct('dimension',1));
    means=double(descriptive.mean(:));sds=double(descriptive.std_sample(:));
    applied_centers=zeros(p,1);applied_scales=ones(p,1);
    if(center),applied_centers=means;endif
    if(strcmp(scaling,'standardize'))
      if(any(!isfinite(sds))||any(sds<=0)),error('%s: standardization requires positive sample spread in every variable',module_id);endif
      applied_scales=sds;
    endif
    Z=zeros(n,p);
    for j=1:p
      shifted=gxtxt_numeric_v1('array_binary','subtract',X(:,j),applied_centers(j));
      normalized=gxtxt_numeric_v1('array_binary','divide',shifted.values,applied_scales(j));
      Z(:,j)=normalized.values;
    endfor
    svd_result=gxtxt_numeric_v1('matrix_svd',Z,struct());
    singular=svd_result.singular_values(:);max_components=numel(singular);
    eigenvalues=singular.^2/(n-1);total=sum(eigenvalues);
    if(total<=0),error('%s: PCA has zero total variance/second moment',module_id);endif
    ratios=eigenvalues/total;cumulative=cumsum(ratios);
    if(strcmp(component_mode,'count'))
      if(component_count>max_components),error('%s: requested components exceed matrix rank bounds',module_id);endif
      k=component_count;
    else
      k=find(cumulative>=target-1e-12,1);if(isempty(k)),k=max_components;endif
    endif
    U=svd_result.u(:,1:k);V=svd_result.v(:,1:k);
    for j=1:k
      [~,imax]=max(abs(V(:,j)));
      if(V(imax,j)<0),V(:,j)=-V(:,j);U(:,j)=-U(:,j);endif
    endfor
    scores=zeros(n,k);
    for j=1:k
      product=gxtxt_numeric_v1('array_binary','multiply',U(:,j),singular(j));
      scores(:,j)=product.values;
    endfor
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Principal Component Analysis', ...
      'provenance',sprintf('%s %s; source=%s; variables=%s; selection=%s; center=%d; scaling=%s; component_mode=%s; component_count=%d; variance_target=%.12g; missing=%s',module_id,version,source_id,strjoin(ids,';'),selection_id(selection),center,scaling,component_mode,k,target,missing), ...
      'notes','SVD sign orientation: each component largest-magnitude loading is positive.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=ids;
    scores_id=[prefix '.scores'];loadings_id=[prefix '.loadings'];components_id=[prefix '.components'];scaling_id=[prefix '.scaling'];
    gxtxt_progress_stage('publish','Publishing PCA scores, loadings and components','indeterminate');
    score_data={'source_row','Original one-based source row','int64','','index',int64(source_rows)};
    loading_data={ ...
      'variable_index','Input variable index','int64','','index',int64((1:p)'); ...
      'variable_id','Stable source variable ID','string','','identifier',{variables.variable_id}'; ...
      'variable_name','Source variable name','string','','label',{variables.name}'; ...
      'source_unit','Source variable unit','string','','unit',{variables.unit}'};
    for j=1:k
      key=sprintf('component_%03d',j);
      score_data(end+1,:)={key,sprintf('PC%d score',j),'float64',score_unit,'derived',scores(:,j)};
      loading_data(end+1,:)={key,sprintf('PC%d loading',j),'float64','1','derived',V(:,j)};
    endfor
    publish_table(session,module_id,scores_id,'observation',opts,score_data);
    publish_table(session,module_id,loadings_id,'variable',opts,loading_data);
    comp_data={ ...
      'component_index','Component index','int64','','index',int64((1:max_components)'); ...
      'singular_value','Singular value','float64',score_unit,'derived',singular; ...
      'eigenvalue','Eigenvalue / explained variance','float64',squared_unit(score_unit),'derived',eigenvalues; ...
      'explained_variance','Explained variance','float64',squared_unit(score_unit),'derived',eigenvalues; ...
      'explained_ratio','Explained variance ratio','float64','1','derived',ratios; ...
      'cumulative_ratio','Cumulative explained ratio','float64','1','derived',cumulative; ...
      'selected','Selected component flag','int32','','flag',int32((1:max_components)'<=k)};
    publish_table(session,module_id,components_id,'component',opts,comp_data);
    scaling_data={ ...
      'variable_index','Input variable index','int64','','index',int64((1:p)'); ...
      'variable_id','Stable source variable ID','string','','identifier',{variables.variable_id}'; ...
      'source_unit','Source variable unit','string','','unit',{variables.unit}'; ...
      'analysis_unit','Unit used before SVD','string','','unit',{variables.analysis_unit}'; ...
      'observed_mean','Observed variable mean','float64','','derived',means; ...
      'observed_sample_sd','Observed sample SD','float64','','derived',sds; ...
      'applied_center','Subtracted center','float64','','derived',applied_centers; ...
      'applied_scale','Divisor','float64','','derived',applied_scales};
    publish_table(session,module_id,scaling_id,'variable',opts,scaling_data);
    graphs=struct('key',{},'graph_id',{},'variant_id',{},'artifact',{},'png',{});
    if(parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1')))
      gxtxt_progress_stage('graphs','Creating persistent PCA graphs','indeterminate');
      graphs(end+1)=plot_graph(session,components_id,'component_index','explained_ratio','bar','Explained variance ratio','scree','pca_scree.png');
      if(k>=2)
        graphs(end+1)=plot_graph(session,scores_id,'component_001','component_002','scatter','PC scores','scores','pca_scores.png');
        graphs(end+1)=plot_graph(session,loadings_id,'component_001','component_002','scatter','PC loadings','loadings','pca_loadings.png');
      endif
      for i=1:numel(graphs)
        [ok,msg]=copyfile(graphs(i).artifact,fullfile(outdir,graphs(i).png),'f');
        if(!ok),error('%s: cannot copy PCA graph: %s',module_id,msg);endif
      endfor
    endif
    write_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);
    write_summary(fullfile(outdir,'pca_summary.ini'),source_id,prefix,selection,center,scaling,component_mode,target,missing,n_input,n,p,k,svd_result,ratios,cumulative,numel(graphs));
    write_report(fullfile(outdir,'pca_report.txt'),source_id,selection,variables,center,scaling,missing,n_input,n,k,singular,eigenvalues,ratios,cumulative,V);
    gxtxt_progress_complete('done',sprintf('Published %d PCA components and %d graphs',k,numel(graphs)));
    fprintf('[%s] source=%s variables=%d rows=%d components=%d graphs=%d\n',module_id,source_id,p,n,k,numel(graphs));
  catch err
    try gxtxt_progress_fail('failed','PCA failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction
function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function out=parse_bool(text)
  q=lower(strtrim(text));if(any(strcmp(q,{'1','true','yes','on'}))),out=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))),out=false;
  else error('analysis.statistics.pca: expected a boolean setting');endif
endfunction
function variables=resolve_variables(cfg,source_id)
  text=strtrim(gxtxt_ini_get(cfg,'repeatable_config.variables.rows',''));rows=strsplit(text,';');
  variables=struct('variable_id',{},'name',{},'unit',{},'analysis_unit',{});seen={};
  for i=1:numel(rows)
    row=strtrim(rows{i});if(isempty(row)),continue;endif
    token=strtrim(gxtxt_ini_get(cfg,['repeatable_config.variables.' row '.variable'],''));
    [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',token);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
      error('analysis.statistics.pca: stable variable could not be resolved');
    endif
    if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
      error('analysis.statistics.pca: PCA variables must be numeric');
    endif
    if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
    if(isempty(unit)),error('analysis.statistics.pca: variable unit is required; use 1 for dimensionless data');endif
    vid=strtrim(meta.variable_id);
    if(isempty(vid)||any(strcmp(seen,vid))),error('analysis.statistics.pca: missing or duplicate stable variable ID');endif
    variables(end+1)=struct('variable_id',vid,'name',strtrim(meta.name),'unit',strtrim(unit),'analysis_unit','');seen{end+1}=vid;
  endfor
  if(numel(variables)<2),error('analysis.statistics.pca: choose at least two numeric variables');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.pca: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.pca: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function unit=squared_unit(base)
  if(strcmp(base,'1')),unit='1';else unit=[base '^2'];endif
endfunction
function publish_table(session,module_id,dataset_id,dim,opts,variables)
  P=struct();opened=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,dim,0,true);
    for i=1:rows(variables)
      P=gxtxt_publication_v2_declare_variable(P,variables{i,1},struct('dtype',variables{i,3},'dimension_ids',dim, ...
        'name',variables{i,2},'unit',variables{i,4},'semantic_role',variables{i,5}));
    endfor
    P=gxtxt_publication_v2_append(P,dim,variables(:,[1,6]));
    [P,result]=gxtxt_publication_v2_finalize(P);opened=false;
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    rethrow(err);
  end_try_catch
endfunction
function graph=plot_graph(session,dataset_id,xid,yid,kind,title_text,key,png)
  series={struct('id',key,'dataset_id',dataset_id,'x_variable_id',xid,'y_variable_id',yid,'axis','left','kind',kind,'label',title_text)};
  axes=struct('x',struct('label',xid),'y_left',struct('label',yid));
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
  if(!isfield(R,'artifact')||exist(R.artifact,'file')!=2),error('analysis.statistics.pca: Plot Dataset returned no graph artifact');endif
  graph=struct('key',key,'graph_id',R.graph_id,'variant_id',R.variant_id,'artifact',R.artifact,'png',png);
endfunction
function write_manifest(path,graphs)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.pca: cannot write graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(graphs));
    for i=1:numel(graphs)
      g=graphs(i);fprintf(fid,'\n[graph.%02d]\nkey=pca.%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\n',i,g.key,g.graph_id,g.variant_id,g.png,g.artifact);
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,source_id,prefix,selection,center,scaling,mode,target,missing,n_input,n,p,k,S,ratios,cumulative,graphs)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.pca: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.pca\nmodule_version=1.0.1\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nselection_id=%s\nvariable_count=%d\nn_input=%d\nn_complete=%d\nn_excluded=%d\n',source_id,selection_id(selection),p,n_input,n,n_input-n);
    fprintf(fid,'\n[pca]\ncenter=%d\nscaling=%s\ncomponent_mode=%s\nvariance_target=%.12g\nmissing_policy=%s\nselected_components=%d\nsvd_rank=%d\ncondition_number=%.17g\n',center,scaling,mode,target,missing,k,S.rank,S.condition_number);
    fprintf(fid,'\n[output]\nprefix=%s\nautomatic_graph_count=%d\n',prefix,graphs);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,selection,variables,center,scaling,missing,n_input,n,k,singular,eigenvalues,ratios,cumulative,V)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.pca: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Principal Component Analysis\nSource Dataset: %s\nSelection: %s\nVariables: %d\nSelected rows: %d  Complete rows: %d\nCenter: %d  Scaling: %s  Missing: %s\nSelected components: %d\n',source_id,selection_id(selection),numel(variables),n_input,n,center,scaling,missing,k);
    fprintf(fid,'\nComponent | Singular value | Explained variance | Ratio | Cumulative\n');
    for i=1:numel(singular),fprintf(fid,'%d | %.12g | %.12g | %.12g | %.12g\n',i,singular(i),eigenvalues(i),ratios(i),cumulative(i));endfor
    fprintf(fid,'\nVariable | Unit | Loadings\n');
    for i=1:numel(variables)
      fprintf(fid,'%s | %s',variables(i).variable_id,variables(i).unit);
      for j=1:k,fprintf(fid,' | %.12g',V(i,j));endfor
      fprintf(fid,'\n');
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
