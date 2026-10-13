function prepared=pd_prepare_2d_filtered_batch(session,G,aux_sets,requested,target,threshold,chunk_rows)
% Prepare compatible filtered Graph Series in one bounded Dataset stream.
% Each series keeps the same independent predicate and reducer semantics as
% pd_prepare_2d_stream, including exact zero-based source-row identities.
% SPDX-License-Identifier: GPL-3.0-or-later
  n=numel(G);if(n<2),error('plot.dataset: filtered batch requires multiple series');endif
  dataset_id=G(1).dataset_id;ids={};
  for k=1:n
    if(!strcmp(G(k).dataset_id,dataset_id)),error('plot.dataset: mixed-Dataset filtered batch');endif
    filter_ids=cell(1,numel(G(k).row_filters));
    for j=1:numel(filter_ids),filter_ids{j}=G(k).row_filters{j}.filter_variable_id;endfor
    ids=unique([ids {G(k).x_variable_id,G(k).y_variable_id} aux_sets{k} filter_ids],'stable');
  endfor
  st=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct());
  row_count=st.row_count;planned=st.range_count;if(planned<0),planned=max(0,row_count-st.range_start);endif
  provider=st.storage_provider;schema=st.schema;range_mode=st.range_mode;
  effective=cell(1,n);stride=ones(1,n);bucket_rows=ones(1,n);
  state=cell(1,n);
  target=max(2,round(target));bucket_count=max(1,floor(max(2,target-2)/2));
  for k=1:n
    mode=lower(strtrim(requested{k}));if(!any(strcmp(mode,{'auto','none','stride','minmax'}))),mode='auto';endif
    if(strcmp(mode,'auto')),if(planned>threshold),mode='minmax';else mode='none';endif;endif
    effective{k}=mode;stride(k)=max(1,ceil(max(1,planned)/target));bucket_rows(k)=max(1,ceil(max(1,planned)/bucket_count));
    a=cell(1,numel(aux_sets{k}));for j=1:numel(a),a{j}=[];endfor
    state{k}=struct('x',[],'y',[],'a',{a},'seq',[],'valid',0,'dropped',0,'filtered',0,'seen',0, ...
      'bindex',-1,'bmin',[],'bmax',[],'first',[],'last',[],'x_numeric',false,'x_seen',false);
  endfor
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      if(ch.nrows>0)
        for k=1:n
          S=state{k};xid=G(k).x_variable_id;yid=G(k).y_variable_id;
          if(!S.x_seen),raw=gxtxt_table_chunk_column(ch,xid);S.x_numeric=isnumeric(raw)||islogical(raw);S.x_seen=true;endif
          xv=gxtxt_table_chunk_numeric(ch,xid);yv=gxtxt_table_chunk_numeric(ch,yid);xv=xv(:);yv=yv(:);
          av=cell(1,numel(aux_sets{k}));for j=1:numel(av)
            av{j}=gxtxt_table_chunk_column(ch,aux_sets{k}{j});
            if(ischar(av{j})),av{j}=cellstr(av{j});endif
            av{j}=av{j}(:);
          endfor
          finite_ok=isfinite(xv)&isfinite(yv);
          for j=1:numel(av),if(isnumeric(av{j})),finite_ok&=isfinite(av{j});endif;endfor
          filter_ok=gxtxt_graph_series_filter_mask(ch,G(k).row_filters);idx=find(finite_ok&filter_ok);nv=numel(idx);
          S.valid+=nv;S.dropped+=ch.nrows-sum(finite_ok);S.filtered+=sum(finite_ok)-sum(finite_ok&filter_ok);
          if(nv>0)
            seqv=ch.offset+idx-1;
            if(isempty(S.first)),S.first=row(xv,yv,av,idx(1),seqv(1));endif
            S.last=row(xv,yv,av,idx(end),seqv(end));
            switch(effective{k})
              case 'none'
                S=append_indices(S,xv,yv,av,idx,seqv);
              case 'stride'
                ord=(S.seen:(S.seen+nv-1))';keep=mod(ord,stride(k))==0;
                S=append_indices(S,xv,yv,av,idx(keep),seqv(keep));S.seen+=nv;
              case 'minmax'
                bins=floor((seqv-st.range_start)/bucket_rows(k));cuts=[1;find(diff(bins)!=0)+1;nv+1];
                for q=1:numel(cuts)-1
                  a=cuts(q);b=cuts(q+1)-1;bi=bins(a);group_idx=idx(a:b);group_seq=seqv(a:b);
                  [~,imin]=min(yv(group_idx));[~,imax]=max(yv(group_idx));
                  rmin=row(xv,yv,av,group_idx(imin),group_seq(imin));
                  rmax=row(xv,yv,av,group_idx(imax),group_seq(imax));
                  if(S.bindex>=0&&bi!=S.bindex),S=flush_pair(S,S.bmin,S.bmax);S.bmin=[];S.bmax=[];endif
                  S.bindex=bi;
                  if(isempty(S.bmin)||rmin.y<S.bmin.y),S.bmin=rmin;endif
                  if(isempty(S.bmax)||rmax.y>S.bmax.y),S.bmax=rmax;endif
                endfor
            endswitch
          endif
          state{k}=S;
        endfor
      endif
      if(ch.eof),break;endif
    endwhile
    diagnostics=gxtxt_table_stream_diagnostics(st);
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  prepared=cell(1,n);
  for k=1:n
    S=state{k};
    if(strcmp(effective{k},'minmax')&&S.bindex>=0),S=flush_pair(S,S.bmin,S.bmax);endif
    if(strcmp(effective{k},'minmax'))
      if(!isempty(S.first)&&isempty(find(S.seq==S.first.seq,1))),S=prepend_row(S,S.first);endif
      if(!isempty(S.last)&&isempty(find(S.seq==S.last.seq,1))),S=append_row(S,S.last);endif
    elseif(strcmp(effective{k},'stride')&&!isempty(S.last)&&isempty(find(S.seq==S.last.seq,1)))
      S=append_row(S,S.last);
    endif
    if(S.valid<1),error('plot.dataset: no finite rows in the selected X range for Graph Series %s/%s',dataset_id,G(k).y_variable_id);endif
    xm=schema_meta(schema,G(k).x_variable_id);aux_meta=cell(1,numel(aux_sets{k}));
    for j=1:numel(aux_meta),aux_meta{j}=schema_meta(schema,aux_sets{k}{j});endfor
    diagnostic=diagnostics;diagnostic.batch_series_count=n;diagnostic.batch_dataset_passes=1;
    prepared{k}=struct('x',S.x(:),'y',S.y(:),'source_row_indices',S.seq(:), ...
      'valid_rows',S.valid,'dropped_rows',S.dropped,'filter_dropped_rows',S.filtered,'window_filtered_rows',0, ...
      'display_rows',numel(S.x),'requested_reduction',requested{k},'effective_reduction',effective{k}, ...
      'aux_ids',{aux_sets{k}},'aux_values',{S.a},'aux_meta',{aux_meta},'dataset_id',dataset_id, ...
      'stream_api_version',3,'storage_provider',provider,'source_row_count',row_count, ...
      'range_applied',false,'range_start',0,'range_count',planned,'range_mode',range_mode, ...
      'implicit_x',strcmpi(strtrim(xm.axis_kind),'uniform'),'x_payload_numeric',S.x_numeric, ...
      'stream_diagnostics',diagnostic);
  endfor
