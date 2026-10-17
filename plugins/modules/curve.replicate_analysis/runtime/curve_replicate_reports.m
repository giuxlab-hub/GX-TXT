function reports=curve_replicate_reports(traces,results,source_ids,numeric_fn)
% Capture each descriptive reduction once; CORE supplies all report values.
% SPDX-License-Identifier: GPL-3.0-or-later
  unit=results(1).y_unit;trace_raw={};trace_ids={};source_raw={};source_row_ids={};source_rows=struct([]);component_raw={};component_ids={};
  options=struct('nonfinite','omit','empty_policy','undefined');
  for i=1:numel(traces)
    trace_raw{end+1}=feval(numeric_fn,'statistics',traces(i).y,options);trace_ids{end+1}=sprintf('trace_%d',i);
  endfor
  kinds={'profile_dispersion','within','between','total'};
  for gi=1:numel(results)
    r=results(gi);components={r.y_std,r.sigma_within,r.sigma_between,r.sigma_total};
    for k=1:4
      component_raw{end+1}=feval(numeric_fn,'statistics',components{k},options);component_ids{end+1}=sprintf('family_%d_%s',gi,kinds{k});
    endfor
    for si=1:numel(r.numeric_profile.sources)
      sid=r.numeric_profile.sources(si);difference=r.numeric_profile.source_means(:,si)-r.y_mean;
      source_raw{end+1}=feval(numeric_fn,'statistics',difference,options);source_row_ids{end+1}=sprintf('family_%d_source_%d',gi,sid);
      selected=r.trace_indices([traces(r.trace_indices).source_index]==sid);
      row=struct('family_index',gi,'source_index',sid,'source_label',traces(selected(1)).source_label, ...
        'replicate_count',numel(selected),'point_count',sum([traces(selected).original_points]),'grid_count',numel(r.x));
      source_rows(end+1)=row;
    endfor
  endfor
  provenance=struct('module_id','curve.replicate_analysis','source_dataset_ids',{source_ids});
  [reports.trace_records,reports.trace_values]=capture(trace_raw,trace_ids,unit,provenance,'trace_summaries');
  [reports.source_records,reports.source_values]=capture(source_raw,source_row_ids,unit,provenance,'source_minus_consensus');
  [reports.component_records,reports.component_values]=capture(component_raw,component_ids,unit,provenance,'dispersion_across_grid');
  reports.trace_csv=csv_records(reports.trace_records,struct('y_mean','mean','y_std','standard_deviation'));
  reports.source_csv=csv_records(reports.source_records,struct('mean_bias','mean','rms_deviation','root_mean_square','max_abs_deviation','absolute_maximum'));
  reports.source_rows=source_rows;reports.component_text={};
  for key=fieldnames(reports.component_records)'
    reports.component_text{end+1}=gxtxt_statistics_v1('table_report',reports.component_records.(key{1}),{},{'n','root_mean_square','mean','maximum'});
  endfor
endfunction

function [records,values]=capture(raw,ids,unit,provenance,prefix)
  records=struct();values=struct('n',[],'mean',[],'standard_deviation',[],'root_mean_square',[],'maximum',[],'absolute_maximum',[]);
  mapping=gxtxt_statistics_v1('numeric_field_map','statistics');provenance.summary_kind=prefix;
  for first=1:8192:numel(raw)
    last=min(numel(raw),first+8191);columns=struct();
    for key=fieldnames(mapping)'
      name=key{1};columns.(name)=cellfun(@(item)item.(name),raw(first:last))';
    endfor
    result=gxtxt_statistics_v1('from_numeric_columns','math.numeric.summary','statistics',ids(first:last),columns,struct(),struct('y_unit',unit),provenance);
    records.(sprintf('%s_%d',prefix,first))=result;
    presented=gxtxt_statistics_v1('table_values',result,fieldnames(values)');
    for key=fieldnames(values)',name=key{1};values.(name)=[values.(name);presented.(name)(:)];endfor
  endfor
endfunction

function records=csv_records(tables,mapping)
  records={};
  for key=fieldnames(tables)'
    output=gxtxt_statistics_v1('table_csv_rows',tables.(key{1}),mapping);
    records=[records,reshape(output.records,1,[])];
  endfor
endfunction
