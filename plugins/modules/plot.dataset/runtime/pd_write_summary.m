function pd_write_summary(path,info,opts,M,enabled,meta)
% Rewrite derived diagnostics from the same current runtime/cache used to render.
% SPDX-License-Identifier: GPL-3.0-or-later
  fid=fopen(path,'w');if(fid<0),error('plot.dataset: cannot write %s',path);endif;unwind_protect
    fprintf(fid,'GX-TXT Scientific Dataset Plot\nModule: plot.dataset 3.12.0\nPrimary dataset: %s\nPrimary source: %s\n',info.dataset_id,info.source_path);
    fprintf(fid,'3D bindings: X=%s Y=%s Z=%s Family=%s Color=%s\n',emptyv(info.x),emptyv(info.y),emptyv(info.z),emptyv(info.family),emptyv(info.color));
    fprintf(fid,'Enabled graphs: %s\nReduction: %s; target_points=%d; auto_threshold=%d; chunk_rows=%d\n',joincell(enabled,';'),opts.reduction_mode,opts.target_points,opts.auto_reduce_threshold,opts.chunk_rows);
    for graph={'plot.dataset.xy','plot.dataset.xy_region'},g=graph{1};fld=cache_field(g);if(isfield(M,fld)),P=M.(fld);fprintf(fid,'%s: mode=%s series=%d\n',g,P.mode,numel(P.series));for k=1:numel(P.series),d=P.series(k).data;fprintf(fid,'  %s dataset=%s axis=%s provider=%s implicit_x=%d source_rows=%d range=%d:%d display=%d valid=%d dropped=%d reduction=%s\n',P.series(k).name,P.series(k).dataset_id,P.series(k).axis,d.storage_provider,d.implicit_x,d.source_row_count,d.range_start,d.range_count,d.display_rows,d.valid_rows,d.dropped_rows,d.effective_reduction);endfor;if(isfield(P,'region_selection')&&P.region_selection.enabled),R=P.region_selection;fprintf(fid,'  X selection: %.17g .. %.17g [%s]\n',R.x_min,R.x_max,R.display_unit);for k=1:numel(R.series),Q=R.series(k);fprintf(fid,'    %s dataset=%s x_variable_id=%s selected_display=%d/%d\n',Q.series_id,Q.dataset_id,Q.x_variable_id,Q.selected_display_points,Q.display_points);endfor;endif;endif;endfor
    if(M.prepared_3d),s=M.plot3d.stats;fprintf(fid,'3D: type=%s mode=%s valid=%d display=%d groups=%d reduction=%s\n',M.plot3d.plot_type,M.plot3d.mode,s.valid_rows,s.display_rows,s.group_count,s.effective_reduction);endif
  unwind_protect_cleanup fclose(fid);end_unwind_protect
endfunction
function fld=cache_field(graph),if(strcmp(graph,'plot.dataset.xy')),fld='plot2d_xy';else fld='plot2d_xy_region';endif;endfunction
function s=emptyv(s),if(isempty(s)),s='(none)';endif;endfunction
function s=joincell(c,sep),if(isempty(c)),s='';return;endif;s=c{1};for i=2:numel(c),s=[s sep c{i}];endfor;endfunction
