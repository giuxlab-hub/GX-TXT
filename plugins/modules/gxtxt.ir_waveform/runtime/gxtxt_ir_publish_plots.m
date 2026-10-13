function D=gxtxt_ir_publish_plots(session,source_id,S)
% Publish display data separately from the full-resolution IR scientific outputs.
% SPDX-License-Identifier: GPL-3.0-or-later
  D=struct();D.full='ir.plot.full';D.carrier='ir.plot.carrier';
  D.markspace='ir.plot.markspace';D.durations='ir.plot.durations';
  ir_plot_table(session,source_id,D.full,{'time_ms',S.overview_t_ms(:),'independent'; ...
    'minimum',S.overview_vMin(:),'measured';'maximum',S.overview_vMax(:),'measured'});
  ir_plot_table(session,source_id,D.carrier,{'time_us',S.carrier_t_us(:),'independent'; ...
    'signal',S.carrier_v(:),'measured'});
  ir_plot_table(session,source_id,D.markspace,{'time_ms',S.logic_t_ms(:),'independent'; ...
    'state',S.logic_y(:),'derived'});
  n=numel(S.burstDuration);space=NaN(n,1);ns=min(n,numel(S.spaceDuration));
  if(ns>0),space(1:ns)=S.spaceDuration(1:ns)(:)*1e6;endif
  ir_plot_table(session,source_id,D.durations,{'burst',(1:n)','independent'; ...
    'mark_us',S.burstDuration(:)*1e6,'derived';'space_us',space,'derived'});
  D.compare=struct();D.count=0;D.names={};
  if(!isfield(S,'analog_chain')||numel(S.analog_chain)<2),return;endif
  A=S.analog_chain;D.count=numel(A);D.names=cell(1,numel(A));
  specs={'absolute','abs_t_ms','abs_vMax','abs_vMin'; ...
    'baseline','zero_t_ms','zero_vMax','zero_vMin'; ...
    'normalized','norm_t_ms','norm_vMax','norm_vMin'; ...
    'envelope','env_t_ms','env_v',''; ...
    'margin','margin_t_ms','margin_v',''; ...
    'gain','gain_t_ms','gain_v',''};
  for j=1:rows(specs),D.compare.(specs{j,1})=cell(1,numel(A));endfor
  for k=1:numel(A)
    D.names{k}=A(k).name;
    for j=1:rows(specs)
      key=specs{j,1};if(strcmp(key,'gain')&&k==1),continue;endif
      x=A(k).(specs{j,2})(:);y=A(k).(specs{j,3})(:);
      if(isempty(x)||isempty(y)),continue;endif
      cols={'time_ms',x,'independent';'value',y,'derived'};
      if(!isempty(specs{j,4})),cols(end+1,:)={'minimum',A(k).(specs{j,4})(:),'derived'};endif
      id=sprintf('ir.plot.%s.%02d',key,k);ir_plot_table(session,source_id,id,cols);
      D.compare.(key){k}=id;
    endfor
  endfor
endfunction

function ir_plot_table(session,source_id,id,cols)
  opts=struct('storage','auto','replace_owned',true,'producer_version','3.6.2', ...
    'source_dataset_ids',{{source_id}},'source',source_id, ...
    'provenance','IR waveform graph display data');
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,'gxtxt.ir_waveform',id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for j=1:rows(cols)
      name=cols{j,1};spec=struct('dtype','float64','dimension_ids','row', ...
        'name',name,'unit','','semantic_role',cols{j,3},'axis_kind','explicit');
      if(j==1),spec.coordinate_role='coordinate';
      else spec.coordinate_role='data';spec.coordinate_variable_ids=cols{1,1};endif
      P=gxtxt_publication_v2_declare_variable(P,name,spec);
    endfor
    n=numel(cols{1,2});chunk=50000;
    for first=1:chunk:n
      last=min(n,first+chunk-1);items=cell(rows(cols),2);
      for j=1:rows(cols),items{j,1}=cols{j,1};v=cols{j,2};items{j,2}=v(first:last);endfor
      P=gxtxt_publication_v2_append(P,'row',items);
    endfor
    [P,~]=gxtxt_publication_v2_finalize(P);opened=false;finalized=true;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction
