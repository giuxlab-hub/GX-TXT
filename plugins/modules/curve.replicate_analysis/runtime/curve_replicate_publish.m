function D=curve_replicate_publish(session,source_ids,traces,results,numeric_fn)
% Publish compact long-form analysis Datasets for Plot Dataset API v3.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='curve.replicate_analysis';D=struct();
  if(!iscell(source_ids)),source_ids={source_ids};endif
  source_ids=source_ids(!cellfun(@isempty,source_ids));

  % One long-form Dataset contains every accepted trace.  trace_index is the
  % stable row-filter key used by Plot Dataset; no per-trace Dataset fan-out.
  tx=[];ty=[];tidx=[];tsrc=[];trep=[];tfam=[];
  for i=1:numel(traces)
    t=traces(i);n=numel(t.x);
    tx=[tx;t.x(:)];ty=[ty;t.y(:)];tidx=[tidx;repmat(i,n,1)];
    tsrc=[tsrc;repmat(t.source_index,n,1)];trep=[trep;repmat(t.replicate_index,n,1)];
    tfam=[tfam;repmat(t.family_value,n,1)];
  endfor
  D.trace_id='curve.replicate.traces';
  publish_table(session,module_id,D.trace_id,source_ids, ...
    {'x',tx,'independent';'y',ty,'measured';'trace_index',tidx,'identifier'; ...
     'source_index',tsrc,'category';'replicate_index',trep,'replicate';'family_value',tfam,'family'});

  % One long-form Dataset contains every family profile and uncertainty field.
  px=[];pfi=[];pfv=[];pmean=[];pmedian=[];pstd=[];psem=[];psw=[];psb=[];pst=[];
  plstd=[];pustd=[];plsem=[];pusem=[];pltotal=[];putotal=[];
  for i=1:numel(results)
    r=results(i);n=numel(r.x);fi=repmat(i,n,1);fv=repmat(r.family_value,n,1);
    px=[px;r.x(:)];pfi=[pfi;fi];pfv=[pfv;fv];pmean=[pmean;r.y_mean(:)];pmedian=[pmedian;r.y_median(:)];
    pstd=[pstd;r.y_std(:)];psem=[psem;r.y_sem(:)];psw=[psw;r.sigma_within(:)];psb=[psb;r.sigma_between(:)];pst=[pst;r.sigma_total(:)];
    plstd=[plstd;r.y_mean(:)-r.y_std(:)];pustd=[pustd;r.y_mean(:)+r.y_std(:)];
    plsem=[plsem;r.y_mean(:)-r.y_sem(:)];pusem=[pusem;r.y_mean(:)+r.y_sem(:)];
    pltotal=[pltotal;r.y_mean(:)-r.sigma_total(:)];putotal=[putotal;r.y_mean(:)+r.sigma_total(:)];
  endfor
  D.profile_id='curve.replicate.profiles';
  publish_table(session,module_id,D.profile_id,source_ids, ...
    {'x',px,'independent';'family_index',pfi,'identifier';'family_value',pfv,'family'; ...
     'mean',pmean,'derived';'median',pmedian,'derived';'std',pstd,'uncertainty';'sem',psem,'uncertainty'; ...
     'sigma_within',psw,'uncertainty';'sigma_between',psb,'uncertainty';'sigma_total',pst,'uncertainty'; ...
     'lower_std',plstd,'derived';'upper_std',pustd,'derived';'lower_sem',plsem,'derived';'upper_sem',pusem,'derived'; ...
     'lower_sigma_total',pltotal,'derived';'upper_sigma_total',putotal,'derived'});

  valid=find([results.variance_components_identifiable]);D.summary_valid=!isempty(valid);
  if(D.summary_valid)
    n=numel(valid);labels=cell(1,n);summary_family_values=zeros(n,1);vals=zeros(n,3,3);
    for i=1:n
      r=results(valid(i));labels{i}=r.family_label;summary_family_values(i)=r.family_value;
      components={r.sigma_within,r.sigma_between,r.sigma_total};
      for j=1:3
        s=feval(numeric_fn,'statistics',components{j}(:),struct());
        vals(i,j,1)=s.rms;vals(i,j,2)=s.mean;vals(i,j,3)=s.max;
      endfor
    endfor
  else
    n=1;labels={'unavailable'};summary_family_values=NaN;vals=zeros(1,3,3);
  endif
  x=(1:n)';D.summary_labels=labels;D.summary_id='curve.replicate.family_summary';
  publish_table(session,module_id,D.summary_id,source_ids, ...
    {'family_index',x,'independent';'family_value',summary_family_values,'family';'x_within',x-0.25,'independent'; ...
     'x_between',x,'independent';'x_total',x+0.25,'independent'; ...
     'within_rms',vals(:,1,1),'uncertainty';'between_rms',vals(:,2,1),'uncertainty'; ...
     'total_rms',vals(:,3,1),'uncertainty'; ...
     'within_mean',vals(:,1,2),'uncertainty';'between_mean',vals(:,2,2),'uncertainty'; ...
     'total_mean',vals(:,3,2),'uncertainty'; ...
     'within_max',vals(:,1,3),'uncertainty';'between_max',vals(:,2,3),'uncertainty'; ...
     'total_max',vals(:,3,3),'uncertainty'});
endfunction

function publish_table(session,module_id,id,source_ids,cols)
  opts=struct('storage','auto','replace_owned',true,'producer_version','15.2', ...
    'source_dataset_ids',{source_ids},'source','Replicate Curve Analysis', ...
    'provenance','Replicate Curve Analysis v15.2; compact long-form derived Dataset');
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
