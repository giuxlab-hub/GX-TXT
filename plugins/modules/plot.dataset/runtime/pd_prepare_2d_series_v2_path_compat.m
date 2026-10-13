function S=pd_prepare_2d_series_v2_path_compat(path,xid,yid,aux_ids,requested,target,threshold,chunk_rows,stage_tag)
% Stream one Graph Series plus optional PlotSpec-v2 auxiliary variables.
% Reduction always carries auxiliary values from the exact selected source row;
% no interpolation/resampling/alignment is introduced.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<9),stage_tag='series_v2';endif
  if(isempty(aux_ids)),aux_ids={};endif;if(ischar(aux_ids)),aux_ids={aux_ids};endif
  aux_ids=unique_stable(aux_ids);cols=[{xid,yid} aux_ids];
  st=gxtxt_table_stream_open(path,cols,chunk_rows);total=max(1,st.total_bytes);schema=st.schema;valid_rows=0;dropped_rows=0;x_payload_numeric=false;x_payload_seen=false;
  gxtxt_progress_stage(['scan_' stage_tag],sprintf('Scanning %s',yid),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        if(!x_payload_seen),xr=gxtxt_table_chunk_column(ch,xid);x_payload_numeric=isnumeric(xr)||islogical(xr);x_payload_seen=true;endif
        xv=gxtxt_table_chunk_numeric(ch,xid);yv=gxtxt_table_chunk_numeric(ch,yid);av=aux_chunk(ch,aux_ids);
        for i=1:ch.nrows
          if(row_valid(xv(i),yv(i),av,i)),valid_rows+=1;else dropped_rows+=1;endif
        endfor
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,['scan_' stage_tag],sprintf('Scanning %s',yid));if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(valid_rows<1),error('plot.dataset: no finite rows for PlotSpec v2 series %s',yid);endif
  effective=lower(strtrim(requested));if(!any(strcmp(effective,{'auto','none','stride','minmax'}))),effective='auto';endif
  if(strcmp(effective,'auto')),if(valid_rows>threshold),effective='minmax';else effective='none';endif;endif
  stride=max(1,ceil(valid_rows/max(1,target)));bucket=max(1,ceil(valid_rows/max(1,ceil(target/2))));
  st=gxtxt_table_stream_open(path,cols,chunk_rows);xout=[];yout=[];seqout=[];aout=cell(1,numel(aux_ids));for j=1:numel(aout),aout{j}=[];endfor;seen=0;bindex=-1;bmin=[];bmax=[];
  gxtxt_progress_stage(['load_' stage_tag],sprintf('Loading %s (%s reduction)',yid,effective),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        xv=gxtxt_table_chunk_numeric(ch,xid);yv=gxtxt_table_chunk_numeric(ch,yid);av=aux_chunk(ch,aux_ids);
        for i=1:ch.nrows
          if(!row_valid(xv(i),yv(i),av,i)),continue;endif
          seen+=1;row=make_row(xv(i),yv(i),av,i,seen,ch.first_row+i-2);
          if(strcmp(effective,'none'))
            [xout,yout,aout,seqout]=append_row(xout,yout,aout,seqout,row);
          elseif(strcmp(effective,'stride'))
            if(mod(seen-1,stride)==0||seen==valid_rows),[xout,yout,aout,seqout]=append_row(xout,yout,aout,seqout,row);endif
          else
            bi=floor((seen-1)/bucket);
            if(bindex>=0&&bi!=bindex),[xout,yout,aout,seqout]=flush_rows(xout,yout,aout,seqout,bmin,bmax);bmin=[];bmax=[];endif
            bindex=bi;if(isempty(bmin)||row.y<bmin.y),bmin=row;endif;if(isempty(bmax)||row.y>bmax.y),bmax=row;endif
          endif
        endfor
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,['load_' stage_tag],sprintf('Loading %s',yid));if(ch.eof),break;endif
    endwhile
    if(strcmp(effective,'minmax')&&bindex>=0),[xout,yout,aout,seqout]=flush_rows(xout,yout,aout,seqout,bmin,bmax);endif
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  meta=cell(1,numel(aux_ids));for j=1:numel(aux_ids),meta{j}=schema_meta(schema,aux_ids{j});endfor
  % Keep the absolute zero-based CSV row when filters or reduction retain a
  % point; a valid-row counter would misidentify rows after missing values.
  S=struct('x',xout(:),'y',yout(:),'source_row_indices',seqout(:),'valid_rows',valid_rows,'dropped_rows',dropped_rows,'display_rows',numel(xout),'requested_reduction',requested,'effective_reduction',effective,'aux_ids',{aux_ids},'aux_values',{aout},'aux_meta',{meta}, ...
    'dataset_id','','stream_api_version',2,'storage_provider','csv_path_compat','source_row_count',valid_rows+dropped_rows, ...
    'range_applied',false,'range_start',0,'range_count',valid_rows+dropped_rows,'range_mode','full','implicit_x',false,'x_payload_numeric',x_payload_numeric,'stream_diagnostics',struct());
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
function ok=row_valid(x,y,av,i),ok=isfinite(x)&&isfinite(y);if(!ok),return;endif;for j=1:numel(av),if(isnumeric(av{j})&&!isfinite(av{j}(i))),ok=false;return;endif;endfor;endfunction
function r=make_row(x,y,av,i,seq,source_row),r=struct('x',x,'y',y,'a',{cell(1,numel(av))},'seq',seq,'source_row',source_row);for j=1:numel(av),r.a{j}=av{j}(i);endfor;endfunction
function [x,y,a,seq]=append_row(x,y,a,seq,r),x(end+1,1)=r.x;y(end+1,1)=r.y;seq(end+1,1)=r.source_row;for j=1:numel(a),a{j}(end+1,1)=r.a{j};endfor;endfunction
function [x,y,a,seq]=flush_rows(x,y,a,seq,r1,r2)
  if(isempty(r1)&&isempty(r2)),return;endif;if(isempty(r1)),[x,y,a,seq]=append_row(x,y,a,seq,r2);return;endif;if(isempty(r2)),[x,y,a,seq]=append_row(x,y,a,seq,r1);return;endif
  if(r1.seq==r2.seq),[x,y,a,seq]=append_row(x,y,a,seq,r1);elseif(r1.seq<r2.seq),[x,y,a,seq]=append_row(x,y,a,seq,r1);[x,y,a,seq]=append_row(x,y,a,seq,r2);else [x,y,a,seq]=append_row(x,y,a,seq,r2);[x,y,a,seq]=append_row(x,y,a,seq,r1);endif
endfunction
function m=schema_meta(schema,id)
  m=struct('name',id,'variable_id',id,'value_kind','number','value_format','','decimal_separator','.','unit','','time_origin','','time_reference','');
  for j=1:numel(schema),if(strcmp(schema(j).variable_id,id)||strcmp(schema(j).name,id)),m=schema(j);return;endif;endfor
endfunction