endfunction
function r=row(x,y,a,i,seq)
  r=struct('x',x(i),'y',y(i),'a',{cell(1,numel(a))},'seq',seq);
  for j=1:numel(a),r.a{j}=a{j}(i);endfor
endfunction
function S=append_indices(S,x,y,a,idx,seq)
  if(isempty(idx)),return;endif
  S.x=[S.x;x(idx)(:)];S.y=[S.y;y(idx)(:)];S.seq=[S.seq;seq(:)];
  for j=1:numel(a),S.a{j}=[S.a{j};a{j}(idx)(:)];endfor
endfunction
function S=append_row(S,r)
  S.x(end+1,1)=r.x;S.y(end+1,1)=r.y;S.seq(end+1,1)=r.seq;
  for j=1:numel(S.a),S.a{j}(end+1,1)=r.a{j};endfor
endfunction
function S=prepend_row(S,r)
  S.x=[r.x;S.x];S.y=[r.y;S.y];S.seq=[r.seq;S.seq];
  for j=1:numel(S.a),S.a{j}=[r.a{j};S.a{j}];endfor
endfunction
function S=flush_pair(S,a,b)
  if(isempty(a)),return;endif
  if(a.seq==b.seq),S=append_row(S,a);
  elseif(a.seq<b.seq),S=append_row(S,a);S=append_row(S,b);
  else S=append_row(S,b);S=append_row(S,a);endif
endfunction
function m=schema_meta(schema,id)
  m=struct('name',id,'variable_id',id,'value_kind','number','value_format','','decimal_separator','.','unit','','time_origin','','time_reference','','coordinate_role','','axis_kind','','axis_origin','','axis_step','','axis_count','');
  for j=1:numel(schema),if(strcmp(schema(j).variable_id,id)||strcmp(schema(j).name,id)),m=schema(j);return;endif;endfor
endfunction
