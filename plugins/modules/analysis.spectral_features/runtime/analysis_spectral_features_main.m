function analysis_spectral_features_main(args)
% Dataset-native spectral descriptive features from an existing spectrum.
% Generic reusable numerical operations are provided by public NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.spectral_features';module_version='1.2.0';
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  numeric=discover_numeric_api(cfg,module_id);discover_plot_service(framework_root(),module_id);
  gxtxt_progress_start('prepare','Preparing spectral-feature analysis','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary spectrum Dataset ID is missing',module_id);endif
    f_binding=binding_column(gxtxt_ini_get(cfg,'bindings.frequency',''),'frequency');v_binding=binding_column(gxtxt_ini_get(cfg,'bindings.value',''),'value');
    if(isempty(f_binding)||isempty(v_binding)),error('%s: Frequency and Spectral value bindings are required',module_id);endif
    [f_unit,~,f_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',f_binding);[v_unit,~,v_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',v_binding);
    if(!meta_found(f_meta)||!meta_found(v_meta)),error('%s: selected bindings could not be resolved',module_id);endif
    f_id=strtrim(f_meta.variable_id);v_id=strtrim(v_meta.variable_id);f_name=strtrim(f_meta.name);v_name=strtrim(v_meta.name);
    if(isempty(f_id)||isempty(v_id)||strcmp(f_id,v_id)),error('%s: stable and distinct variable IDs are required',module_id);endif
    if(isempty(f_name)),f_name=f_id;endif;if(isempty(v_name)),v_name=v_id;endif
    try if(!gxtxt_unit_compatible(f_unit,'Hz')),error('%s: frequency variable unit %s is not frequency-compatible',module_id,f_unit);endif;catch e,error('%s: frequency variable unit %s cannot be used as frequency: %s',module_id,f_unit,e.message);end_try_catch
    sem=choice(gxtxt_ini_get(cfg,'config.input_semantics','amplitude'),'amplitude',{'amplitude','power','psd'});exclude_dc=strcmp(choice(gxtxt_ini_get(cfg,'config.exclude_dc','yes'),'yes',{'yes','no'}),'yes');
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','spectral_features.summary'));if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid output Dataset ID',module_id);endif
    distribution_dataset_id=[output_dataset_id '.distribution'];if(strcmp(output_dataset_id,source_dataset_id)||strcmp(distribution_dataset_id,source_dataset_id)),error('%s: output Dataset IDs must differ from source Dataset ID',module_id);endif

    gxtxt_progress_stage('load_dataset','Reading spectrum Dataset','indeterminate');[freq,val,source_provider]=read_spectrum(cfg,f_id,v_id);
    gxtxt_progress_stage('features','Computing spectral descriptors','indeterminate');R=spectral_features_compute(freq,val,sem,exclude_dc,numeric.function_name);
    R.statistics=gxtxt_statistics_v1('from_numeric','math.numeric.spectral_distribution','spectral_features',R,struct('x_unit',f_unit,'y_unit',v_unit),struct(), ...
      struct('producer',module_id,'dataset_id',source_dataset_id,'frequency_variable_id',f_id,'value_variable_id',v_id));
    R.fields=gxtxt_statistics_v1('numeric_fields',R.statistics);
    % Every scalar presentation comes from the captured CORE projection.
    for field=fieldnames(R.fields)'
      item=R.fields.(field{1});R.(field{1})=NaN;
      if(strcmp(item.status,'value')),R.(field{1})=item.value;endif
    endfor
    provenance=sprintf('%s %s; source spectrum=%s; frequency=%s; value=%s; semantics=%s; exclude_dc=%d',module_id,module_version,source_dataset_id,f_id,v_id,sem,exclude_dc);

    gxtxt_progress_stage('publish_distribution','Publishing plot-ready spectral distribution Dataset','indeterminate');
    [dist_diag,dist_result,dist_provider]=publish_distribution(session,module_id,module_version,distribution_dataset_id,source_dataset_id,{f_id,v_id},provenance,f_unit,R);
    gxtxt_progress_stage('publish_summary','Publishing spectral-feature summary Dataset','indeterminate');
    [sum_diag,sum_result,sum_provider]=publish_summary(session,module_id,module_version,output_dataset_id,source_dataset_id,{f_id,v_id},provenance,f_unit,R);

    write_metrics(fullfile(outdir,'spectral_features_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,distribution_dataset_id,f_id,v_id,f_name,v_name,f_unit,v_unit,source_provider,R,sum_provider,dist_provider);
    write_report(fullfile(outdir,'spectral_features_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,distribution_dataset_id,f_name,f_id,f_unit,v_name,v_id,v_unit,R,sum_diag,sum_result,dist_diag,dist_result);

    gxtxt_progress_stage('plot','Creating persistent plot.dataset spectral-feature graphs','indeterminate');
    graphs=create_standard_graphs(session,distribution_dataset_id,f_unit,module_id);copy_graph_artifacts(graphs,outdir,module_id);write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);
    gxtxt_progress_complete('done',sprintf('Published %s and %s',output_dataset_id,distribution_dataset_id));
    fprintf('[%s] version=%s source=%s summary=%s distribution=%s validation=PASS\n%s\n',module_id,module_version,source_dataset_id,output_dataset_id,distribution_dataset_id, ...
      gxtxt_statistics_v1('ini_report',R.statistics,struct('dominant','dominant_frequency','centroid','spectral_centroid','bandwidth','spectral_bandwidth')));
  catch err
    try gxtxt_progress_fail('failed','Spectral-feature analysis failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function [diag,result,provider]=publish_summary(session,module_id,module_version,dataset_id,source_dataset_id,source_vars,provenance,f_unit,R)
  P=struct();opened=false;finalized=false;
  try
    opts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_vars},'source',source_dataset_id,'provenance',provenance,'notes','One-row spectral-feature summary derived from an existing one-sided spectrum.');
    opts.statistical_results=struct('spectrum',R.statistics);
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'summary',0,true);
    ids={'dominant_frequency','spectral_centroid','rms_frequency','spectral_bandwidth','frequency_05','frequency_50','frequency_85','frequency_95','occupied_bandwidth_90','spectral_flatness','spectral_crest_factor','spectral_entropy','bin_count'};
    roles={'frequency','frequency','frequency','frequency_delta','frequency','frequency','frequency','frequency','frequency_delta','dimensionless','dimensionless','dimensionless','count'};
    units=cell(size(ids));for k=1:numel(ids),units{k}=R.fields.(ids{k}).unit_text;endfor
    vals={R.dominant_frequency,R.spectral_centroid,R.rms_frequency,R.spectral_bandwidth,R.frequency_05,R.frequency_50,R.frequency_85,R.frequency_95,R.occupied_bandwidth_90,R.spectral_flatness,R.spectral_crest_factor,R.spectral_entropy,R.bin_count};
    cells=cell(numel(ids),2);for i=1:numel(ids),P=declare_numeric(P,ids{i},R.fields.(ids{i}).label,roles{i},units{i},'summary');cells{i,1}=ids{i};cells{i,2}=vals{i};endfor
    P=gxtxt_publication_v2_append(P,'summary',cells);[P,diag]=gxtxt_publication_v2_diagnostics(P);[P,result]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;provider=P.provider;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif;rethrow(err);
  end_try_catch
endfunction

function [diag,result,provider]=publish_distribution(session,module_id,module_version,dataset_id,source_dataset_id,source_vars,provenance,f_unit,R)
  P=struct();opened=false;finalized=false;
  try
    opts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{source_vars},'source',source_dataset_id,'provenance',[provenance '; plot-ready spectral distribution'],'notes','Plot-ready normalized spectral distribution. The captured public Numeric result is interpreted by STATISTICAL_RESULT_SEMANTICS_API_v1.');
    opts.statistical_results=struct('spectrum',R.statistics);
    P=gxtxt_publication_v2_open(session,module_id,dataset_id,'table.generic',opts);opened=true;P=gxtxt_publication_v2_declare_dimension(P,'bin',0,true);
    P=declare_numeric(P,'frequency','frequency','frequency',f_unit,'bin');P=declare_numeric(P,'normalized_power','normalized_power','probability','1','bin');P=declare_numeric(P,'normalized_power_percent','normalized_power_percent','relative_level','%','bin');P=declare_numeric(P,'cumulative_power_percent','cumulative_power_percent','cumulative_probability','%','bin');P=declare_numeric(P,'relative_power_db','relative_power_dB','relative_level','dB','bin');
    P=gxtxt_publication_v2_append(P,'bin',{'frequency',R.frequency;'normalized_power',R.normalized_power;'normalized_power_percent',100*R.normalized_power;'cumulative_power_percent',100*R.cumulative_power;'relative_power_db',R.relative_power_db});
    [P,diag]=gxtxt_publication_v2_diagnostics(P);[P,result]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;provider=P.provider;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif;rethrow(err);
  end_try_catch
