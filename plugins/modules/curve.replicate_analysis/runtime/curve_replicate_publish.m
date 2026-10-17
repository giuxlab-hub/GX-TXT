function D=curve_replicate_publish(session,source_ids,traces,results,reports)
% Publish canonical long-form Datasets with captured CORE interpretation.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!iscell(source_ids)),source_ids={source_ids};endif
  source_ids=source_ids(!cellfun(@isempty,source_ids));u=results(1);D=struct();
  D.trace_id='curve.replicate.traces';blocks={};
  for i=1:numel(traces)
    t=traces(i);blocks{end+1}={t.x,t.y,i,t.source_index,t.replicate_index,t.family_value};
  endfor
  records=reports.trace_records;
  for key=fieldnames(reports.source_records)',records.(key{1})=reports.source_records.(key{1});endfor
  publish_blocks(session,D.trace_id,source_ids, ...
    {'x',u.x_unit,'independent';'y',u.y_unit,'measured';'trace_index','1','identifier'; ...
     'source_index','1','category';'replicate_index','1','replicate';'family_value',u.family_unit,'family'},blocks,records);

  D.profile_id='curve.replicate.profiles';blocks={};segments={};offset=0;
  columns=u.core_statistics.producer_columns;fields=gxtxt_statistics_v1('numeric_fields',u.core_statistics.prototype);
  schema={'x',u.x_unit,'independent';'family_index','1','identifier';'family_value',u.family_unit,'family'};
  for k=1:rows(columns)
    unit=fields.(columns{k,1}).unit_text;if(strcmp(unit,'unspecified')),unit='';endif
    schema(end+1,:)={columns{k,2},unit,'derived'};
  endfor
  for i=1:numel(results)
    r=results(i);block={r.x,i,r.family_value};
    for k=1:rows(columns),block{end+1}=r.numeric_profile.(columns{k,1});endfor
    blocks{end+1}=block;n=numel(r.x);
    if(isempty(segments)||!isequal(segments{end}.prototype.context,r.core_statistics.prototype.context))
      segments{end+1}=struct('prototype',r.core_statistics.prototype,'column_variables',r.core_statistics.column_variables,'row_start',offset,'row_count',n);
    else segments{end}.row_count+=n;endif
    offset+=n;
  endfor
  records=struct();
  for i=1:numel(segments)
    s=segments{i};records.(sprintf('profile_%d',i))=gxtxt_statistics_v1('bind_columns',s.prototype,s.column_variables,s.row_count,s.row_start);
  endfor
  publish_blocks(session,D.profile_id,source_ids,schema,blocks,records);

  valid=find([results.variance_components_identifiable]);D.summary_valid=!isempty(valid);
  if(isempty(valid)),valid=1;placeholder=true;else placeholder=false;endif
  blocks={};labels={};
  for i=1:numel(valid)
    gi=valid(i);r=results(gi);indices=(gi-1)*4+(2:4);
    if(placeholder),family=NaN;labels{end+1}='unavailable';else family=r.family_value;labels{end+1}=r.family_label;endif
    v=reports.component_values;
    blocks{end+1}={i,family,i-.25,i,i+.25,v.root_mean_square(indices(1)),v.root_mean_square(indices(2)),v.root_mean_square(indices(3)), ...
      v.mean(indices(1)),v.mean(indices(2)),v.mean(indices(3)),v.maximum(indices(1)),v.maximum(indices(2)),v.maximum(indices(3))};
  endfor
  D.summary_labels=labels;D.summary_id='curve.replicate.family_summary';
  publish_blocks(session,D.summary_id,source_ids, ...
    {'family_index','1','independent';'family_value',u.family_unit,'family';'x_within','1','independent';'x_between','1','independent';'x_total','1','independent'; ...
     'within_rms',u.y_unit,'uncertainty';'between_rms',u.y_unit,'uncertainty';'total_rms',u.y_unit,'uncertainty'; ...
     'within_mean',u.y_unit,'uncertainty';'between_mean',u.y_unit,'uncertainty';'total_mean',u.y_unit,'uncertainty'; ...
     'within_max',u.y_unit,'uncertainty';'between_max',u.y_unit,'uncertainty';'total_max',u.y_unit,'uncertainty'},blocks,reports.component_records);
endfunction

function publish_blocks(session,id,source_ids,schema,blocks,records)
  opts=struct('storage','auto','replace_owned',true,'producer_version','15.3', ...
    'source_dataset_ids',{source_ids},'source','Replicate Curve Analysis', ...
    'provenance','Replicate Curve Analysis v15.3; captured CORE statistics and source-unit normalization','statistical_results',records);
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,'curve.replicate_analysis',id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for k=1:rows(schema)
      spec=struct('dtype','float64','dimension_ids','row','name',schema{k,1},'unit',schema{k,2},'semantic_role',schema{k,3},'axis_kind','explicit');
      if(k==1),spec.coordinate_role='coordinate';else spec.coordinate_role='data';spec.coordinate_variable_ids=schema{1,1};endif
      P=gxtxt_publication_v2_declare_variable(P,schema{k,1},spec);
    endfor
    for bi=1:numel(blocks)
      block=blocks{bi};n=numel(block{1});
      for first=1:50000:n
        last=min(n,first+49999);items=cell(rows(schema),2);
        for k=1:rows(schema)
          value=block{k};items{k,1}=schema{k,1};
          if(isscalar(value)),items{k,2}=repmat(value,last-first+1,1);
          elseif(numel(value)==n),items{k,2}=value(first:last);
          else error('curve.replicate_analysis: inconsistent published row span');endif
        endfor
        P=gxtxt_publication_v2_append(P,'row',items);
      endfor
    endfor
    [P,~]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction
