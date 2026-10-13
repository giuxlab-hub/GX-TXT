function analysis_statistics_distribution_main(args,framework_root)
% Empirical distribution workflow using public GX-TXT APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.statistics.distribution';version='1.0.1';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing empirical distribution','indeterminate');
  try
    token=strtrim(gxtxt_ini_get(cfg,'config.variable',''));
    [unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',token);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
      error('%s: stable source variable could not be resolved',module_id);
    endif
    if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
      error('%s: source variable must be numeric',module_id);
    endif
    if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),unit='s';endif
    vid=strtrim(meta.variable_id);
    if(isempty(vid)),error('%s: stable variable ID is missing',module_id);endif
    prefix=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_prefix','statistics.distribution'));
    if(isempty(regexp(prefix,'^[A-Za-z0-9_.-]+$','once'))||strcmp(prefix,source_id))
      error('%s: invalid output Dataset prefix',module_id);
    endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));
    if(!any(strcmp(policy,{'omit','error'}))),error('%s: invalid nonfinite policy',module_id);endif
    mode=lower(strtrim(gxtxt_ini_get(cfg,'config.bin_mode','count')));
    if(!any(strcmp(mode,{'count','width','edges'}))),error('%s: choose an explicit bin rule',module_id);endif
    edges=[];options=struct('bin_mode',mode,'nonfinite',policy);
    switch(mode)
      case 'count'
        n=str2double(gxtxt_ini_get(cfg,'config.bin_count','10'));
        if(!isfinite(n)||n<1||n>1000000||n!=fix(n)),error('%s: bin count must be an integer from 1 to 1000000',module_id);endif
        options.bin_count=n;
      case 'width'
        width=str2double(gxtxt_ini_get(cfg,'config.bin_width','1'));
        if(!isfinite(width)||width<=0),error('%s: bin width must be positive and finite',module_id);endif
        options.bin_width=width;
      case 'edges'
        edges=parse_numbers(gxtxt_ini_get(cfg,'config.bin_edges',''),'bin edges');
        if(numel(edges)<2||any(diff(edges)<=0)),error('%s: bin edges must be strictly increasing',module_id);endif
    endswitch
    probabilities=parse_numbers(gxtxt_ini_get(cfg,'config.quantile_probabilities','0;0.25;0.5;0.75;1'),'quantile probabilities');
    if(any(probabilities<0)||any(probabilities>1)),error('%s: quantile probabilities must lie in [0,1]',module_id);endif
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    gxtxt_progress_stage('read','Reading selected numeric observations','indeterminate');
    [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',{vid},selection,65536);
    values=matrix(:,1);n_input=numel(values);
    if(n_input<1),error('%s: no selected observations',module_id);endif
    if(strcmp(policy,'error')&&any(!isfinite(values))),error('%s: selected variable contains NaN or Inf',module_id);endif
    gxtxt_progress_stage('compute','Computing histogram, ECDF and quantiles','indeterminate');
    histogram=gxtxt_numeric_v1('histogram',values,edges,options);
    ecdf=gxtxt_numeric_v1('ecdf',values,struct('nonfinite',policy));
    quantiles=gxtxt_numeric_v1('quantiles',values,probabilities,struct('nonfinite',policy));
    provenance=sprintf('%s %s; source=%s; variable=%s; selection=%s; bin_mode=%s; nonfinite=%s',module_id,version,source_id,vid,selection_id(selection),mode,policy);
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Empirical Distribution','provenance',provenance, ...
      'notes','Histogram frequencies use all finite selected observations as denominator.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids={vid};
    gxtxt_progress_stage('publish','Publishing empirical distribution Datasets','indeterminate');
    bins_id=[prefix '.bins'];ecdf_id=[prefix '.ecdf'];quantiles_id=[prefix '.quantiles'];
    publish_table(session,module_id,bins_id,'bin',opts,{ ...
      'bin_index','Bin index','','index',int64((1:numel(histogram.counts))'); ...
      'left_edge','Left bin edge',unit,'coordinate',histogram.edges(1:end-1); ...
      'right_edge','Right bin edge',unit,'coordinate',histogram.edges(2:end); ...
      'center','Bin center',unit,'coordinate',histogram.centers; ...
      'count','Frequency count','','count',int64(histogram.counts); ...
      'relative_frequency','Relative frequency','1','derived',histogram.relative_frequency; ...
      'cumulative_frequency','Cumulative frequency','1','derived',histogram.cumulative_frequency});
    publish_table(session,module_id,ecdf_id,'support',opts,{ ...
      'support','ECDF support',unit,'coordinate',ecdf.support; ...
      'count','Support frequency','','count',int64(ecdf.counts); ...
      'probability','Cumulative probability','1','derived',ecdf.probability});
    publish_table(session,module_id,quantiles_id,'quantile',opts,{ ...
      'probability','Requested probability','1','coordinate',quantiles.probabilities; ...
      'percentile','Requested percentile','%','coordinate',100*quantiles.probabilities; ...
      'value','Type-7 quantile',unit,'derived',quantiles.quantiles});
    graph_count=0;
    if(parse_bool(gxtxt_ini_get(cfg,'config.render_graphs','1')))
      gxtxt_progress_stage('graphs','Creating persistent distribution graphs','indeterminate');
      graphs(1)=create_graph(session,bins_id,'center','count',unit,'Frequency table','bar');
      graphs(2)=create_graph(session,ecdf_id,'support','probability',unit,'Empirical CDF','line');
      graph_count=numel(graphs);
      for i=1:graph_count
        [ok,msg]=copyfile(graphs(i).artifact,fullfile(outdir,sprintf('distribution_graph_%02d.png',i)),'f');
        if(!ok),error('%s: cannot copy graph artifact: %s',module_id,msg);endif
      endfor
    else
      graphs=struct('graph_id',{},'variant_id',{},'artifact',{});
    endif
    write_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);
    write_summary(fullfile(outdir,'distribution_summary.ini'),source_id,vid,prefix,selection,mode,policy,histogram,ecdf,quantiles,graph_count);
    write_report(fullfile(outdir,'distribution_report.txt'),source_id,vid,unit,prefix,selection,mode,policy,histogram,ecdf,quantiles);
    gxtxt_progress_complete('done',sprintf('Published %d bins, %d ECDF supports and %d quantiles',numel(histogram.counts),numel(ecdf.support),numel(probabilities)));
    fprintf('[%s] source=%s variable=%s bins=%d ecdf=%d quantiles=%d graphs=%d\n',module_id,source_id,vid,numel(histogram.counts),numel(ecdf.support),numel(probabilities),graph_count);
  catch err
    try gxtxt_progress_fail('failed','Empirical distribution failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function out=parse_numbers(text,label)
  parts=strsplit(strrep(text,',',';'),';');out=[];
  for i=1:numel(parts)
    token=strtrim(parts{i});if(isempty(token)),continue;endif
    value=str2double(token);
    if(!isfinite(value)),error('analysis.statistics.distribution: invalid %s value: %s',label,token);endif
    out(end+1,1)=value;
  endfor
  if(isempty(out)),error('analysis.statistics.distribution: %s list is empty',label);endif
endfunction
function out=parse_bool(text)
  q=lower(strtrim(text));if(any(strcmp(q,{'1','true','yes','on'}))),out=true;
  elseif(any(strcmp(q,{'0','false','no','off'}))),out=false;
  else error('analysis.statistics.distribution: expected a boolean setting');endif
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.distribution: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.statistics.distribution: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function publish_table(session,module_id,dataset_id,dim,opts,variables)
  P=struct();opened=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,dim,0,true);
    for i=1:rows(variables)
      id=variables{i,1};value=variables{i,5};dtype='float64';
      if(isinteger(value)),dtype='int64';endif
      P=gxtxt_publication_v2_declare_variable(P,id,struct('dtype',dtype,'dimension_ids',dim, ...
        'name',variables{i,2},'unit',variables{i,3},'semantic_role',variables{i,4}));
    endfor
    P=gxtxt_publication_v2_append(P,dim,variables(:,[1,5]));
    [P,result]=gxtxt_publication_v2_finalize(P);opened=false;
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    rethrow(err);
  end_try_catch
endfunction
function R=create_graph(session,dataset_id,xid,yid,xunit,title_text,kind)
  series={struct('id','distribution','dataset_id',dataset_id,'x_variable_id',xid,'y_variable_id',yid,'axis','left','kind',kind,'label',title_text)};
  axes=struct('x',struct('label',xid,'display_unit',xunit,'scale','linear'),'y_left',struct('label',yid,'scale','linear'));
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));
  if(!isfield(R,'artifact')||exist(R.artifact,'file')!=2),error('analysis.statistics.distribution: Plot Dataset returned no graph artifact');endif
