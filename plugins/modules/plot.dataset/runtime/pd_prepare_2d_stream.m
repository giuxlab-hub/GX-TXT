function S=pd_prepare_2d_stream(session,dataset_id,xid,yid,aux_ids,requested,target,threshold,chunk_rows,stage_tag,x_window,row_filters)
% Dataset-native bounded preparation for one 2-D Graph Series.
% Reads stable Dataset/Variable IDs through Table Stream API v3. The reducer
% keeps source-row extrema and never creates or modifies canonical data.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<10||isempty(stage_tag)),stage_tag='series';endif
  if(nargin<11||isempty(x_window)),x_window=struct('enabled',false);endif
  if(nargin<12||isempty(row_filters)),row_filters={};endif
  if(isempty(aux_ids)),aux_ids={};endif;if(ischar(aux_ids)),aux_ids={aux_ids};endif
  filter_ids=cell(1,numel(row_filters));
  for j=1:numel(row_filters),filter_ids{j}=row_filters{j}.filter_variable_id;endfor
  aux_ids=unique_stable(aux_ids);ids=unique_stable([{xid,yid} aux_ids filter_ids]);
  if(isempty(strtrim(session))||isempty(strtrim(dataset_id))||isempty(strtrim(xid))||isempty(strtrim(yid)))
    error('plot.dataset: dataset-native 2-D preparation requires session, dataset_id, x_variable_id and y_variable_id');
  endif

  % Metadata-only open. For implicit coordinates this does not materialize X.
  probe=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct());
  schema=probe.schema;row_count=probe.row_count;provider=probe.storage_provider;plan=range_plan(probe,xid,x_window);
  window_bounds=source_window_bounds(schema,xid,x_window);
  probe=gxtxt_table_stream_close(probe);

  options=struct('start',plan.start,'count',plan.count,'require_direct',false);
  st=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,options);
  planned_rows=st.range_count;if(planned_rows<0),planned_rows=max(0,row_count-st.range_start);endif
  effective=lower(strtrim(requested));if(!any(strcmp(effective,{'auto','none','stride','minmax'}))),effective='auto';endif
  if(strcmp(effective,'auto')),if(planned_rows>threshold),effective='minmax';else effective='none';endif;endif
  target=max(2,round(target));stride=max(1,ceil(max(1,planned_rows)/target));
  bucket_count=max(1,floor(max(2,target-2)/2));bucket_rows=max(1,ceil(max(1,planned_rows)/bucket_count));

  xout=[];yout=[];seqout=[];aout=cell(1,numel(aux_ids));for j=1:numel(aout),aout{j}=[];endfor
  x_payload_numeric=false;x_payload_seen=false;
  valid_rows=0;dropped_rows=0;filter_dropped_rows=0;window_filtered_rows=0;seen=0;bindex=-1;bmin=[];bmax=[];first_valid=[];last_valid=[];diag=struct();
  total=max(1,planned_rows);stage=['load_' stage_tag];
  gxtxt_progress_stage(stage,sprintf('Loading %s from Dataset %s (%s reduction)',yid,dataset_id,effective),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      if(ch.nrows>0)
        if(!x_payload_seen),xr=gxtxt_table_chunk_column(ch,xid);x_payload_numeric=isnumeric(xr)||islogical(xr);x_payload_seen=true;endif
        xv=gxtxt_table_chunk_numeric(ch,xid);yv=gxtxt_table_chunk_numeric(ch,yid);av=aux_chunk(ch,aux_ids);
        finite_ok=isfinite(xv)&isfinite(yv);for j=1:numel(av),if(isnumeric(av{j})),finite_ok&=isfinite(av{j});endif;endfor
        filter_ok=gxtxt_graph_series_filter_mask(ch,row_filters);
        ok=finite_ok&filter_ok;
        if(window_bounds.enabled),ok&=(xv>=window_bounds.lo)&(xv<=window_bounds.hi);endif
        idx=find(ok);nv=numel(idx);valid_rows+=nv;dropped_rows+=ch.nrows-sum(finite_ok);filter_dropped_rows+=sum(finite_ok)-sum(finite_ok&filter_ok);window_filtered_rows+=sum(finite_ok&filter_ok)-nv;
        if(nv>0)
          seqv=ch.offset+idx-1;
          if(isempty(first_valid)),first_valid=make_row(xv(idx(1)),yv(idx(1)),av,idx(1),seqv(1));endif
          last_valid=make_row(xv(idx(end)),yv(idx(end)),av,idx(end),seqv(end));
          if(strcmp(effective,'none'))
            [xout,yout,aout,seqout]=append_indices(xout,yout,aout,seqout,xv,yv,av,idx,seqv);
          elseif(strcmp(effective,'stride'))
            ord=(seen:(seen+nv-1))';keep=mod(ord,stride)==0;pick=idx(keep);pickseq=seqv(keep);seen+=nv;
            [xout,yout,aout,seqout]=append_indices(xout,yout,aout,seqout,xv,yv,av,pick,pickseq);
          else
            biv=floor((seqv-st.range_start)/bucket_rows);cuts=[1;find(diff(biv)!=0)+1;nv+1];
            for g=1:numel(cuts)-1
              a=cuts(g);b=cuts(g+1)-1;bi=biv(a);gidx=idx(a:b);gseq=seqv(a:b);
              [~,imn]=min(yv(gidx));[~,imx]=max(yv(gidx));rmin=make_row(xv(gidx(imn)),yv(gidx(imn)),av,gidx(imn),gseq(imn));rmax=make_row(xv(gidx(imx)),yv(gidx(imx)),av,gidx(imx),gseq(imx));
              if(bindex>=0&&bi!=bindex),[xout,yout,aout,seqout]=flush_rows(xout,yout,aout,seqout,bmin,bmax);bmin=[];bmax=[];endif
              bindex=bi;if(isempty(bmin)||rmin.y<bmin.y),bmin=rmin;endif;if(isempty(bmax)||rmax.y>bmax.y),bmax=rmax;endif
            endfor
          endif
        endif
      endif
      processed=max(0,min(planned_rows,ch.offset+ch.nrows-st.range_start));
      gxtxt_progress_update(min(processed,total),total,stage,sprintf('Loading %s',yid));if(ch.eof),break;endif
    endwhile
    if(strcmp(effective,'minmax')&&bindex>=0),[xout,yout,aout,seqout]=flush_rows(xout,yout,aout,seqout,bmin,bmax);endif
    if(strcmp(effective,'minmax')),[xout,yout,aout,seqout]=preserve_boundaries(xout,yout,aout,seqout,first_valid,last_valid);endif
    if(strcmp(effective,'stride')&&!isempty(last_valid)&&isempty(find(seqout==last_valid.seq,1))),[xout,yout,aout,seqout]=append_row(xout,yout,aout,seqout,last_valid);endif
    try diag=gxtxt_table_stream_diagnostics(st);catch;diag=struct();end_try_catch
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(valid_rows<1&&!(plan.applied&&planned_rows==0)),error('plot.dataset: no finite rows in the selected X range for Graph Series %s/%s',dataset_id,yid);endif
  meta=cell(1,numel(aux_ids));for j=1:numel(aux_ids),meta{j}=schema_meta(schema,aux_ids{j});endfor
  xm=schema_meta(schema,xid);implicit_x=strcmpi(strtrim(xm.axis_kind),'uniform');
  % Preserve the exact zero-based source row for every displayed point.
  % A graphical point selection cannot safely infer rows from X/Y values:
  % duplicate coordinates, filters and display reduction all break that map.
  S=struct('x',xout(:),'y',yout(:),'source_row_indices',seqout(:),'valid_rows',valid_rows,'dropped_rows',dropped_rows,'filter_dropped_rows',filter_dropped_rows,'window_filtered_rows',window_filtered_rows,'display_rows',numel(xout), ...
    'requested_reduction',requested,'effective_reduction',effective,'aux_ids',{aux_ids},'aux_values',{aout},'aux_meta',{meta}, ...
    'dataset_id',dataset_id,'stream_api_version',3,'storage_provider',provider, ...
    'source_row_count',row_count,'range_applied',plan.applied,'range_start',plan.start,'range_count',planned_rows,'range_mode',st.range_mode, ...
    'implicit_x',implicit_x,'x_payload_numeric',x_payload_numeric,'stream_diagnostics',diag);
endfunction

function B=source_window_bounds(schema,xid,W)
  B=struct('enabled',false,'lo',NaN,'hi',NaN);
  if(!isstruct(W)||!isfield(W,'enabled')||!W.enabled),return;endif
  m=schema_meta(schema,xid);from=field_or(W,'display_unit','');to=strtrim(m.unit);
  lo=field_or(W,'x_min',NaN);hi=field_or(W,'x_max',NaN);
  try
    if(isfinite(lo)),lo=convert_bound(lo,from,to);endif
    if(isfinite(hi)),hi=convert_bound(hi,from,to);endif
  catch
    return;
  end_try_catch
  if(isfinite(lo)||isfinite(hi))
    if(!isfinite(lo)),lo=-Inf;endif
    if(!isfinite(hi)),hi=Inf;endif
    B=struct('enabled',true,'lo',min(lo,hi),'hi',max(lo,hi));
  endif
endfunction

function plan=range_plan(probe,xid,W)
  plan=struct('start',0,'count',-1,'applied',false);
  if(!isstruct(W)||!isfield(W,'enabled')||!W.enabled),return;endif
  m=schema_meta(probe.schema,xid);if(!strcmpi(strtrim(m.axis_kind),'uniform')),return;endif
  origin=str2double(m.axis_origin);step=str2double(m.axis_step);count=str2double(m.axis_count);
  if(!isfinite(origin)||!isfinite(step)||step==0||!isfinite(count)||count<0),return;endif
  count=round(count);if(count==0),plan=struct('start',0,'count',0,'applied',true);return;endif
  xmin=field_or(W,'x_min',NaN);xmax=field_or(W,'x_max',NaN);from=field_or(W,'display_unit','');to=strtrim(m.unit);
  try
    if(isfinite(xmin)),xmin=convert_bound(xmin,from,to);endif
    if(isfinite(xmax)),xmax=convert_bound(xmax,from,to);endif
  catch
    return;
  end_try_catch
  first=origin;last=origin+(count-1)*step;coord_lo=min(first,last);coord_hi=max(first,last);
  if(!isfinite(xmin)),xmin=coord_lo;endif;if(!isfinite(xmax)),xmax=coord_hi;endif
  lo=min(xmin,xmax);hi=max(xmin,xmax);lo=max(lo,coord_lo);hi=min(hi,coord_hi);
  if(hi<lo),plan=struct('start',0,'count',0,'applied',true);return;endif
  a=(lo-origin)/step;b=(hi-origin)/step;scale=max(1,max(abs([a b])));tol=1e-12*scale;
  i0=max(0,ceil(min(a,b)-tol));i1=min(count-1,floor(max(a,b)+tol));
  if(i1<i0),plan=struct('start',0,'count',0,'applied',true);else plan=struct('start',i0,'count',i1-i0+1,'applied',true);endif
endfunction
function v=convert_bound(v,from,to)
  from=strtrim(from);to=strtrim(to);if(isempty(from)||isempty(to)||strcmp(from,to)),return;endif;v=gxtxt_unit_convert(v,from,to);
endfunction
function ids=unique_stable(ids)
  out={};for i=1:numel(ids),q=strtrim(ids{i});if(!isempty(q)&&isempty(find(strcmp(out,q),1))),out{end+1}=q;endif;endfor;ids=out;
endfunction
function av=aux_chunk(ch,ids)
  av=cell(1,numel(ids));
  for j=1:numel(ids)
    av{j}=gxtxt_table_chunk_column(ch,ids{j});
    if(ischar(av{j})),av{j}=cellstr(av{j});endif
  endfor
endfunction
function [x,y,a,seqs]=append_indices(x,y,a,seqs,xv,yv,av,idx,seqv)
  if(isempty(idx)),return;endif;x=[x;xv(idx)(:)];y=[y;yv(idx)(:)];seqs=[seqs;seqv(:)];for j=1:numel(a),a{j}=[a{j};av{j}(idx)(:)];endfor
endfunction
function r=make_row(x,y,av,i,seq),r=struct('x',x,'y',y,'a',{cell(1,numel(av))},'seq',seq);for j=1:numel(av),r.a{j}=av{j}(i);endfor;endfunction
function [x,y,a,seqs]=append_row(x,y,a,seqs,r),x(end+1,1)=r.x;y(end+1,1)=r.y;seqs(end+1,1)=r.seq;for j=1:numel(a),a{j}(end+1,1)=r.a{j};endfor;endfunction
function [x,y,a,seqs]=flush_rows(x,y,a,seqs,r1,r2)
  if(isempty(r1)&&isempty(r2)),return;endif;if(isempty(r1)),[x,y,a,seqs]=append_row(x,y,a,seqs,r2);return;endif;if(isempty(r2)),[x,y,a,seqs]=append_row(x,y,a,seqs,r1);return;endif
  if(r1.seq==r2.seq),[x,y,a,seqs]=append_row(x,y,a,seqs,r1);elseif(r1.seq<r2.seq),[x,y,a,seqs]=append_row(x,y,a,seqs,r1);[x,y,a,seqs]=append_row(x,y,a,seqs,r2);else [x,y,a,seqs]=append_row(x,y,a,seqs,r2);[x,y,a,seqs]=append_row(x,y,a,seqs,r1);endif
endfunction
function [x,y,a,seqs]=preserve_boundaries(x,y,a,seqs,first,last)
  if(!isempty(first)&&isempty(find(seqs==first.seq,1))),x=[first.x;x];y=[first.y;y];seqs=[first.seq;seqs];for j=1:numel(a),a{j}=[first.a{j};a{j}];endfor;endif
  if(!isempty(last)&&isempty(find(seqs==last.seq,1))),[x,y,a,seqs]=append_row(x,y,a,seqs,last);endif
endfunction
function m=schema_meta(schema,id)
  m=struct('name',id,'variable_id',id,'value_kind','number','value_format','','decimal_separator','.','unit','','time_origin','','time_reference','','coordinate_role','','axis_kind','','axis_origin','','axis_step','','axis_count','');
  for j=1:numel(schema),if(strcmp(schema(j).variable_id,id)||strcmp(schema(j).name,id)),m=schema(j);return;endif;endfor
endfunction
function v=field_or(s,name,def),if(isstruct(s)&&isfield(s,name)),v=s.(name);else v=def;endif;endfunction
