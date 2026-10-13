function analysis_dataset_expression_main(args,framework_root)
% Controlled Dataset expression with stable bindings and public services.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.dataset_expression';version='1.0.1';
  config_path=argument(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  source_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(source_id)),source_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  if(isempty(session)||isempty(outdir)||isempty(source_id)),error('%s: Session, output directory and source Dataset are required',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  P=struct();opened=false;
  gxtxt_progress_start('prepare','Preparing Dataset expression','indeterminate');
  try
    definition_file=strtrim(gxtxt_ini_get(cfg,'config.definition_file',''));
    if(!isempty(definition_file))
      if(!is_absolute(definition_file)),definition_file=fullfile(session,definition_file);endif
      if(exist(definition_file,'file')!=2),error('%s: saved calculation definition is unavailable',module_id);endif
      def=gxtxt_ini_read(definition_file);
      if(!strcmp(strtrim(gxtxt_ini_get(def,'definition.source_dataset_id','')),source_id))
        error('%s: saved definition requires a different stable source Dataset ID',module_id);
      endif
      expr=strtrim(gxtxt_ini_get(def,'definition.expression',''));
      bindings=read_bindings(def,'binding');
    else
      expr=strtrim(gxtxt_ini_get(cfg,'config.expression',''));
      bindings=read_bindings(cfg,'repeatable_config.bindings');
    endif
    if(isempty(expr)),error('%s: expression is required',module_id);endif
    rpn=gxtxt_analysis_expression_parse(expr);
    symbols={};for i=1:numel(rpn),if(strcmp(rpn{i}.kind,'id')&&!any(strcmp(symbols,rpn{i}.text))),symbols{end+1}=rpn{i}.text;endif,endfor
    for i=1:numel(symbols),if(!any(strcmp({bindings.symbol},symbols{i}))),error('%s: expression symbol %s has no binding',module_id,symbols{i});endif,endfor
    selection=gxtxt_selection_from_runtime(cfg,'selection');
    if(selection.enabled)
      if(!strcmp(strtrim(selection.source_dataset_id),source_id)),error('%s: Selection belongs to another Dataset',module_id);endif
      selection=resolve_selection(cfg,selection);
    endif
    output_id=strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','analysis.expression.result'));
    output_vid=strtrim(gxtxt_ini_get(cfg,'config.output_variable_id','result'));
    output_unit=strtrim(gxtxt_ini_get(cfg,'config.output_unit',''));
    if(isempty(regexp(output_id,'^[A-Za-z0-9_.-]+$','once'))||strcmp(output_id,source_id))
      error('%s: invalid or conflicting output Dataset ID',module_id);
    endif
    if(isempty(regexp(output_vid,'^[A-Za-z][A-Za-z0-9_]*$','once'))||strcmp(output_vid,'source_row'))
      error('%s: invalid output variable ID',module_id);
    endif
    series=struct();units=struct();used_ids={};matrix_ids={};matrix_symbols={};
    for i=1:numel(bindings)
      b=bindings(i);if(!any(strcmp(symbols,b.symbol))),continue;endif
      if(any(strcmp(b.kind,{'series','row','selection'})))
        lookup=b.variable;if(!isempty(b.variable_id)),lookup=b.variable_id;endif
        [source_unit,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',lookup);
        if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found&&strcmp(strtrim(meta.dataset_id),source_id)))
          error('%s: stable variable binding for %s could not be resolved',module_id,b.symbol);
        endif
        if(!any(strcmp(lower(strtrim(meta.value_kind)),{'number','elapsed_time'})))
          error('%s: variable for %s must be numeric',module_id,b.symbol);
        endif
        b.variable_id=strtrim(meta.variable_id);
        if(isempty(b.variable_id)),error('%s: stable variable ID is missing',module_id);endif
        if(strcmp(lower(strtrim(meta.value_kind)),'elapsed_time')),source_unit='s';endif
        if(isempty(strtrim(source_unit))),source_unit=strtrim(b.unit);endif
        if(isempty(source_unit)),error('%s: variable %s has no unit; specify one explicitly',module_id,b.variable_id);endif
        b.unit=source_unit;bindings(i)=b;
        if(!any(strcmp(used_ids,b.variable_id))),used_ids{end+1}=b.variable_id;endif
        if(any(strcmp(b.kind,{'series','selection'}))&&!any(strcmp(matrix_ids,b.variable_id)))
          matrix_ids{end+1}=b.variable_id;
        endif
      else
        if(isempty(strtrim(b.unit))),b.unit='1';endif
        bindings(i)=b;
      endif
    endfor
    if(!isempty(matrix_ids))
      gxtxt_progress_stage('read','Reading selected Dataset series','indeterminate');
      [matrix,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,'primary',matrix_ids,selection,65536);
      if(rows(matrix)<1),error('%s: no selected source rows',module_id);endif
    else
      matrix=[];source_rows=[];
    endif
    for i=1:numel(bindings)
      b=bindings(i);if(!any(strcmp(symbols,b.symbol))),continue;endif
      switch(b.kind)
        case 'series'
          idx=find(strcmp(matrix_ids,b.variable_id),1);value=matrix(:,idx);
        case 'literal'
          value=parse_scalar(b.literal,sprintf('literal %s',b.symbol));
        case 'metadata'
          if(isempty(b.metadata_key)),error('%s: metadata key is required for %s',module_id,b.symbol);endif
          [raw,found]=gxtxt_analysis_source_dataset_metadata_get(cfg,'primary',b.metadata_key);
          if(!found),error('%s: metadata key %s is missing',module_id,b.metadata_key);endif
          value=parse_scalar(raw,sprintf('metadata %s',b.metadata_key));
        case 'row'
          row=parse_positive_integer(b.source_row,sprintf('source row for %s',b.symbol));
          value=read_source_row(cfg,b.variable_id,row);
        case 'selection'
          if(!selection.enabled),error('%s: selection scalar %s requires an enabled Dataset Selection',module_id,b.symbol);endif
          idx=find(strcmp(matrix_ids,b.variable_id),1);column=matrix(:,idx);
          if(any(!isfinite(column))),error('%s: selection scalar %s includes NaN or Inf',module_id,b.symbol);endif
          if(!any(strcmp(b.aggregate,{'mean','median','minimum','maximum','sum'})))
            error('%s: invalid Selection aggregate for %s',module_id,b.symbol);
          endif
          reduced=gxtxt_numeric_v1('array_reduce',b.aggregate,column);
          value=reduced.values;
        otherwise
          error('%s: unsupported binding kind for %s',module_id,b.symbol);
      endswitch
      series.(b.symbol)=value;units.(b.symbol)=b.unit;
    endfor
    gxtxt_progress_stage('compute','Evaluating controlled numerical expression','indeterminate');
    [result,result_unit]=gxtxt_analysis_expression_strict_units(expr,series,units,output_unit);
    if(!(isnumeric(result)||islogical(result))||!isreal(result)||isempty(result))
      error('%s: expression result must be a nonempty real numeric scalar or vector',module_id);
    endif
    if(isscalar(result))
      result_kind='scalar';published_rows=1;result=double(result);
    elseif(isvector(result)&&!isempty(source_rows)&&numel(result)==numel(source_rows))
      result_kind='series';published_rows=numel(source_rows);result=double(result(:));
    else
      error('%s: expression result shape does not match selected Dataset rows',module_id);
    endif
    gxtxt_progress_stage('publish','Publishing derived Dataset','indeterminate');
    opts=struct('storage','auto','replace_owned',true,'producer_version',version, ...
      'source','GX-TXT Dataset Expression', ...
      'provenance',sprintf('%s %s; source=%s; variables=%s; selection=%s; expression=%s',module_id,version,source_id,strjoin(used_ids,';'),selection_id(selection),expr), ...
      'notes','Controlled expression with stable source bindings and strict Unit Registry validation.');
    opts.source_dataset_ids={source_id};opts.source_variable_ids=used_ids;
    P=gxtxt_publication_v2_open(session,module_id,output_id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    if(strcmp(result_kind,'series'))
      P=gxtxt_publication_v2_declare_variable(P,'source_row',struct('dtype','int64','dimension_ids','row','name','Original one-based source row','unit','','semantic_role','index'));
    endif
    P=gxtxt_publication_v2_declare_variable(P,output_vid,struct('dtype','float64','dimension_ids','row','name',output_vid,'unit',result_unit,'semantic_role','derived'));
    if(strcmp(result_kind,'series')),items={'source_row',int64(source_rows);output_vid,result};
    else items={output_vid,result};endif
    P=gxtxt_publication_v2_append(P,'row',items);
    [P,published]=gxtxt_publication_v2_finalize(P);opened=false;
    write_definition(fullfile(outdir,'expression_definition.ini'),source_id,expr,bindings,symbols,result_unit);
    write_summary(fullfile(outdir,'expression_summary.ini'),source_id,output_id,output_vid,expr,result_unit,selection,result_kind,published_rows,used_ids);
    write_report(fullfile(outdir,'expression_report.txt'),source_id,output_id,output_vid,expr,result_unit,selection,result_kind,published_rows,bindings,symbols);
    fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');
    if(fid<0),error('%s: cannot write graph manifest',module_id);endif
    fprintf(fid,'[automatic_graphs]\ncount=0\nprovider=plot.dataset\n');fclose(fid);
    gxtxt_progress_complete('done',sprintf('Published %s result with %d row(s)',result_kind,published_rows));
    fprintf('[%s] source=%s output=%s kind=%s rows=%d\n',module_id,source_id,output_id,result_kind,published_rows);
  catch err
    if(opened),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch,endif
    try gxtxt_progress_fail('failed','Dataset expression failed; see log');catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function value=argument(args,key,default)
  value=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),value=args{i+1};return;endif,endfor