endfunction
function write_manifest(path,graphs)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.distribution: cannot write graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(graphs));
    for i=1:numel(graphs)
      fprintf(fid,'\n[graph.%02d]\nkey=distribution.%02d\ngraph_id=%s\nvariant_id=%s\npng=distribution_graph_%02d.png\nprovider_artifact=%s\n',i,i,graphs(i).graph_id,graphs(i).variant_id,i,graphs(i).artifact);
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,source_id,vid,prefix,selection,mode,policy,H,E,Q,graph_count)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.distribution: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.statistics.distribution\nmodule_version=1.0.1\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nvariable_id=%s\nselection_id=%s\n',source_id,vid,selection_id(selection));
    fprintf(fid,'\n[analysis]\nbin_mode=%s\nnonfinite_policy=%s\nn_input=%d\nn_valid=%d\nn_nonfinite=%d\nn_inside=%d\nn_outside=%d\n',mode,policy,H.n_input,H.n_valid,H.n_nonfinite,H.n_inside,H.n_outside);
    fprintf(fid,'\n[output]\nprefix=%s\nbin_rows=%d\necdf_rows=%d\nquantile_rows=%d\nautomatic_graph_count=%d\n',prefix,numel(H.counts),numel(E.support),numel(Q.probabilities),graph_count);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,vid,unit,prefix,selection,mode,policy,H,E,Q)
  fid=fopen(path,'w');if(fid<0),error('analysis.statistics.distribution: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Empirical Distribution\nSource Dataset: %s\nVariable: %s (%s)\nSelection: %s\nBin rule: %s\nNaN / Inf: %s\nOutput prefix: %s\n',source_id,vid,unit,selection_id(selection),mode,policy,prefix);
    fprintf(fid,'Input: %d  Valid: %d  Excluded: %d  In bins: %d  Outside bins: %d\n',H.n_input,H.n_valid,H.n_nonfinite,H.n_inside,H.n_outside);
    fprintf(fid,'Bins: %d  ECDF support values: %d\n\nProbability | Quantile\n',numel(H.counts),numel(E.support));
    for i=1:numel(Q.probabilities),fprintf(fid,'%.12g | %.12g %s\n',Q.probabilities(i),Q.quantiles(i),unit);endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
