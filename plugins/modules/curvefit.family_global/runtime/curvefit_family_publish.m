function D=curvefit_family_publish(session,source_id,h,g,y,pred,residual,relative,metrics,statistical_results,units,source_audit,parameter_state)
% Canonical graph data for fitting and frozen-parameter validation.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<12),source_audit=struct();endif
  if(nargin<13),parameter_state=struct();endif
  module_id='curvefit.family_global';D=struct('units',units,'metric_labels',struct());
  cells=metrics.export_rows{1}.cells;
  for name={'rmse','mae','max_abs_error'},D.metric_labels.(name{1})=cells.(name{1}).label;endfor
  [~,ord]=sortrows([h(:),g(:)],[1,2]);
  D.result_id='curvefit.family.result';
  result_columns={'horizontal',h(ord),'independent',units.horizontal;'group',g(ord),'family',units.group; ...
     'measured_axis',y(ord),'independent',units.response;'measured',y(ord),'measured',units.response;'predicted',pred(ord),'derived',units.response; ...
     'residual',residual(ord),'residual',units.response;'relative_percent',relative(ord),'residual','%'};
  if(isfield(source_audit,'source_row_ordinals'))
    source_rows=source_audit.source_row_ordinals;
    if(!isa(source_rows,'uint64')||numel(source_rows)!=numel(y)),error('curvefit.family_global: invalid retained source-row provenance');endif
    result_columns(:,5)={'float64'};
    result_columns(end+1,:)={'source_row_ordinal',source_rows(ord),'source_row','1','uint64'};
  endif
  D.publications.result=publish_table(session,module_id,D.result_id,source_id,result_columns,statistical_results);
  lim=[min([y(:);pred(:)]),max([y(:);pred(:)])];
  if(lim(2)<=lim(1)),lim=lim+[-1,1];endif
  D.parity_min=lim(1);D.parity_max=lim(2);D.identity_id='curvefit.family.identity';
  D.publications.identity=publish_table(session,module_id,D.identity_id,source_id, ...
    {'measured',[lim(1);lim(2)],'independent',units.response;'identity',[lim(1);lim(2)],'reference',units.response},statistical_results);
  D.metrics_id='curvefit.family.metrics';n=numel(metrics.family_value);D.group_labels=cell(1,n);
  for i=1:n,D.group_labels{i}=sprintf('%g',metrics.family_value(i));endfor
  D.publications.metrics=publish_table(session,module_id,D.metrics_id,source_id, ...
    {'group_index',(1:n)','independent','1';'group_value',metrics.family_value(:),'family',units.group; ...
     'rmse',metrics.rmse(:),'error',units.response;'mae',metrics.mae(:),'error',units.response; ...
     'max_abs_error',metrics.max_abs_error(:),'error',units.response},statistical_results);
  if(isfield(parameter_state,'plan'))
    plan=parameter_state.plan;values=parameter_state.values(:);n=columns(plan.parameter_indices);
    member_values=NaN(n,1);scope=repmat({'all_families'},n,1);
    if(plan.has_local),member_values=plan.member_values(:);scope=repmat({'member'},n,1);endif
    parameter_columns={'parameter_row',uint32((0:n-1)'),'independent','1','uint32'; ...
      'family_value',member_values,'family',parameter_state.family_unit,'float64'; ...
      'family_scope',scope,'label','','string'};
    for i=1:numel(plan.base_parameter_ids)
      indices=plan.parameter_indices(i,:);roles=repmat({'free'},n,1);
      roles(plan.fixed_mask(indices))={'fixed'};
      if(strcmp(parameter_state.operation_mode,'evaluate')),roles(:)={'frozen'};endif
      unit=plan.base_parameter_units{i};if(strcmp(unit,'unspecified')),unit='';endif
      parameter_columns(end+1,:)={sprintf('p%03d_estimate',i),values(indices),'parameter',unit,'float64'};
      parameter_columns(end+1,:)={sprintf('p%03d_role',i),roles,'label','','string'};
      parameter_columns(end+1,:)={sprintf('p%03d_scope',i),repmat(plan.scopes(i),n,1),'label','','string'};
    endfor
    D.parameters_id='curvefit.family.parameters';
    D.publications.parameters=publish_table(session,module_id,D.parameters_id,source_id,parameter_columns,statistical_results);
  endif
endfunction

function receipt=publish_table(session,module_id,id,source_id,cols,statistical_results)
  opts=struct('storage','auto','replace_owned',true,'producer_version','12', ...
    'source_dataset_ids',{{source_id}},'source',source_id, ...
    'provenance','Curve family fit or frozen-parameter validation graph data');
  opts.statistical_results=statistical_results;
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for k=1:rows(cols)
      dtype='float64';if(columns(cols)>=5&&!isempty(cols{k,5})),dtype=cols{k,5};endif
      name=cols{k,1};spec=struct('dtype',dtype,'dimension_ids','row', ...
        'name',name,'unit',cols{k,4},'semantic_role',cols{k,3},'axis_kind','explicit');
      if(k==1),spec.coordinate_role='coordinate';
      else spec.coordinate_role='data';spec.coordinate_variable_ids=cols{1,1};endif
      P=gxtxt_publication_v2_declare_variable(P,name,spec);
    endfor
    n=numel(cols{1,2});chunk=50000;
    for first=1:chunk:n
      last=min(n,first+chunk-1);items=cell(rows(cols),2);
      for k=1:rows(cols),items{k,1}=cols{k,1};v=cols{k,2};items{k,2}=v(first:last);endfor
      P=gxtxt_publication_v2_append(P,'row',items);
    endfor
    [P,receipt]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction
