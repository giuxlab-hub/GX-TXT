% Read a numeric value and numeric/text group label from one Analysis Source.
% SPDX-License-Identifier: GPL-3.0-or-later
function [values,groups,source_rows]=gxtxt_analysis_grouped_numeric_source(cfg,role,value_id,group_id,selection,chunk_rows)
  if(nargin<5||isempty(selection)),selection=struct('enabled',false);endif
  if(nargin<6),chunk_rows=65536;endif
  ids={value_id,group_id};
  if(isfield(selection,'enabled')&&selection.enabled)
    if(isempty(strtrim(selection.x_variable_id))),error('GXTXT:AnalysisSource','Selection requires a stable X variable ID');endif
    if(!any(strcmp(ids,selection.x_variable_id))),ids{end+1}=selection.x_variable_id;endif
    if(strcmp(selection.type,'rectangle'))
      if(isempty(strtrim(selection.y_variable_id))),error('GXTXT:AnalysisSource','rectangle Selection requires stable Y variable ID');endif
      if(!any(strcmp(ids,selection.y_variable_id))),ids{end+1}=selection.y_variable_id;endif
    endif
  endif
  stream=gxtxt_table_stream_open_source(cfg,role,ids,chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  value_blocks={};group_blocks={};row_blocks={};cursor=0;
  unwind_protect
    while(!stream.eof)
      [stream,chunk]=gxtxt_table_stream_next(stream);
      if(chunk.nrows<1),continue;endif
      value=chunk.values{1};group=chunk.values{2};
      if(!(isnumeric(value)||islogical(value))||numel(value)!=chunk.nrows||numel(group)!=chunk.nrows)
        error('GXTXT:AnalysisSource','ANOVA value or group column is not row-aligned');
      endif
      if(isnumeric(group)||islogical(group))
        labels=cell(chunk.nrows,1);
        for j=1:chunk.nrows
          if(isinteger(group)&&strncmp(class(group),'uint',4)),labels{j}=sprintf('%u',group(j));
          elseif(isinteger(group)),labels{j}=sprintf('%d',group(j));
          elseif(isfinite(group(j))),labels{j}=sprintf('%.17g',double(group(j)));else labels{j}='';endif
        endfor
      elseif(iscell(group))
        labels=cell(chunk.nrows,1);
        for j=1:chunk.nrows
          item=group{j};
          if(ischar(item)),labels{j}=strtrim(item);
          elseif(isnumeric(item)&&isscalar(item)&&isfinite(item)),labels{j}=sprintf('%.17g',double(item));
          else labels{j}='';endif
        endfor
      else error('GXTXT:AnalysisSource','ANOVA group column must be numeric or text');endif
      value=double(value(:));rows=(cursor+1:cursor+chunk.nrows)';cursor+=chunk.nrows;
      if(isfield(selection,'enabled')&&selection.enabled)
        xidx=find(strcmp(ids,selection.x_variable_id),1);x=chunk.values{xidx};
        if(!(isnumeric(x)||islogical(x))),error('GXTXT:AnalysisSource','Selection X variable must be numeric');endif
        if(strcmp(selection.type,'rectangle'))
          yidx=find(strcmp(ids,selection.y_variable_id),1);y=chunk.values{yidx};
          if(!(isnumeric(y)||islogical(y))),error('GXTXT:AnalysisSource','Selection Y variable must be numeric');endif
          mask=gxtxt_selection_mask(selection,double(x(:)),double(y(:)));
        else mask=gxtxt_selection_mask(selection,double(x(:)));endif
        mask=logical(mask(:));if(numel(mask)!=chunk.nrows),error('GXTXT:AnalysisSource','Selection mask length differs from chunk');endif
        value=value(mask);labels=labels(mask);rows=rows(mask);
      endif
      if(!isempty(rows)),value_blocks{end+1}=value;group_blocks{end+1}=labels;row_blocks{end+1}=rows;endif
    endwhile
  unwind_protect_cleanup
    stream=gxtxt_table_stream_close(stream);
  end_unwind_protect
  if(isempty(value_blocks)),values=zeros(0,1);groups=cell(0,1);source_rows=zeros(0,1);
  else values=vertcat(value_blocks{:});groups=vertcat(group_blocks{:});source_rows=vertcat(row_blocks{:});endif
endfunction
