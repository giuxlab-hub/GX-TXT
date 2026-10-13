function S=pd_prepare_2d_series_path_compat(path,xname,yname,requested,target,threshold,chunk_rows,stage_tag)
% Stream and presentation-reduce one Graph-Series X/Y trace.
% There is deliberately no row grouping/family path here. A future family
% member must arrive as one real Graph Series with an explicit CORE-owned row
% selection predicate.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<8),stage_tag='series';endif
  cols={xname,yname};st=gxtxt_table_stream_open(path,cols,chunk_rows);total=max(1,st.total_bytes);
  valid_rows=0;dropped_rows=0;x_payload_numeric=false;x_payload_seen=false;
  gxtxt_progress_stage(['scan_' stage_tag],sprintf('Scanning %s',yname),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        if(!x_payload_seen),xr=gxtxt_table_chunk_column(ch,xname);x_payload_numeric=isnumeric(xr)||islogical(xr);x_payload_seen=true;endif
        xv=gxtxt_table_chunk_numeric(ch,xname);yv=gxtxt_table_chunk_numeric(ch,yname);
        ok=isfinite(xv)&isfinite(yv);valid_rows+=sum(ok);dropped_rows+=sum(!ok);
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,['scan_' stage_tag],sprintf('Scanning %s',yname));if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(valid_rows<1),error('plot.dataset: no finite X/Y rows for Graph Series %s',yname);endif
  effective=lower(strtrim(requested));if(!any(strcmp(effective,{'auto','none','stride','minmax'}))),effective='auto';endif
  if(strcmp(effective,'auto')),if(valid_rows>threshold),effective='minmax';else effective='none';endif;endif
  stride=max(1,ceil(valid_rows/max(1,target)));bucket=max(1,ceil(valid_rows/max(1,ceil(target/2))));
  st=gxtxt_table_stream_open(path,cols,chunk_rows);xout=[];yout=[];seqout=[];seen=0;bindex=-1;bmin=[];bmax=[];
  gxtxt_progress_stage(['load_' stage_tag],sprintf('Loading %s (%s reduction)',yname,effective),'determinate',total);
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_next(st);if(ch.nrows>0)
        xv=gxtxt_table_chunk_numeric(ch,xname);yv=gxtxt_table_chunk_numeric(ch,yname);
        for i=1:ch.nrows
          if(!isfinite(xv(i))||!isfinite(yv(i))),continue;endif
          seen+=1;row=struct('x',xv(i),'y',yv(i),'seq',seen,'source_row',ch.first_row+i-2);
          if(strcmp(effective,'none'))
            [xout,yout,seqout]=append_row(xout,yout,seqout,row);
          elseif(strcmp(effective,'stride'))
            if(mod(seen-1,stride)==0||seen==valid_rows),[xout,yout,seqout]=append_row(xout,yout,seqout,row);endif
          else
            bi=floor((seen-1)/bucket);
            if(bindex>=0&&bi!=bindex),[xout,yout,seqout]=flush_rows(xout,yout,seqout,bmin,bmax);bmin=[];bmax=[];endif
            bindex=bi;if(isempty(bmin)||row.y<bmin.y),bmin=row;endif;if(isempty(bmax)||row.y>bmax.y),bmax=row;endif
          endif
        endfor
      endif
      gxtxt_progress_update(min(ch.bytes_read,total),total,['load_' stage_tag],sprintf('Loading %s',yname));if(ch.eof),break;endif
    endwhile
    if(strcmp(effective,'minmax')&&bindex>=0),[xout,yout,seqout]=flush_rows(xout,yout,seqout,bmin,bmax);endif
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  % Compatibility CSV streams still need exact source-row identity. The
  % reduction sequence counts only valid rows, so it cannot serve as that ID.
  S=struct('x',xout(:),'y',yout(:),'source_row_indices',seqout(:),'valid_rows',valid_rows,'dropped_rows',dropped_rows,'display_rows',numel(xout), ...
    'requested_reduction',requested,'effective_reduction',effective,'aux_ids',{{}},'aux_values',{{}},'aux_meta',{{}}, ...
    'dataset_id','','stream_api_version',2,'storage_provider','csv_path_compat','source_row_count',valid_rows+dropped_rows, ...
    'range_applied',false,'range_start',0,'range_count',valid_rows+dropped_rows,'range_mode','full','implicit_x',false,'x_payload_numeric',x_payload_numeric,'stream_diagnostics',struct());
endfunction

function [x,y,seq]=append_row(x,y,seq,r),x(end+1,1)=r.x;y(end+1,1)=r.y;seq(end+1,1)=r.source_row;endfunction
function [x,y,seq]=flush_rows(x,y,seq,r1,r2)
  if(isempty(r1)&&isempty(r2)),return;endif;if(isempty(r1)),[x,y,seq]=append_row(x,y,seq,r2);return;endif;if(isempty(r2)),[x,y,seq]=append_row(x,y,seq,r1);return;endif
  if(r1.seq==r2.seq),[x,y,seq]=append_row(x,y,seq,r1);elseif(r1.seq<r2.seq),[x,y,seq]=append_row(x,y,seq,r1);[x,y,seq]=append_row(x,y,seq,r2);else [x,y,seq]=append_row(x,y,seq,r2);[x,y,seq]=append_row(x,y,seq,r1);endif
endfunction
