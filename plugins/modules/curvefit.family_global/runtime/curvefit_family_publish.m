function D=curvefit_family_publish(session,source_id,h,g,y,pred,residual,relative,metrics)
% Canonical graph data for fitting and frozen-parameter validation.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='curvefit.family_global';D=struct();
  [~,ord]=sortrows([h(:),g(:)],[1,2]);
  D.result_id='curvefit.family.result';
  publish_table(session,module_id,D.result_id,source_id, ...
    {'horizontal',h(ord),'independent';'group',g(ord),'family'; ...
     'measured_axis',y(ord),'independent';'measured',y(ord),'measured';'predicted',pred(ord),'derived'; ...
     'residual',residual(ord),'residual';'relative_percent',relative(ord),'residual'});
  lim=[min([y(:);pred(:)]),max([y(:);pred(:)])];
  if(lim(2)<=lim(1)),lim=lim+[-1,1];endif
  D.parity_min=lim(1);D.parity_max=lim(2);D.identity_id='curvefit.family.identity';
  publish_table(session,module_id,D.identity_id,source_id, ...
    {'measured',[lim(1);lim(2)],'independent';'identity',[lim(1);lim(2)],'reference'});
  D.metrics_id='curvefit.family.metrics';n=numel(metrics.family_value);D.group_labels=cell(1,n);
  for i=1:n,D.group_labels{i}=sprintf('%g',metrics.family_value(i));endfor
  publish_table(session,module_id,D.metrics_id,source_id, ...
    {'group_index',(1:n)','independent';'group_value',metrics.family_value(:),'family'; ...
     'rmse',metrics.rmse(:),'error';'mae',metrics.mae(:),'error'; ...
     'max_abs_error',metrics.max_abs_error(:),'error'});
endfunction

function publish_table(session,module_id,id,source_id,cols)
  opts=struct('storage','auto','replace_owned',true,'producer_version','5', ...
    'source_dataset_ids',{{source_id}},'source',source_id, ...
    'provenance','Curve family fit or frozen-parameter validation graph data');
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for k=1:rows(cols)
      name=cols{k,1};spec=struct('dtype','float64','dimension_ids','row', ...
        'name',name,'unit','','semantic_role',cols{k,3},'axis_kind','explicit');
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
    [P,~]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction
