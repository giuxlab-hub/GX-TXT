% SPDX-License-Identifier: GPL-3.0-or-later
% Graph Series API v1: load each dataset/series independently, without
% interpolation, resampling or implicit temporal alignment.
function series = gxtxt_graph_series_load(runtime,graph_id,chunk_rows,variant_id)
  if(nargin<3||isempty(chunk_rows)),chunk_rows=5000;endif
  if(nargin<4),variant_id='';endif
  n=str2double(gxtxt_ini_get(runtime,'graph_series.count','0'));
  if(!isfinite(n)||n<0),error('GXTXT:GraphSeries','invalid graph series count');endif
  series=struct('dataset_id',{},'series_id',{},'variant_id',{},'label',{},'enabled',{},'order',{},'x_name',{},'y_name',{},'axis',{},'x_variable_id',{},'y_variable_id',{},'x_unit',{},'y_unit',{},'x_semantic_role',{},'y_semantic_role',{},'x_value_kind',{},'y_value_kind',{},'x_value_format',{},'y_value_format',{},'x_decimal_separator',{},'y_decimal_separator',{},'x',{},'y',{},'row_filters',{},'time_reference',{},'time_origin',{},'x_time_reference',{},'x_time_origin',{},'y_time_reference',{},'y_time_origin',{},'alignment_mode',{},'manual_offset_seconds',{});
  for i=1:round(n)
    p=sprintf('graph_series.%d.',i);
    if(!strcmp(gxtxt_ini_get(runtime,[p 'graph_id'],''),graph_id)),continue;endif
    v=gxtxt_ini_get(runtime,[p 'variant_id'],'');
    if(!(isempty(v)&&isempty(variant_id))&&!strcmp(v,variant_id)),continue;endif
    enabled=strtrim(gxtxt_ini_get(runtime,[p 'enabled'],'1'));
    if(any(strcmpi(enabled,{'0','false','no','off'}))),continue;endif
    if(!any(strcmpi(enabled,{'1','true','yes','on'}))),error('GXTXT:GraphSeries','invalid enabled state');endif
    path=gxtxt_ini_get(runtime,[p 'path'],'');
    xid=gxtxt_ini_get(runtime,[p 'x_variable_id'],'');
    yid=gxtxt_ini_get(runtime,[p 'y_variable_id'],'');
    if(isempty(path)||isempty(xid)||isempty(yid)),error('GXTXT:GraphSeries','incomplete graph series');endif
    filters=gxtxt_graph_series_filters_from_runtime(runtime,p);
    ids={xid,yid};for j=1:numel(filters),id=filters{j}.filter_variable_id;if(!any(strcmp(ids,id))),ids{end+1}=id;endif;endfor
    S=gxtxt_table_stream_open(path,ids,chunk_rows);
    x=[];y=[];
    unwind_protect
      while(true)
        [S,C]=gxtxt_table_stream_next(S);
        if(C.nrows>0)
          keep=gxtxt_graph_series_filter_mask(C,filters);
          xv=gxtxt_table_chunk_numeric(C,xid);yv=gxtxt_table_chunk_numeric(C,yid);
          x=[x;xv(keep)(:)];
          y=[y;yv(keep)(:)];
        endif
        if(C.eof),break;endif
      endwhile
    unwind_protect_cleanup
      S=gxtxt_table_stream_close(S);
    end_unwind_protect
    axis=gxtxt_ini_get(runtime,[p 'axis'],'left');
    if(!any(strcmp(axis,{'left','right'}))),error('GXTXT:GraphSeries','invalid axis');endif
    order=str2double(gxtxt_ini_get(runtime,[p 'order'],'0'));
    if(!isfinite(order)),order=0;endif
    x_time_reference=gxtxt_ini_get(runtime,[p 'x_time_reference'],gxtxt_ini_get(runtime,[p 'time_reference'],'elapsed'));
    x_time_origin=gxtxt_ini_get(runtime,[p 'x_time_origin'],gxtxt_ini_get(runtime,[p 'time_origin'],''));
    series(end+1)=struct('dataset_id',gxtxt_ini_get(runtime,[p 'dataset_id'],''),'series_id',gxtxt_ini_get(runtime,[p 'series_id'],''),'variant_id',variant_id,'label',gxtxt_ini_get(runtime,[p 'label'],''),'enabled',true,'order',order,'x_name',gxtxt_ini_get(runtime,[p 'x_name'],''),'y_name',gxtxt_ini_get(runtime,[p 'y_name'],''),'axis',axis, ...
      'x_variable_id',xid,'y_variable_id',yid,'x_unit',gxtxt_ini_get(runtime,[p 'x_unit'],''),'y_unit',gxtxt_ini_get(runtime,[p 'y_unit'],''), ...
      'x_semantic_role',gxtxt_ini_get(runtime,[p 'x_semantic_role'],''),'y_semantic_role',gxtxt_ini_get(runtime,[p 'y_semantic_role'],''), ...
      'x_value_kind',gxtxt_ini_get(runtime,[p 'x_value_kind'],'number'),'y_value_kind',gxtxt_ini_get(runtime,[p 'y_value_kind'],'number'), ...
      'x_value_format',gxtxt_ini_get(runtime,[p 'x_value_format'],''),'y_value_format',gxtxt_ini_get(runtime,[p 'y_value_format'],''), ...
      'x_decimal_separator',gxtxt_ini_get(runtime,[p 'x_decimal_separator'],'.'),'y_decimal_separator',gxtxt_ini_get(runtime,[p 'y_decimal_separator'],'.'), ...
      'x',x,'y',y,'row_filters',{filters},'time_reference',x_time_reference,'time_origin',x_time_origin,'x_time_reference',x_time_reference,'x_time_origin',x_time_origin, ...
      'y_time_reference',gxtxt_ini_get(runtime,[p 'y_time_reference'],'elapsed'),'y_time_origin',gxtxt_ini_get(runtime,[p 'y_time_origin'],''), ...
      'alignment_mode',gxtxt_ini_get(runtime,[p 'alignment_mode'],'none'),'manual_offset_seconds',str2double(gxtxt_ini_get(runtime,[p 'manual_offset_seconds'],'0')));
  endfor
endfunction
