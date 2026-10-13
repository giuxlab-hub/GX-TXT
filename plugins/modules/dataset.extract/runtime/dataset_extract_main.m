% SPDX-License-Identifier: GPL-3.0-or-later
% Dataset Extract preserves its module identity and legacy controls. All data
% selection, projection, compatibility checks and publication belong to CORE.
function dataset_extract_main(config_path)
  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if (isempty(outdir)), error('dataset.extract: runtime.output_dir is missing'); endif
  row_mode = lower(strtrim(gxtxt_ini_get(cfg,'config.row_mode','selected')));
  column_mode = lower(strtrim(gxtxt_ini_get(cfg,'config.column_mode','all')));
  output_id = strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','dataset.extracted'));
  if (!any(strcmp(row_mode,{'all','selected','unselected'}))), error('Rows must be all, selected or unselected'); endif
  if (!any(strcmp(column_mode,{'all','trace'}))), error('Variables must be all or trace'); endif
  if (isempty(output_id)), error('Enter an output Dataset ID'); endif
  metadata = struct('extract_module','dataset.extract','extract_module_version','1.3.0', ...
                    'extract_row_mode',row_mode,'extract_column_mode',column_mode);
  manifest = struct('api_version',1,'operation','project_variables','sources',{{}}, ...
                    'output',struct('dataset_id',output_id,'storage','auto','contract','auto'), ...
                    'options',struct('metadata',metadata),'schema_policy',struct(),'metadata_policy','explicit');
  selection_id = '';
  if (!strcmp(row_mode,'all'))
    selection_id = strtrim(gxtxt_ini_get(cfg,'selection.selection.id',''));
    if (isempty(selection_id)), error('Selected/Unselected rows require a Dataset Selection'); endif
    manifest.selection_id = selection_id;
    if (strcmp(row_mode,'selected')), manifest.selection_operation='keep'; else manifest.selection_operation='exclude'; endif
    selection_type = strtrim(gxtxt_ini_get(cfg,'selection.selection.type',''));
    if (strcmp(selection_type,'members'))
      manifest.operation = 'combine_selection';
      manifest.selection_trace = strcmp(column_mode,'trace');
    else
      % Legacy selections use one source; preserve the configured trace
      % bindings rather than requiring a rectangle to carry a Y binding.
      manifest.operation = 'subset_rows';
      if (strcmp(column_mode,'trace'))
        manifest.options.variable_ids = trace_ids_local(cfg);
      endif
    endif
  else
    source_id = strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if (isempty(source_id)), source_id = strtrim(gxtxt_ini_get(cfg,'dataset.id','')); endif
    if (isempty(source_id)), error('All rows requires a primary Dataset'); endif
    source = struct('dataset_id',source_id);
    if (strcmp(column_mode,'trace')), source.variable_ids = trace_ids_local(cfg); endif
    manifest.sources = {source};
  endif
  gxtxt_progress_start('extract','Publishing Dataset through CORE Transform','indeterminate');
  result = gxtxt_dataset_transform_execute(config_path,manifest);
  row_count=result.row_count; if(ischar(row_count)),row_count=str2double(row_count);endif
  report = fullfile(outdir,'extract_report.txt');
  fid=fopen(report,'w');if(fid<0),error('Cannot write extraction report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Dataset Extract 1.3.0\noutput_dataset_id=%s\nrow_count=%s\nrow_mode=%s\ncolumn_mode=%s\nselection_id=%s\ntransform_authority=DATASET_TRANSFORM_API_v1\n', ...
                result.dataset_id,num2str(row_count),row_mode,column_mode,selection_id);
    fprintf(fid,'source_mutation=none\ninterpolation=none\nrow_order=preserved per member\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  fid=fopen(fullfile(outdir,'extract_provenance.ini'),'w');if(fid<0),error('Cannot write extraction provenance');endif
  unwind_protect
    fprintf(fid,'[extract]\nmodule_version=1.3.0\noutput_dataset_id=%s\nselection_id=%s\ntransform_authority=DATASET_TRANSFORM_API_v1\ncomplete_provenance=Dataset structured metadata transform.manifest and transform.effective\n',result.dataset_id,selection_id);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  gxtxt_progress_complete('done',['Published ' result.dataset_id]);
  fprintf('[dataset.extract] output=%s via CORE Dataset Transform\n',result.dataset_id);
endfunction

function ids = trace_ids_local(cfg)
  ids = {};
  for role = {'trace_x','trace_y'}
    value = strtrim(gxtxt_ini_get(cfg,['bindings.' role{1}],''));
    if (isempty(value) || strcmpi(value,'auto')), error('Trace mode requires X/Y bindings'); endif
    dot=find(value=='.',1);
    if (!isempty(dot))
      if (!strcmp(value(1:dot-1),'primary')), error('Legacy trace binding must use primary source'); endif
      value=value(dot+1:end);
    endif
    [~,~,meta] = gxtxt_analysis_source_variable_meta(cfg,'primary',value);
    if (!meta.found || isempty(meta.variable_id)), error('Unknown trace variable %s',value); endif
    if (!any(strcmp(ids,meta.variable_id))), ids{end+1}=meta.variable_id; endif
  endfor
endfunction
