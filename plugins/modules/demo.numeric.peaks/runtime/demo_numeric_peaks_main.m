function demo_numeric_peaks_main(args,framework_root)
% Dataset-native peak demonstration using only the public NUMERIC_API_v1 peak operation.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='demo.numeric.peaks';module_version='1.0.2';publication_open=false;publication_finalized=false;P=struct();
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  gxtxt_progress_start('prepare','Preparing numerical peak-detection demonstration','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif;if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif
    x_binding=binding_column(gxtxt_ini_get(cfg,'bindings.x',''),'x');y_binding=binding_column(gxtxt_ini_get(cfg,'bindings.signal',''),'signal');if(isempty(x_binding)||isempty(y_binding)),error('%s: X and Signal Y bindings are required',module_id);endif
    [x_unit,~,x_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',x_binding);[y_unit,~,y_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',y_binding);
    if(!meta_found(x_meta)||!meta_found(y_meta)),error('%s: X or Signal Y binding could not be resolved',module_id);endif
    x_id=strtrim(x_meta.variable_id);y_id=strtrim(y_meta.variable_id);x_name=strtrim(x_meta.name);y_name=strtrim(y_meta.name);if(isempty(x_id)||isempty(y_id)),error('%s: stable X/Y variable IDs are required',module_id);endif;if(strcmp(x_id,y_id)),error('%s: X and Signal Y variables must be different',module_id);endif
    policy=lower(strtrim(gxtxt_ini_get(cfg,'config.nonfinite_policy','omit')));if(!any(strcmp(policy,{'omit','error'}))),error('%s: NaN / Inf policy must be omit or error',module_id);endif
    min_height=cfg_num(cfg,'config.min_height',0.5,module_id);min_prominence=cfg_num(cfg,'config.min_prominence',0.5,module_id);min_distance=cfg_num(cfg,'config.min_distance',8,module_id);relative_height=cfg_num(cfg,'config.relative_height',0.5,module_id);
    distance_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.distance_mode','x')));if(!any(strcmp(distance_mode,{'samples','x'}))),error('%s: Distance units must be x or samples',module_id);endif
    if(min_prominence<0||min_distance<0||relative_height<0||relative_height>1),error('%s: invalid peak option; prominence/distance must be non-negative and relative height must be within [0,1]',module_id);endif
    output_dataset_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','demo.numeric.peaks.detected'));if(isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once'))),error('%s: invalid Detected peaks Dataset ID',module_id);endif;if(strcmp(output_dataset_id,source_dataset_id)),error('%s: output Dataset ID must differ from source Dataset ID',module_id);endif
    selection=struct('enabled',false);try selection=gxtxt_selection_from_runtime(cfg,'selection');catch selerr,error('%s: invalid Dataset Selection: %s',module_id,selerr.message);end_try_catch
    if(selection.enabled),validate_selection(selection,source_dataset_id,x_id,module_id);endif
    metadata=read_optional_metadata(cfg);numeric=discover_numeric_api(framework_root,module_id);

    gxtxt_progress_stage('load_dataset','Reading selected source signal','indeterminate');
    [input_count,valid_count,source_provider]=count_selected_xy(cfg,x_id,y_id,selection);if(input_count<1),error('%s: selected input contains no rows',module_id);endif
    excluded_nonfinite=input_count-valid_count;
    opts=struct('nonfinite',policy,'min_height',min_height,'min_prominence',min_prominence,'min_distance',min_distance,'distance_mode',distance_mode,'relative_height',relative_height);if(selection.enabled),opts.selection=selection;endif

    gxtxt_progress_stage('numeric','Running public peak operation','determinate',1);
    result=feval(numeric.function_name,'dataset_find_peaks',session,source_dataset_id,x_id,y_id,opts);
    if(double(result.n)!=numel(result.indices)||double(result.n)!=numel(result.x)||double(result.n)!=numel(result.heights)||double(result.n)!=numel(result.prominences)||double(result.n)!=numel(result.widths)),error('%s: public peak result has inconsistent vector lengths',module_id);endif
    gxtxt_progress_update(1,1,'numeric',sprintf('Public peak operation detected %d peak(s)',double(result.n)));

    selection_id='';if(selection.enabled&&isfield(selection,'id')),selection_id=strtrim(selection.id);endif
    provenance=sprintf('%s %s via NUMERIC_API_v1 dataset_find_peaks; nonfinite=%s; min_height=%.17g; min_prominence=%.17g; min_distance=%.17g; distance_mode=%s; relative_height=%.17g; selection=%s',module_id,module_version,policy,min_height,min_prominence,min_distance,distance_mode,relative_height,selection_id);
    popts=struct('storage','auto','replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{x_id,y_id}},'source',source_dataset_id,'provenance',provenance,'notes','Detected peaks produced exclusively by the public math.numeric NUMERIC_API_v1 Dataset peak operation.');
    gxtxt_progress_stage('publish','Publishing detected-peaks Dataset','determinate',1);
    P=gxtxt_publication_v2_open(session,module_id,output_dataset_id,'table.generic',popts);publication_open=true;P=gxtxt_publication_v2_declare_dimension(P,'peak',0,true);
    P=declare_numeric(P,'peak_id','peak_id','identifier','1');P=declare_numeric(P,'peak_index','peak_index','sample_index','1');P=declare_numeric(P,'peak_x','peak_x','peak_position',x_unit);P=declare_numeric(P,'peak_y','peak_y','peak_amplitude',y_unit);P=declare_numeric(P,'prominence','prominence','prominence',y_unit);P=declare_numeric(P,'width','width','peak_width',x_unit);P=declare_numeric(P,'left_x','left_x','width_crossing',x_unit);P=declare_numeric(P,'right_x','right_x','width_crossing',x_unit);
    if(result.n>0),ids=(1:double(result.n))';P=gxtxt_publication_v2_append(P,'peak',{'peak_id',ids;'peak_index',double(result.indices(:));'peak_x',double(result.x(:));'peak_y',double(result.heights(:));'prominence',double(result.prominences(:));'width',double(result.widths(:));'left_x',double(result.left_x(:));'right_x',double(result.right_x(:))});endif
    [P,pub_diag]=gxtxt_publication_v2_diagnostics(P);[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;gxtxt_progress_update(1,1,'publish','Detected-peaks Dataset published');

    write_metrics(fullfile(outdir,'peak_detection_metrics.ini'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,source_provider,numeric,result,policy,min_height,min_prominence,min_distance,distance_mode,relative_height,metadata,P.provider);
    write_report(fullfile(outdir,'peak_detection_report.txt'),module_id,module_version,source_dataset_id,output_dataset_id,x_id,y_id,x_name,y_name,x_unit,y_unit,selection_id,input_count,valid_count,excluded_nonfinite,numeric,result,policy,min_height,min_prominence,min_distance,distance_mode,relative_height,metadata,pub_diag,pub_result);
    peak_count=double(result.n);
    save(fullfile(outdir,'render_cache.mat'),'source_dataset_id','output_dataset_id','x_id','y_id','peak_count','x_name','y_name','x_unit','y_unit');
    demo_numeric_peaks_render(outdir,source_dataset_id,output_dataset_id,x_id,y_id,peak_count,x_name,y_name,x_unit,y_unit,cfg);
    gxtxt_progress_complete('done',sprintf('Published %s with %d detected peak(s)',output_dataset_id,double(result.n)));
    fprintf('[%s] version=%s source=%s output=%s peaks=%d input=%d valid=%d excluded_nonfinite=%d validation=PASS\n',module_id,module_version,source_dataset_id,output_dataset_id,double(result.n),input_count,valid_count,excluded_nonfinite);
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Peak-detection demonstration failed; see log for details');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function tf=meta_found(meta),tf=isstruct(meta)&&isfield(meta,'found')&&meta.found;endfunction
function out=binding_column(value,role),value=strtrim(value);if(isempty(value)||strcmp(value,'auto')),out='';return;endif;dot=find(value=='.',1);if(!isempty(dot)),out=value(dot+1:end);else,out=value;endif;if(isempty(out)),error('demo.numeric.peaks: invalid %s binding',role);endif,endfunction
function validate_selection(S,dataset_id,x_id,module_id),if(!S.enabled),return;endif;if(!isfield(S,'source_dataset_id')||!strcmp(strtrim(S.source_dataset_id),dataset_id)),error('%s: Dataset Selection source does not match the bound Dataset',module_id);endif;if(!isfield(S,'type')||!strcmp(lower(strtrim(S.type)),'x_range')),error('%s: only X-range Dataset Selection is supported',module_id);endif;if(!isfield(S,'x_variable_id')||!strcmp(strtrim(S.x_variable_id),x_id)),error('%s: Dataset Selection X variable must match the bound X variable',module_id);endif;endfunction
function md=read_optional_metadata(cfg),try md=gxtxt_analysis_source_dataset_metadata(cfg,'primary');catch,md=struct('found',false,'count',0,'keys',{{}},'values',{{}});end_try_catch;endfunction
function [input_count,valid_count,provider]=count_selected_xy(cfg,x_id,y_id,selection)
  ids={x_id,y_id};S=gxtxt_table_stream_open_source(cfg,'primary',ids,65536,struct('start',0,'count',-1,'require_direct',false));provider=S.storage_provider;input_count=0;valid_count=0;
  unwind_protect
    while(!S.eof)
      [S,C]=gxtxt_table_stream_next(S);
      if(C.nrows>0)
        x=double(C.values{1}(:));y=double(C.values{2}(:));
        if(selection.enabled),mask=gxtxt_selection_mask(selection,x);x=x(mask);y=y(mask);endif
        input_count+=numel(x);valid_count+=sum(isfinite(x)&isfinite(y));
      endif
    endwhile
  unwind_protect_cleanup
    S=gxtxt_table_stream_close(S);
  end_unwind_protect
endfunction
function api=discover_numeric_api(root,module_id)
  descriptor=fullfile(root,'plugins','modules','math.numeric','module.ini');if(exist(descriptor,'file')!=2),error('%s: math.numeric descriptor missing',module_id);endif;d=gxtxt_ini_read(descriptor);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'NUMERIC_API_v1'))),error('%s: NUMERIC_API_v1 is not advertised',module_id);endif
  ver=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.api_version',''));if(!strcmp(ver,'1')),error('%s: unsupported NUMERIC_API_v1 version: %s',module_id,ver);endif;caps=split_list(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.capabilities',''));required={'peak_detection','dataset_peaks','dataset_selection','stable_variable_identity'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif,endfor
  entry=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_entrypoint',''));fn=strtrim(gxtxt_ini_get(d,'public_api.NUMERIC_API_v1.octave_function',''));if(isempty(entry)||isempty(fn)),error('%s: incomplete NUMERIC_API_v1 Octave binding',module_id);endif;entry_path=fullfile(fileparts(descriptor),entry);if(exist(entry_path,'file')!=2),error('%s: advertised NUMERIC_API_v1 entrypoint missing',module_id);endif;addpath(fileparts(entry_path));if(exist(fn,'file')!=2),error('%s: advertised NUMERIC_API_v1 function unavailable',module_id);endif;api=struct('name','NUMERIC_API_v1','api_version',ver,'function_name',fn,'entrypoint',entry);
endfunction
function P=declare_numeric(P,id,name,role,unit),spec=struct('dtype','float64','dimension_ids','peak','name',name,'unit',unit,'semantic_role',role,'coordinate_role','data','axis_kind','none');P=gxtxt_publication_v2_declare_variable(P,id,spec);endfunction
function write_metrics(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,provider,api,R,policy,min_height,min_prominence,min_distance,distance_mode,relative_height,md,out_provider)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write peak_detection_metrics.ini',id);endif
  fprintf(fid,'; GX-TXT demo.numeric.peaks metrics\n[module]\nid=%s\nversion=%s\nvalidation=PASS\n\n[source]\ndataset_id=%s\nx_variable_id=%s\ny_variable_id=%s\nx_name=%s\ny_name=%s\nx_unit=%s\ny_unit=%s\nstorage_provider=%s\nselection_id=%s\ninput_count=%d\nvalid_count=%d\nexcluded_nonfinite_count=%d\n',id,ver,src,xid,yid,ini_escape(xname),ini_escape(yname),ini_escape(xunit),ini_escape(yunit),provider,selection_id,input_count,valid_count,excluded);
  fprintf(fid,'\n[peak_detection]\npublic_operation=dataset_find_peaks\nnonfinite_policy=%s\nmin_height=%.17g\nmin_prominence=%.17g\nmin_distance=%.17g\ndistance_mode=%s\nrelative_height=%.17g\npeak_count=%d\nindex_base=%.0f\n',policy,min_height,min_prominence,min_distance,distance_mode,relative_height,double(R.n),double(R.index_base));
  fprintf(fid,'\n[numeric_api]\nname=%s\napi_version=%s\noctave_function=%s\n\n[metadata]\nresource_found=%d\n\n[output]\ndataset_id=%s\nstorage_provider=%s\n',api.name,api.api_version,api.function_name,double(logical(md.found)),outid,out_provider);fclose(fid);
endfunction
function write_report(path,id,ver,src,outid,xid,yid,xname,yname,xunit,yunit,selection_id,input_count,valid_count,excluded,api,R,policy,min_height,min_prominence,min_distance,distance_mode,relative_height,md,pub_diag,pub_result)
  fid=fopen(path,'w');if(fid<0),error('%s: cannot write peak_detection_report.txt',id);endif
  fprintf(fid,'GX-TXT Numerical Peak Detection Demo\n====================================\n\nPlugin: %s %s\nSource Dataset: %s\nX variable: %s (%s) [%s]\nY variable: %s (%s) [%s]\nSelection: %s\nPublic numerical operation: dataset_find_peaks via %s\n',id,ver,src,xname,xid,xunit,yname,yid,yunit,selection_text(selection_id),api.name);
  fprintf(fid,'NaN / Inf policy: %s\nInput sample count after Selection: %d\nValid sample count: %d\nExcluded non-finite pair count: %d\n\nConfiguration\n-------------\nMinimum height: %.12g %s\nMinimum prominence: %.12g %s\nMinimum distance: %.12g (%s)\nRelative height: %.12g\n',policy,input_count,valid_count,excluded,min_height,yunit,min_prominence,yunit,min_distance,distance_text(distance_mode,xunit),relative_height);
  fprintf(fid,'\nDetected peaks: %d\n\n',double(R.n));
  if(R.n>0)
    fprintf(fid,'ID   index   X [%s]            Y [%s]            prominence [%s]    width [%s]\n',xunit,yunit,yunit,xunit);
    for k=1:double(R.n),fprintf(fid,'%-4d %-7.0f %-18.12g %-18.12g %-18.12g %-18.12g\n',k,double(R.indices(k)),double(R.x(k)),double(R.heights(k)),double(R.prominences(k)),double(R.widths(k)));endfor
    fprintf(fid,'\nDetected X positions: %s\nDetected amplitudes: %s\n',vector_text(R.x),vector_text(R.heights));
  else
    fprintf(fid,'Detected X positions: none\nDetected amplitudes: none\n');
  endif
  fprintf(fid,'\nSemantics\n---------\nPeak indices are 1-based indices in the valid selected signal passed to NUMERIC_API_v1. Peak X values use the bound scientific X coordinate. Minimum distance uses %s. Width is right_x-left_x at level peak_y - relative_height*prominence; the default relative_height=0.5 is width at half prominence. X may be non-uniform but must be strictly increasing.\n',distance_text(distance_mode,xunit));
  fprintf(fid,'\nPublished Dataset\n-----------------\nDataset ID: %s\nColumns: peak_id, peak_index, peak_x, peak_y, prominence, width, left_x, right_x\nUnits: peak_x/width/left_x/right_x use X units; peak_y/prominence use Y units; identifiers/indices are dimensionless.\n',outid);
  fprintf(fid,'\nGraph\n-----\n01_peak_detection.png contains the selected valid source signal and markers at exactly the public peak X/Y results.\n\nDataset Metadata resource present: %s\n',bool_text(md.found));
  fprintf(fid,'\nWarnings\n--------\n');if(excluded>0),fprintf(fid,'- %d non-finite X/Y pair(s) were excluded by the explicit omit policy.\n',excluded);endif;if(R.n==0),fprintf(fid,'- No peaks matched the configured public peak criteria.\n',0);endif;if(excluded==0&&R.n>0),fprintf(fid,'None.\n');endif
  fprintf(fid,'\nValidation: PASS\n');fclose(fid);
endfunction
function s=distance_text(mode,xunit),if(strcmp(mode,'samples')),s='sample-index distance';else,if(isempty(strtrim(xunit))),s='physical X-coordinate distance';else,s=['physical X-coordinate distance in ' xunit];endif,endif,endfunction
function s=selection_text(id),if(isempty(id)),s='Full Dataset';else,s=id;endif,endfunction
function s=bool_text(v),if(v),s='yes';else,s='no';endif,endfunction
function s=vector_text(v),if(isempty(v)),s='none';return;endif;c=arrayfun(@(z)sprintf('%.12g',z),double(v(:))','UniformOutput',false);s=strjoin(c,', ');endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function v=cfg_num(cfg,key,def,module_id),raw=strtrim(gxtxt_ini_get(cfg,key,num2str(def,17)));v=str2double(raw);if(!isfinite(v)),error('%s: %s must be a finite number',module_id,key);endif,endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor,endfunction
function out=split_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};return;endif;out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endfunction
