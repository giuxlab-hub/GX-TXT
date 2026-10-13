function prepared=pd_prepare_2d_family_grouped(session,G,requested,target,threshold,chunk_rows)
% Prepare exact-member Graph Series in two bounded Dataset passes.
% SPDX-License-Identifier: GPL-3.0-or-later
  n=numel(G);dataset_id=G(1).dataset_id;xid=G(1).x_variable_id;yid=G(1).y_variable_id;
  group_id=G(1).row_filters{1}.filter_variable_id;
  text_group=strcmp(G(1).row_filters{1}.dtype,'string');
  members=cell(1,n);
  for g=1:n,members{g}=G(g).row_filters{1}.value;endfor
  if(!text_group),members=cellfun(@str2double,members);endif
  ids={xid,yid,group_id};counts=zeros(1,n);invalid=0;total_rows=0;
  st=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct());
  row_count=st.row_count;provider=st.storage_provider;schema=st.schema;range_mode=st.range_mode;
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      total_rows+=ch.nrows;
      if(ch.nrows>0)
        x=gxtxt_table_chunk_numeric(ch,xid);y=gxtxt_table_chunk_numeric(ch,yid);
        valid=isfinite(x(:))&isfinite(y(:));invalid+=sum(!valid);
        group=member_column(ch,group_id,text_group);
        [~,loc]=ismember(group,members);
        selected=loc(valid&loc>0);
        if(!isempty(selected)),counts+=accumarray(selected(:),1,[n 1])';endif
      endif
      if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(row_count<0),row_count=total_rows;endif
  requested=lower(strtrim(requested));target=max(2,round(target));
  effective=cell(1,n);stride=ones(1,n);bucket_rows=ones(1,n);
  bucket_count=max(1,floor(max(2,target-2)/2));
  for g=1:n
    effective{g}=requested;
    if(strcmp(requested,'auto'))
      if(counts(g)>threshold),effective{g}='minmax';else effective{g}='none';endif
    endif
    stride(g)=max(1,ceil(max(1,counts(g))/target));
    bucket_rows(g)=max(1,ceil(max(1,counts(g))/bucket_count));
  endfor
  xo=cell(1,n);yo=cell(1,n);seq=cell(1,n);seen=zeros(1,n);
  first=cell(1,n);last=cell(1,n);lo=cell(1,n);hi=cell(1,n);bucket=-ones(1,n);
  st=gxtxt_table_stream_open_dataset(session,dataset_id,ids,chunk_rows,struct());
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);
      if(ch.nrows>0)
        x=gxtxt_table_chunk_numeric(ch,xid);y=gxtxt_table_chunk_numeric(ch,yid);
        x=x(:);y=y(:);valid=isfinite(x)&isfinite(y);
        group=member_column(ch,group_id,text_group);
        [~,loc]=ismember(group,members);
        idx=find(valid&loc>0);
        if(!isempty(idx))
          [sorted,order]=sort(loc(idx));idx=idx(order);
          ends=[find(diff(sorted)!=0);numel(sorted)];begin=1;
          for block=1:numel(ends)
            g=sorted(begin);part=idx(begin:ends(block));begin=ends(block)+1;
            for q=1:numel(part)
              j=part(q);r=struct('x',x(j),'y',y(j),'seq',ch.offset+j-1);
              if(isempty(first{g})),first{g}=r;endif;last{g}=r;
              ordinal=seen(g);seen(g)+=1;
              switch(effective{g})
                case 'none',[xo{g},yo{g},seq{g}]=append_point(xo{g},yo{g},seq{g},r);
                case 'stride'
                  if(mod(ordinal,stride(g))==0),[xo{g},yo{g},seq{g}]=append_point(xo{g},yo{g},seq{g},r);endif
                case 'minmax'
                  b=floor(ordinal/bucket_rows(g));
                  if(bucket(g)>=0&&b!=bucket(g))
                    [xo{g},yo{g},seq{g}]=flush_pair(xo{g},yo{g},seq{g},lo{g},hi{g});lo{g}=[];hi{g}=[];
                  endif
                  bucket(g)=b;
                  if(isempty(lo{g})||r.y<lo{g}.y),lo{g}=r;endif
                  if(isempty(hi{g})||r.y>hi{g}.y),hi{g}=r;endif
                otherwise,error('plot.dataset: unsupported family reduction %s',effective{g});
              endswitch
            endfor
          endfor
        endif
      endif
      if(ch.eof),break;endif
    endwhile
    diagnostics=gxtxt_table_stream_diagnostics(st);
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  prepared=cell(1,n);implicit_x=false;
  for k=1:numel(schema),if(strcmp(schema(k).variable_id,xid)),implicit_x=strcmpi(schema(k).axis_kind,'uniform');break;endif;endfor
  for g=1:n
    if(seen(g)!=counts(g)),error('plot.dataset: family Dataset changed during grouped preparation');endif
    if(strcmp(effective{g},'minmax')&&bucket(g)>=0)
      [xo{g},yo{g},seq{g}]=flush_pair(xo{g},yo{g},seq{g},lo{g},hi{g});
    endif
    if(strcmp(effective{g},'minmax')&&!isempty(first{g})&&isempty(find(seq{g}==first{g}.seq,1)))
      xo{g}=[first{g}.x;xo{g}];yo{g}=[first{g}.y;yo{g}];seq{g}=[first{g}.seq;seq{g}];
    endif
    if(!isempty(last{g})&&isempty(find(seq{g}==last{g}.seq,1)))
      [xo{g},yo{g},seq{g}]=append_point(xo{g},yo{g},seq{g},last{g});
    endif
    if(counts(g)==0),error('plot.dataset: family member %s has no finite X/Y rows',G(g).row_filters{1}.value);endif
    % Group filtering and display reduction preserve the same source-row
    % identity needed by CORE graphical point selection.
    prepared{g}=struct('x',xo{g}(:),'y',yo{g}(:),'source_row_indices',seq{g}(:),'valid_rows',counts(g), ...
      'dropped_rows',invalid,'filter_dropped_rows',row_count-invalid-counts(g), ...
      'window_filtered_rows',0,'display_rows',numel(xo{g}), ...
      'requested_reduction',requested,'effective_reduction',effective{g}, ...
      'aux_ids',{{}},'aux_values',{{}},'aux_meta',{{}}, ...
      'dataset_id',dataset_id,'stream_api_version',3,'storage_provider',provider, ...
      'source_row_count',row_count,'range_applied',false,'range_start',0, ...
      'range_count',row_count,'range_mode',range_mode,'implicit_x',implicit_x, ...
      'x_payload_numeric',true,'stream_diagnostics',diagnostics);
  endfor
endfunction

function values=member_column(ch,id,text_group)
  if(text_group),values=gxtxt_table_chunk_column(ch,id);if(!iscell(values)),values=cellstr(values);endif;
  else values=double(gxtxt_table_chunk_numeric(ch,id));values=values(:);endif
endfunction
function [x,y,s]=append_point(x,y,s,r)
  x(end+1,1)=r.x;y(end+1,1)=r.y;s(end+1,1)=r.seq;
endfunction
function [x,y,s]=flush_pair(x,y,s,a,b)
  if(isempty(a)),return;endif
  if(a.seq==b.seq),[x,y,s]=append_point(x,y,s,a);
  elseif(a.seq<b.seq),[x,y,s]=append_point(x,y,s,a);[x,y,s]=append_point(x,y,s,b);
  else [x,y,s]=append_point(x,y,s,b);[x,y,s]=append_point(x,y,s,a);endif
endfunction