endfunction

function api=discover_numeric_api(cfg,module_id)
  sec='public_api.NUMERIC_API_v1';provider=strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],''));if(!strcmp(provider,'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif
  if(!strcmp(strtrim(gxtxt_ini_get(cfg,[sec '.api_version'],'')),'1')),error('%s: unsupported runtime NUMERIC_API_v1 version',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));required={'spectral_features'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif;endfor
  entry=strtrim(gxtxt_ini_get(cfg,[sec '.octave_entrypoint'],''));fn=strtrim(gxtxt_ini_get(cfg,[sec '.octave_function'],''));if(isempty(entry)||isempty(fn)||exist(entry,'file')!=2),error('%s: runtime NUMERIC_API_v1 Octave binding unavailable',module_id);endif
  addpath(fileparts(entry));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif;api=struct('function_name',fn,'provider',provider);
endfunction

function discover_plot_service(root,module_id)
  pd=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(pd,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif;d=gxtxt_ini_read(pd);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.PLOT_DATASET_API_v2.capabilities',''));if(!any(strcmp(caps,'series_kind_line'))),error('%s: PLOT_DATASET_API_v2 capability missing: series_kind_line',module_id);endif
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable',module_id);endif;addpath(fileparts(bridge));
endfunction

function G=create_standard_graphs(session,dataset_id,f_unit,module_id)
  G={};G{end+1}=create_line_plot(session,dataset_id,'relative_power_db','Spectral distribution — relative power','relative_power_db','Relative power','dB',f_unit,module_id);
  G{end+1}=create_line_plot(session,dataset_id,'normalized_power_percent','Spectral distribution — normalized power','normalized_power_percent','Normalized power per bin','%',f_unit,module_id);
  G{end+1}=create_line_plot(session,dataset_id,'cumulative_power_percent','Spectral distribution — cumulative power','cumulative_power_percent','Cumulative power','%',f_unit,module_id);
endfunction

function R=create_line_plot(session,dataset_id,key,title_text,yvar,ylabel_text,yunit,f_unit,module_id)
  axes=struct('x',struct('label',axis_label('Frequency',f_unit),'scale','linear'),'y_left',struct('label',axis_label(ylabel_text,yunit),'scale','linear'));
  series=struct('id',key,'dataset_id',dataset_id,'x_variable_id','frequency','y_variable_id',yvar,'axis','left','kind','line','label',ylabel_text,'style',struct());
  panel=struct('id','main','title',title_text,'axes',axes,'series',{{series}});spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));if(!isfield(R,'artifact')||isempty(strtrim(R.artifact))),error('%s: plot.dataset returned no artifact for %s',module_id,key);endif;R.key=key;
endfunction

function copy_graph_artifacts(G,outdir,module_id),for i=1:numel(G),src=strtrim(G{i}.artifact);if(isempty(src)||exist(src,'file')!=2),error('%s: plot.dataset graph artifact missing for %s',module_id,G{i}.key);endif;dst=fullfile(outdir,sprintf('%02d_%s.png',i,G{i}.key));[ok,msg]=copyfile(src,dst,'f');if(!ok),error('%s: cannot copy plot.dataset artifact: %s',module_id,msg);endif;endfor;endfunction
function write_graph_manifest(path,G),fid=fopen(path,'w');if(fid<0),error('analysis.spectral_features: cannot write automatic graph manifest');endif;unwind_protect fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(G));for i=1:numel(G),fprintf(fid,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%02d_%s.png\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',i,G{i}.key,ini_escape(G{i}.graph_id),ini_escape(G{i}.variant_id),i,G{i}.key,ini_escape(G{i}.artifact));endfor;unwind_protect_cleanup fclose(fid);end_unwind_protect;endfunction

function [f,v,provider]=read_spectrum(cfg,fid,vid),S=gxtxt_table_stream_open_source(cfg,'primary',{fid,vid},65536,struct('start',0,'count',-1,'require_direct',false));provider=S.storage_provider;fc={};vc={};unwind_protect while(!S.eof),[S,C]=gxtxt_table_stream_next(S);if(C.nrows>0),fc{end+1}=double(C.values{1}(:));vc{end+1}=double(C.values{2}(:));endif;endwhile;unwind_protect_cleanup S=gxtxt_table_stream_close(S);end_unwind_protect;if(isempty(fc)),f=zeros(0,1);v=zeros(0,1);else,f=vertcat(fc{:});v=vertcat(vc{:});endif;endfunction
function P=declare_numeric(P,id,name,role,unit,dim),spec=struct('dtype','float64','dimension_ids',dim,'name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('analysis.spectral_features: invalid %s binding',role);endif;endfunction
function v=choice(raw,def,allowed),v=lower(strtrim(raw));if(!any(strcmp(v,allowed))),v=def;endif;endfunction
function root=framework_root(),runtime_dir=fileparts(mfilename('fullpath'));module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);root=fileparts(plugins_dir);endfunction
function s=axis_label(name,unit),if(isempty(strtrim(unit))||strcmp(unit,'1')),s=name;else,s=sprintf('%s [%s]',name,unit);endif;endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif;endfor;endfunction

function write_metrics(path,id,ver,src,outid,distid,fid,vid,fname,vname,funit,vunit,src_provider,R,sum_provider,dist_provider)
  fh=fopen(path,'w');if(fh<0),error('%s: cannot write metrics',id);endif
  unwind_protect
    fprintf(fh,'; GX-TXT spectral features with public CORE interpretation\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n',id,ver);
    fprintf(fh,'\n[source]\ndataset_id=%s\nfrequency_variable_id=%s\nvalue_variable_id=%s\nfrequency_name=%s\nvalue_name=%s\nfrequency_unit=%s\nvalue_unit=%s\nstorage_provider=%s\n',src,fid,vid,ini_escape(fname),ini_escape(vname),ini_escape(funit),ini_escape(vunit),src_provider);
    fprintf(fh,'\n[analysis]\ninput_semantics=%s\nexclude_dc=%d\nspacing_relative_deviation=%.17g\n',R.input_semantics,R.exclude_dc,R.spacing_relative_deviation);
    mapping=gxtxt_statistics_v1('numeric_field_map','spectral_features');
    % Retain the established INI frequency_spacing name and scientific IDs.
    mapping.frequency_spacing=mapping.df;mapping=rmfield(mapping,'df');
    fprintf(fh,'%s\n',gxtxt_statistics_v1('ini_report',R.statistics,mapping));
    fprintf(fh,'\n[output]\nsummary_dataset_id=%s\nsummary_storage_provider=%s\ndistribution_dataset_id=%s\ndistribution_storage_provider=%s\n',outid,sum_provider,distid,dist_provider);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction

function write_report(path,id,ver,src,outid,distid,fname,fid,funit,vname,vid,vunit,R,sum_diag,sum_result,dist_diag,dist_result)
  fh=fopen(path,'w');if(fh<0),error('%s: cannot write report',id);endif
  unwind_protect
    fprintf(fh,'GX-TXT Spectral Features\nPlugin: %s %s\nSource spectrum Dataset: %s\nFrequency: %s (%s) [%s]\nSpectral value: %s (%s) [%s]\nInput semantics: %s\nExclude DC: %d\n\n',id,ver,src,fname,fid,funit,vname,vid,vunit,R.input_semantics,R.exclude_dc);
    mapping=gxtxt_statistics_v1('numeric_field_map','spectral_features');
    fprintf(fh,'%s\n',gxtxt_statistics_v1('report',R.statistics,struct2cell(mapping)));
    fprintf(fh,'\nPublished Datasets\nSummary: %s\nDistribution: %s\nSummary diagnostics: %s\nSummary result: %s\nDistribution diagnostics: %s\nDistribution result: %s\n',outid,distid,sum_diag,sum_result,dist_diag,dist_result);
  unwind_protect_cleanup
    fclose(fh);
  end_unwind_protect
endfunction
