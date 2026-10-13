% SPDX-License-Identifier: GPL-3.0-or-later
% Concatenate non-overlapping canonical timeseries.table datasets.
%
% Scientific policy:
% - source selection order is ignored;
% - each source must be strictly increasing in absolute time;
% - schemas must match exactly;
% - gaps are preserved;
% - overlaps, including an identical boundary timestamp, are rejected;
% - no interpolation, averaging, resampling or row alignment is performed.

function sequence_table_join_main(config_path)
  cfg = gxtxt_ini_read(config_path);
  outdir = strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  if (isempty(outdir)), error('sequence.table_join: runtime.output_dir is missing'); endif

  output_dataset_id = strtrim(gxtxt_ini_get(cfg,'config.output_dataset_id','sequence.joined'));
  abs_col = strtrim(gxtxt_ini_get(cfg,'config.absolute_time_column','timestamp_s'));
  rel_col = strtrim(gxtxt_ini_get(cfg,'config.relative_time_column','time_s'));
  if (isempty(output_dataset_id)), error('sequence.table_join: Output Dataset ID is required'); endif
  if (isempty(regexp(output_dataset_id,'^[A-Za-z0-9_.-]+$','once')))
    error('sequence.table_join: invalid Output Dataset ID "%s"',output_dataset_id);
  endif
  if (isempty(abs_col)), error('sequence.table_join: absolute time column is required'); endif

  source_ids = split_list_local(gxtxt_ini_get(cfg,'analysis_sources.ids',''));
  if (isempty(source_ids))
    error('sequence.table_join: no Analysis Source Map is available');
  endif

  gxtxt_progress_start('read_sources','Reading sequential datasets','determinate',numel(source_ids));

  seg = struct('source_id',{},'dataset_id',{},'path',{},'kind',{},'table',{}, ...
               'time',{},'start_s',{},'end_s',{},'rows',{},'units',{},'roles',{});
  canonical_names = {};
  canonical_units = {};
  canonical_roles = {};
  metadata_complete = [];
  input_order = {};

  for k = 1:numel(source_ids)
    sid = strtrim(source_ids{k});
    p = strtrim(gxtxt_ini_get(cfg,['analysis_source.' sid '.path'],''));
    if (isempty(p))
      % Dynamic optional rows may be left empty in the framework GUI.
      continue;
    endif
    dsid = strtrim(gxtxt_ini_get(cfg,['analysis_source.' sid '.dataset_id'],sid));
    kind = strtrim(gxtxt_ini_get(cfg,['analysis_source.' sid '.kind'],''));
    if (!isempty(kind) && !strcmp(kind,'timeseries.table'))
      error('sequence.table_join: source %s (%s) has contract %s; timeseries.table is required',sid,dsid,kind);
    endif
    if (exist(p,'file') != 2)
      error('sequence.table_join: canonical source file is missing: %s',p);
    endif

    T = gxtxt_read_csv_table(p);
    if (T.nrows < 1), error('sequence.table_join: dataset %s is empty',dsid); endif

    if (isempty(canonical_names))
      canonical_names = T.names;
    elseif (!same_cellstr_local(canonical_names,T.names))
      error('sequence.table_join: schema mismatch in dataset %s. All input tables must have identical columns in identical order.',dsid);
    endif

    [src_units,src_roles] = source_variable_metadata_local(cfg,sid,T.names);
    if (isempty(canonical_units))
      canonical_units = src_units;
      canonical_roles = src_roles;
      metadata_complete = true(1,numel(T.names));
      for mi=1:numel(T.names), metadata_complete(mi)=!isempty(src_units{mi}); endfor
    else
      [canonical_units,canonical_roles,metadata_complete] = merge_metadata_local( ...
          canonical_names,canonical_units,canonical_roles,metadata_complete,src_units,src_roles,dsid);
    endif

    t = gxtxt_table_column(T,abs_col,'numeric');
    if (numel(t) != T.nrows || any(!isfinite(t)))
      error('sequence.table_join: dataset %s has invalid/non-finite values in %s',dsid,abs_col);
    endif
    if (numel(t) > 1 && any(diff(t) <= 0))
      error('sequence.table_join: dataset %s is not strictly increasing in %s',dsid,abs_col);
    endif

    s = struct();
    s.source_id = sid;
    s.dataset_id = dsid;
    s.path = p;
    s.kind = kind;
    s.table = T;
    s.time = t(:);
    s.start_s = t(1);
    s.end_s = t(end);
    s.rows = T.nrows;
    s.units = src_units;
    s.roles = src_roles;
    seg(end+1) = s; %#ok<AGROW>
    input_order{end+1} = dsid; %#ok<AGROW>
    gxtxt_progress_update(k,numel(source_ids),'read_sources',sprintf('Read %s (%d rows)',dsid,T.nrows));
  endfor

  if (numel(seg) < 2)
    error('sequence.table_join: at least two populated source datasets are required');
  endif

  gxtxt_progress_stage('validate','Sorting segments and checking boundaries','indeterminate');
  [~,ord] = sort([seg.start_s]);
  seg = seg(ord);

  for k = 2:numel(seg)
    if (seg(k).start_s <= seg(k-1).end_s)
      error(['sequence.table_join: overlap or duplicate boundary detected between %s and %s ' ...
             '(previous end %.17g, next start %.17g)'], ...
             seg(k-1).dataset_id,seg(k).dataset_id,seg(k-1).end_s,seg(k).start_s);
    endif
  endfor

  names = canonical_names;
  rel_idx = 0;
  if (!isempty(rel_col))
    rel_idx = find(strcmp(names,rel_col),1);
    if (isempty(rel_idx))
      names{end+1} = rel_col;
      rel_idx = numel(names);
      canonical_units{end+1} = '';
      canonical_roles{end+1} = '';
      metadata_complete(end+1) = false;
    endif
    abs_idx = find(strcmp(names,abs_col),1);
    if (!isempty(abs_idx) && abs_idx <= numel(canonical_units) && metadata_complete(abs_idx))
      canonical_units{rel_idx} = canonical_units{abs_idx};
      metadata_complete(rel_idx) = true;
    endif
    if (isempty(canonical_roles{rel_idx})), canonical_roles{rel_idx} = 'independent'; endif
  endif

  % Do not assert a unit for a joined column unless every source supplied it.
  for mi=1:numel(canonical_units)
    if (mi > numel(metadata_complete) || !metadata_complete(mi)), canonical_units{mi}=''; endif
  endfor

  total_rows = sum([seg.rows]);
  global_t0 = seg(1).start_s;
  out_csv = fullfile(outdir,'joined_sequence.csv');
  report_path = fullfile(outdir,'join_report.txt');

  gxtxt_progress_stage('write','Writing joined time series','determinate',total_rows);
  write_joined_csv_local(out_csv,names,seg,rel_idx,global_t0,total_rows);
  write_report_local(report_path,output_dataset_id,abs_col,rel_col,input_order,seg,total_rows,global_t0);

  % The Dataset Publication API makes the result immediately available to
  % later modules in the same session after this module exits successfully.
  meta = struct();
  meta.variables = names;
  meta.units = canonical_units;
  meta.semantic_roles = canonical_roles;
  meta.source = 'Sequential Table Join';
  meta.provenance = ['Chronological concatenation of canonical datasets: ' join_dataset_ids_local(seg)];
  meta.notes = ['Input order ignored; sorted by ' abs_col '; gaps preserved; overlaps rejected; no interpolation/resampling.'];
  gxtxt_dataset_publish_request(outdir,output_dataset_id,'timeseries.table','csv','joined_sequence.csv',meta);

  gxtxt_progress_complete('done',sprintf('Joined %d datasets, %d rows',numel(seg),total_rows));
  fprintf('[sequence.table_join] datasets=%d rows=%d output_dataset=%s\n',numel(seg),total_rows,output_dataset_id);