endfunction
function tf=is_absolute(path)
  tf=(!isempty(regexp(path,'^[A-Za-z]:[/\\]','once'))||!isempty(regexp(path,'^[/\\]','once')));
endfunction
function value=parse_scalar(text,label)
  value=str2double(strtrim(text));
  if(!isscalar(value)||!isfinite(value)),error('analysis.dataset_expression: %s must be a finite numeric scalar',label);endif
endfunction
function value=parse_positive_integer(text,label)
  value=parse_scalar(text,label);
  if(value<1||value!=fix(value)),error('analysis.dataset_expression: %s must be a positive integer',label);endif
endfunction
function bindings=read_bindings(cfg,prefix)
  rows_text=strtrim(gxtxt_ini_get(cfg,[prefix '.rows'],''));rows=strsplit(rows_text,';');
  bindings=struct('symbol',{},'kind',{},'variable',{},'variable_id',{},'literal',{},'metadata_key',{},'source_row',{},'aggregate',{},'unit',{});
  for i=1:numel(rows)
    row=strtrim(rows{i});if(isempty(row)),continue;endif
    p=[prefix '.' row '.'];
    symbol=strtrim(gxtxt_ini_get(cfg,[p 'symbol'],''));kind=lower(strtrim(gxtxt_ini_get(cfg,[p 'kind'],'series')));
    if(isempty(regexp(symbol,'^[A-Za-z_][A-Za-z0-9_]*$','once')))
      error('analysis.dataset_expression: binding symbol must be an identifier');
    endif
    if(any(strcmp({bindings.symbol},symbol))),error('analysis.dataset_expression: duplicate symbol %s',symbol);endif
    if(!any(strcmp(kind,{'series','literal','metadata','row','selection'})))
      error('analysis.dataset_expression: invalid binding kind for %s',symbol);
    endif
    bindings(end+1)=struct('symbol',symbol,'kind',kind, ...
      'variable',strtrim(gxtxt_ini_get(cfg,[p 'variable'],'')), ...
      'variable_id',strtrim(gxtxt_ini_get(cfg,[p 'variable_id'],'')), ...
      'literal',strtrim(gxtxt_ini_get(cfg,[p 'literal'],'')), ...
      'metadata_key',strtrim(gxtxt_ini_get(cfg,[p 'metadata_key'],'')), ...
      'source_row',strtrim(gxtxt_ini_get(cfg,[p 'source_row'],'')), ...
      'aggregate',lower(strtrim(gxtxt_ini_get(cfg,[p 'aggregate'],'mean'))), ...
      'unit',strtrim(gxtxt_ini_get(cfg,[p 'unit'],'')));
  endfor
  if(isempty(bindings)),error('analysis.dataset_expression: at least one symbol binding is required');endif
