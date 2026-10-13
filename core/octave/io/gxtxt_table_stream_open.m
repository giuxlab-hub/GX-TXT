% SPDX-License-Identifier: GPL-3.0-or-later
% Open a column-selective CSV stream. Call gxtxt_table_stream_close on cleanup.
function S=gxtxt_table_stream_open(path,columns,chunk_rows)
  if(nargin<2||isempty(columns)),columns={};endif;if(ischar(columns)),columns={columns};endif
  if(nargin<3||isempty(chunk_rows)),chunk_rows=5000;endif
  chunk_rows=round(chunk_rows);if(!isfinite(chunk_rows)||chunk_rows<1),error('GXTXT:TableStream','chunk_rows must be >= 1');endif
  fid=fopen(path,'r');if(fid<0),error('GXTXT:TableStream','Cannot open table: %s',path);endif
  try
    header='';while(true),header=fgetl(fid);if(!ischar(header)),error('GXTXT:TableStream','CSV has no header: %s',path);endif;if(!isempty(strtrim(header))),break;endif;endwhile
    [delimiter,schema]=gxtxt_table_stream_schema(path,header);
    names=gxtxt_csv_split_line(header,delimiter);for i=1:numel(names),names{i}=strtrim(names{i});endfor
    if(isempty(names)||any(cellfun(@isempty,names))),error('GXTXT:TableStream','CSV contains an empty header field');endif
    if(isempty(columns)),columns=names;endif
    idx=zeros(1,numel(columns));
    for i=1:numel(columns)
      token=columns{i};
      for j=1:numel(schema)
        if(strcmp(schema(j).variable_id,token)),columns{i}=schema(j).name;break;endif
      endfor
      k=find(strcmp(names,columns{i}),1);
      if(isempty(k)),error('GXTXT:TableStream','Column not found: %s',token);endif
      idx(i)=k;
    endfor
    info=dir(path);total=0;if(!isempty(info)),total=info.bytes;endif
    S=struct('api_version',2,'path',path,'fid',fid,'names',{names},'columns',{columns},'indices',idx,'chunk_rows',chunk_rows,'row_number',0,'eof',false,'total_bytes',total,'bytes_read',ftell(fid),'delimiter',delimiter,'schema',schema);
  catch err
    fclose(fid);rethrow(err);
  end_try_catch
endfunction
