function G=pd_graph_series_defs(cfg,graph)
% Read active Graph Series API v1 runtime descriptors without materializing data.
% Data are streamed later via Table Stream API v3 using Dataset IDs and stable variable IDs.
% SPDX-License-Identifier: GPL-3.0-or-later
  variant='';pg=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));if(strcmp(pg,graph)),variant=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));endif
  n=str2double(gxtxt_ini_get(cfg,'graph_series.count','0'));if(!isfinite(n)||n<0),error('plot.dataset: invalid Graph Series count');endif
  G=struct('dataset_row_count',{},'scientific_dataset_identity',{},'dataset_id',{},'series_id',{},'variant_id',{},'label',{},'order',{},'path',{},'x_variable_id',{},'y_variable_id',{},'family_variable_id',{},'secondary_variable_id',{},'ordering_variable_id',{},'x_name',{},'y_name',{},'axis',{},'x_unit',{},'y_unit',{},'x_semantic_role',{},'y_semantic_role',{},'x_value_kind',{},'y_value_kind',{},'x_value_format',{},'y_value_format',{},'x_decimal_separator',{},'y_decimal_separator',{},'x_time_reference',{},'x_time_origin',{},'y_time_reference',{},'y_time_origin',{},'alignment_mode',{},'manual_offset_seconds',{},'source_row_ordinals',{},'row_filters',{},'style_color',{},'style_line_style',{});
  for i=1:round(n)
    p=sprintf('graph_series.%d.',i);if(!strcmp(gxtxt_ini_get(cfg,[p 'graph_id'],''),graph)),continue;endif
    v=gxtxt_ini_get(cfg,[p 'variant_id'],'');if(!(isempty(v)&&isempty(variant))&&!strcmp(v,variant)),continue;endif
    en=strtrim(gxtxt_ini_get(cfg,[p 'enabled'],'1'));if(any(strcmpi(en,{'0','false','no','off'}))),continue;endif
    if(!any(strcmpi(en,{'1','true','yes','on'}))),error('plot.dataset: invalid Graph Series enabled state');endif
    dataset_id=strtrim(gxtxt_ini_get(cfg,[p 'dataset_id'],''));path=strtrim(gxtxt_ini_get(cfg,[p 'path'],''));xid=strtrim(gxtxt_ini_get(cfg,[p 'x_variable_id'],''));yid=strtrim(gxtxt_ini_get(cfg,[p 'y_variable_id'],''));
    if(isempty(dataset_id)||isempty(xid)||isempty(yid)),error('plot.dataset: incomplete Graph Series dataset/variable identity');endif
    axis=lower(strtrim(gxtxt_ini_get(cfg,[p 'axis'],'left')));if(!any(strcmp(axis,{'left','right'}))),error('plot.dataset: invalid Graph Series axis');endif
    ord=str2double(gxtxt_ini_get(cfg,[p 'order'],sprintf('%d',i)));if(!isfinite(ord)),ord=i;endif
    off=str2double(gxtxt_ini_get(cfg,[p 'manual_offset_seconds'],'0'));if(!isfinite(off)),off=0;endif
    filters=gxtxt_graph_series_filters_from_runtime(cfg,p);
    G(end+1)=struct('dataset_row_count',str2double(gxtxt_ini_get(cfg,[p 'dataset_row_count'],'')),'scientific_dataset_identity',gxtxt_ini_get(cfg,[p 'scientific_dataset_identity'],''),'dataset_id',dataset_id,'series_id',gxtxt_ini_get(cfg,[p 'series_id'],sprintf('s%03d',i)),'variant_id',variant,'label',gxtxt_ini_get(cfg,[p 'label'],''),'order',ord,'path',path,'x_variable_id',xid,'y_variable_id',yid,'family_variable_id',gxtxt_ini_get(cfg,[p 'family_variable_id'],''),'secondary_variable_id',gxtxt_ini_get(cfg,[p 'secondary_variable_id'],''),'ordering_variable_id',gxtxt_ini_get(cfg,[p 'ordering_variable_id'],''),'x_name',gxtxt_ini_get(cfg,[p 'x_name'],xid),'y_name',gxtxt_ini_get(cfg,[p 'y_name'],yid),'axis',axis,'x_unit',gxtxt_ini_get(cfg,[p 'x_unit'],''),'y_unit',gxtxt_ini_get(cfg,[p 'y_unit'],''),'x_semantic_role',gxtxt_ini_get(cfg,[p 'x_semantic_role'],''),'y_semantic_role',gxtxt_ini_get(cfg,[p 'y_semantic_role'],''),'x_value_kind',gxtxt_ini_get(cfg,[p 'x_value_kind'],'number'),'y_value_kind',gxtxt_ini_get(cfg,[p 'y_value_kind'],'number'),'x_value_format',gxtxt_ini_get(cfg,[p 'x_value_format'],''),'y_value_format',gxtxt_ini_get(cfg,[p 'y_value_format'],''),'x_decimal_separator',gxtxt_ini_get(cfg,[p 'x_decimal_separator'],'.'),'y_decimal_separator',gxtxt_ini_get(cfg,[p 'y_decimal_separator'],'.'),'x_time_reference',gxtxt_ini_get(cfg,[p 'x_time_reference'],gxtxt_ini_get(cfg,[p 'time_reference'],'')),'x_time_origin',gxtxt_ini_get(cfg,[p 'x_time_origin'],gxtxt_ini_get(cfg,[p 'time_origin'],'')),'y_time_reference',gxtxt_ini_get(cfg,[p 'y_time_reference'],''),'y_time_origin',gxtxt_ini_get(cfg,[p 'y_time_origin'],''),'alignment_mode',gxtxt_ini_get(cfg,[p 'alignment_mode'],'none'),'manual_offset_seconds',off,'source_row_ordinals',row_ordinals(gxtxt_ini_get(cfg,[p 'source_row_ordinals'],'')),'row_filters',{filters},'style_color',gxtxt_ini_get(cfg,[p 'style_color'],''),'style_line_style',gxtxt_ini_get(cfg,[p 'style_line_style'],'')); %#ok<AGROW>
  endfor
  if(numel(G)>1),[~,ix]=sort([G.order]);G=G(ix);endif
endfunction

function rows=row_ordinals(text)
  rows=[];text=strtrim(text);if(isempty(text)),return;endif
  rows=str2double(strsplit(text));
  if(numel(rows)>200000||any(!isfinite(rows))||any(rows<0)||any(rows!=fix(rows))||any(rows>flintmax)||numel(unique(rows))!=numel(rows))
    error('plot.dataset: invalid exact source-row selection');
  endif
  rows=sort(rows(:));
endfunction
