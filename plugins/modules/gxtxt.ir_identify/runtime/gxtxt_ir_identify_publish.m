function ids=gxtxt_ir_identify_publish(session,source_id,R,order,D,E,F)
% Publish graph data as canonical Datasets, keeping diagnostic CSVs intact.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='gxtxt.ir_identify';base=['irid.' safe_id(source_id)];
  opts=struct('storage','auto','replace_owned',true,'producer_version','2.0', ...
    'source_dataset_ids',{{source_id}},'source',source_id, ...
    'provenance','IR protocol identification from measured MARK/SPACE events');
  n=numel(order);names=cell(n,1);pids=cell(n,1);scores=zeros(n,1);
  for k=1:n,names{k}=R(order(k)).name;pids{k}=R(order(k)).id;scores(k)=R(order(k)).score;endfor
  ids=struct();ids.ranking=publish_table(session,module_id,[base '.ranking'],opts, ...
    {'rank',(1:n)','float64','1','independent'; ...
     'score',scores,'float64','1','measured'; ...
     'candidate_name',names,'string','','label'; ...
     'protocol_id',pids,'string','','identifier'});
  if(!isempty(D))
    m=numel(D);labels=cell(m,1);for k=1:m,labels{k}=D(k).label;endfor
    ids.timing=publish_table(session,module_id,[base '.timing'],opts, ...
      {'timing_item',(1:m)','float64','1','independent'; ...
       'measured_us',[D.measured_us]','float64','us','measured'; ...
       'expected_us',[D.expected_us]','float64','us','reference'; ...
       'item_label',labels,'string','','label'});
  else
    ids.timing='';
  endif
  m=numel(E.type);marks=NaN(m,1);spaces=NaN(m,1);
  for k=1:m,if(strcmp(E.type{k},'MARK')),marks(k)=E.duration_us(k);else spaces(k)=E.duration_us(k);endif,endfor
  ids.events=publish_table(session,module_id,[base '.events'],opts, ...
    {'event_index',(1:m)','float64','1','independent'; ...
     'mark_us',marks,'float64','us','measured'; ...
     'space_us',spaces,'float64','us','measured'});
  m=numel(F.type);t=zeros(2*m,1);carrier=zeros(2*m,1);t0=F.start_s(1);
  for k=1:m
    q=2*k-1;t(q)=(F.start_s(k)-t0)*1000;t(q+1)=(F.end_s(k)-t0)*1000;
    level=double(strcmp(F.type{k},'MARK'));carrier(q:q+1)=level;
  endfor
  ids.frame=publish_table(session,module_id,[base '.frame'],opts, ...
    {'time_ms',t,'float64','ms','independent'; ...
     'carrier_present',carrier,'float64','1','measured'});
endfunction
function id=publish_table(session,module_id,id,opts,cols)
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,module_id,id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    x_id=cols{1,1};items=cell(rows(cols),2);
    for k=1:rows(cols)
      name=cols{k,1};values=cols{k,2};dtype=cols{k,3};unit=cols{k,4};role=cols{k,5};
      spec=struct('dtype',dtype,'dimension_ids','row','name',name,'unit',unit,'semantic_role',role,'axis_kind','explicit');
      if(k==1),spec.coordinate_role='coordinate';else spec.coordinate_role='data';if(!strcmp(dtype,'string')),spec.coordinate_variable_ids=x_id;else spec.value_kind='text';endif,endif
      P=gxtxt_publication_v2_declare_variable(P,name,spec);
      items{k,1}=name;items{k,2}=values;
    endfor
    P=gxtxt_publication_v2_append(P,'row',items);
    [P,~]=gxtxt_publication_v2_finalize(P);finalized=true;opened=false;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction
function s=safe_id(raw),s=regexprep(strtrim(raw),'[^A-Za-z0-9_.-]','_');if(isempty(s)),s='source';endif;endfunction