endfunction

function write_joined_csv_local(path,names,seg,rel_idx,global_t0,total_rows)
  fid = fopen(path,'w');
  if (fid < 0), error('sequence.table_join: cannot write %s',path); endif
  unwind_protect
    write_csv_row_local(fid,names);
    done = 0;
    for k = 1:numel(seg)
      T = seg(k).table;
      for r = 1:T.nrows
        row = T.rows(r,:);
        if (numel(row) < numel(names)), row(end+1:numel(names)) = {''}; endif
        if (rel_idx > 0)
          row{rel_idx} = sprintf('%.15g',seg(k).time(r)-global_t0);
        endif
        write_csv_row_local(fid,row);
        done += 1;
        if (mod(done,1000) == 0 || done == total_rows)
          gxtxt_progress_update(done,total_rows,'write',sprintf('Writing row %d of %d',done,total_rows));
        endif
      endfor
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_report_local(path,output_dataset_id,abs_col,rel_col,input_order,seg,total_rows,global_t0)
  fid = fopen(path,'w');
  if (fid < 0), error('sequence.table_join: cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'GX-TXT Sequential Table Join\n');
    fprintf(fid,'module_version=2\n');
    fprintf(fid,'output_dataset_id=%s\n',output_dataset_id);
    fprintf(fid,'absolute_time_column=%s\n',abs_col);
    fprintf(fid,'relative_time_column=%s\n',rel_col);
    fprintf(fid,'source_count=%d\n',numel(seg));
    fprintf(fid,'row_count=%d\n',total_rows);
    fprintf(fid,'global_start_s=%.17g\n',global_t0);
    fprintf(fid,'input_selection_order=%s\n',strjoin(input_order,';'));
    fprintf(fid,'chronological_order=%s\n',join_dataset_ids_local(seg));
    fprintf(fid,'policy=gaps preserved; overlaps rejected; no interpolation/resampling\n');
    fprintf(fid,'\nSEGMENTS\n');
    for k = 1:numel(seg)
      fprintf(fid,'%d\tdataset=%s\tsource=%s\trows=%d\tstart=%.17g\tend=%.17g\n', ...
              k,seg(k).dataset_id,seg(k).source_id,seg(k).rows,seg(k).start_s,seg(k).end_s);
      if (k > 1)
        fprintf(fid,'  separation_from_previous_s=%.17g\n',seg(k).start_s-seg(k-1).end_s);
      endif
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_csv_row_local(fid,row)
  for c = 1:numel(row)
    if (c > 1), fprintf(fid,','); endif
    fprintf(fid,'%s',csv_escape_local(row{c}));
  endfor
  fprintf(fid,'\n');
endfunction

function s = csv_escape_local(v)
  if (isnumeric(v)), s = sprintf('%.17g',v); else s = v; endif
  if (!ischar(s)), s = ''; endif
  s = strrep(s,'"','""');
  if (any(s==',') || any(s=='"') || any(s==sprintf('\n')) || any(s==sprintf('\r')))
    s = ['"' s '"'];
  endif
endfunction


function [units,roles] = source_variable_metadata_local(cfg,sid,names)
  units=cell(1,numel(names)); roles=cell(1,numel(names));
  for i=1:numel(names)
    units{i}=''; roles{i}='';
    try
      [u,r] = gxtxt_analysis_source_variable_meta(cfg,sid,names{i});
      units{i}=strtrim(u); roles{i}=strtrim(r);
    catch
      units{i}=''; roles{i}='';
    end_try_catch
  endfor
endfunction

function [units,roles,complete] = merge_metadata_local(names,units,roles,complete,new_units,new_roles,dsid)
  for i=1:numel(names)
    u0=strtrim(units{i}); u1=strtrim(new_units{i});
    if(isempty(u1))
      complete(i)=false;
    elseif(isempty(u0))
      % A missing earlier unit makes the aggregate unit unknown even if later
      % segments provide one.  Keep the later text only for mismatch checking.
      units{i}=u1; complete(i)=false;
    elseif(!strcmp(u0,u1))
      error('sequence.table_join: unit mismatch for column %s: %s vs %s in dataset %s. Join does not rescale source data.',names{i},u0,u1,dsid);
    endif
    r0=strtrim(roles{i}); r1=strtrim(new_roles{i});
    if(isempty(r0)), roles{i}=r1;
    elseif(!isempty(r1)&&!strcmpi(r0,r1))
      error('sequence.table_join: semantic-role mismatch for column %s: %s vs %s in dataset %s',names{i},r0,r1,dsid);
    endif
  endfor
endfunction

function out = split_list_local(s)
  s = strrep(s,';',',');
  raw = strsplit(s,',');
  out = {};
  for i = 1:numel(raw)
    q = strtrim(raw{i});
    if (!isempty(q)), out{end+1} = q; endif %#ok<AGROW>
  endfor
endfunction

function tf = same_cellstr_local(a,b)
  tf = (numel(a) == numel(b));
  if (!tf), return; endif
  for k = 1:numel(a)
    if (!strcmp(a{k},b{k})), tf = false; return; endif
  endfor
endfunction

function s = join_dataset_ids_local(seg)
  ids = cell(1,numel(seg));
  for k = 1:numel(seg), ids{k} = seg(k).dataset_id; endfor
  s = strjoin(ids,';');
endfunction