endfunction
function value=read_source_row(cfg,variable_id,row)
  stream=gxtxt_table_stream_open_source(cfg,'primary',{variable_id},1,struct('start',row-1,'count',1,'require_direct',false,'numeric_transport','auto'));
  unwind_protect
    [stream,chunk]=gxtxt_table_stream_next(stream);
    if(chunk.nrows!=1||!(isnumeric(chunk.values{1})||islogical(chunk.values{1})))
      error('analysis.dataset_expression: requested source row is unavailable or nonnumeric');
    endif
    value=double(chunk.values{1}(1));
    if(!isfinite(value)),error('analysis.dataset_expression: requested source-row scalar is NaN or Inf');endif
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
endfunction
function selection=resolve_selection(cfg,selection)
  if(isempty(strtrim(selection.x_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.x_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.dataset_expression: cannot resolve Selection X variable');endif
    selection.x_variable_id=strtrim(meta.variable_id);
  endif
  if(strcmp(selection.type,'rectangle')&&isempty(strtrim(selection.y_variable_id)))
    [~,~,meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',selection.y_variable);
    if(!(isstruct(meta)&&isfield(meta,'found')&&meta.found)),error('analysis.dataset_expression: cannot resolve Selection Y variable');endif
    selection.y_variable_id=strtrim(meta.variable_id);
  endif
endfunction
function id=selection_id(selection)
  id='none';if(isfield(selection,'enabled')&&selection.enabled&&isfield(selection,'id')),id=selection.id;endif
endfunction
function write_definition(path,source_id,expr,bindings,symbols,result_unit)
  fid=fopen(path,'w');if(fid<0),error('analysis.dataset_expression: cannot save definition');endif
  unwind_protect
    fprintf(fid,'[definition]\napi_version=1\nsource_dataset_id=%s\nexpression=%s\nresult_unit=%s\n',safe(source_id),safe(expr),safe(result_unit));
    ids={};for i=1:numel(bindings),if(any(strcmp(symbols,bindings(i).symbol))),ids{end+1}=sprintf('b%03d',numel(ids)+1);endif,endfor
    fprintf(fid,'\n[binding]\nrows=%s\n',strjoin(ids,';'));
    n=0;
    for i=1:numel(bindings)
      b=bindings(i);if(!any(strcmp(symbols,b.symbol))),continue;endif;n+=1;
      fprintf(fid,'\n[binding.%s]\n',ids{n});
      for field={'symbol','kind','variable','variable_id','literal','metadata_key','source_row','aggregate','unit'}
        key=field{1};fprintf(fid,'%s=%s\n',key,safe(b.(key)));
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_summary(path,source_id,output_id,output_vid,expr,unit,selection,kind,n,used_ids)
  fid=fopen(path,'w');if(fid<0),error('analysis.dataset_expression: cannot write summary');endif
  unwind_protect
    fprintf(fid,'[meta]\nmodule_id=analysis.dataset_expression\nmodule_version=1.0.1\napi=NUMERIC_API_v1\n');
    fprintf(fid,'\n[source]\ndataset_id=%s\nvariable_ids=%s\nselection_id=%s\n',safe(source_id),safe(strjoin(used_ids,';')),safe(selection_id(selection)));
    fprintf(fid,'\n[calculation]\nexpression=%s\nresult_kind=%s\nresult_unit=%s\n',safe(expr),kind,safe(unit));
    fprintf(fid,'\n[output]\ndataset_id=%s\nvariable_id=%s\nrows=%d\n',safe(output_id),safe(output_vid),n);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function write_report(path,source_id,output_id,output_vid,expr,unit,selection,kind,n,bindings,symbols)
  fid=fopen(path,'w');if(fid<0),error('analysis.dataset_expression: cannot write report');endif
  unwind_protect
    fprintf(fid,'GX-TXT Dataset Expression\nSource Dataset: %s\nSelection: %s\nExpression: %s\nOutput: %s / %s (%s)\nResult: %s, %d row(s)\n',safe(source_id),safe(selection_id(selection)),safe(expr),safe(output_id),safe(output_vid),safe(unit),kind,n);
    fprintf(fid,'\nSymbol | Kind | Stable variable ID | Unit\n');
    for i=1:numel(bindings),b=bindings(i);if(any(strcmp(symbols,b.symbol))),fprintf(fid,'%s | %s | %s | %s\n',b.symbol,b.kind,b.variable_id,b.unit);endif,endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function out=safe(value)
  out=strrep(strrep(char(value),sprintf('\r'),' '),sprintf('\n'),' ');
endfunction
