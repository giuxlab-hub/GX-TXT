% Bind stable Dataset variable IDs from one Analysis Source through Table Stream.
% SPDX-License-Identifier: GPL-3.0-or-later
function [values,source_rows]=gxtxt_analysis_numeric_source_matrix(cfg,role,variable_ids,selection,chunk_rows)
  if(nargin<4||isempty(selection)),selection=struct('enabled',false);endif
  if(nargin<5),chunk_rows=65536;endif
  if(!isnumeric(chunk_rows)||!isscalar(chunk_rows)||!isfinite(chunk_rows)||chunk_rows<1||chunk_rows!=fix(chunk_rows))
    error('GXTXT:AnalysisSource','chunk_rows must be a positive integer');
  endif
  if(!iscell(variable_ids)||isempty(variable_ids))
    error('GXTXT:AnalysisSource','one or more stable variable IDs are required');
  endif
  for j=1:numel(variable_ids)
    if(!ischar(variable_ids{j})||isempty(strtrim(variable_ids{j})))
      error('GXTXT:AnalysisSource','stable variable ID is missing');
    endif
  endfor
  ids=variable_ids(:)';
  if(isfield(selection,'enabled')&&selection.enabled)
    if(!isfield(selection,'x_variable_id')||isempty(strtrim(selection.x_variable_id)))
      error('GXTXT:AnalysisSource','Selection requires a stable X variable ID');
    endif
    if(!any(strcmp(ids,selection.x_variable_id))),ids{end+1}=selection.x_variable_id;endif
    if(strcmp(selection.type,'rectangle'))
      if(!isfield(selection,'y_variable_id')||isempty(strtrim(selection.y_variable_id)))
        error('GXTXT:AnalysisSource','Rectangle Selection requires a stable Y variable ID');
      endif
      if(!any(strcmp(ids,selection.y_variable_id))),ids{end+1}=selection.y_variable_id;endif
    endif
  endif
  stream=gxtxt_table_stream_open_source(cfg,role,ids,chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  blocks={};row_blocks={};cursor=0;
  unwind_protect
    while(!stream.eof)
      [stream,chunk]=gxtxt_table_stream_next(stream);
      if(chunk.nrows<1),continue;endif
      block=zeros(chunk.nrows,numel(ids));
      for j=1:numel(ids)
        column=chunk.values{j};
        if(!(isnumeric(column)||islogical(column))||numel(column)!=chunk.nrows)
          error('GXTXT:AnalysisSource','Dataset variable %s is not a row-aligned numeric variable',ids{j});
        endif
        block(:,j)=double(column(:));
      endfor
      rows=(cursor+1:cursor+chunk.nrows)';cursor+=chunk.nrows;
      if(isfield(selection,'enabled')&&selection.enabled)
        xidx=find(strcmp(ids,selection.x_variable_id),1);
        if(strcmp(selection.type,'rectangle'))
          yidx=find(strcmp(ids,selection.y_variable_id),1);
          mask=gxtxt_selection_mask(selection,block(:,xidx),block(:,yidx));
        else
          mask=gxtxt_selection_mask(selection,block(:,xidx));
        endif
        mask=logical(mask(:));
        if(numel(mask)!=chunk.nrows),error('GXTXT:AnalysisSource','Selection mask length differs from Table Stream chunk');endif
        block=block(mask,:);rows=rows(mask);
      endif
      if(!isempty(rows)),blocks{end+1}=block(:,1:numel(variable_ids));row_blocks{end+1}=rows;endif
    endwhile
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
  if(isempty(blocks))
    values=zeros(0,numel(variable_ids));source_rows=zeros(0,1);
  else
    values=vertcat(blocks{:});source_rows=vertcat(row_blocks{:});
  endif
endfunction
