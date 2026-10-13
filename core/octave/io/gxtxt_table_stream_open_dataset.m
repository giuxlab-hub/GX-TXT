% SPDX-License-Identifier: GPL-3.0-or-later
% Open a registered table-shaped Dataset ID through Table Stream API v3.
function S=gxtxt_table_stream_open_dataset(session,dataset_id,variable_ids,chunk_rows,options)
  if(nargin<3||isempty(variable_ids)),variable_ids={};endif
  if(ischar(variable_ids)),variable_ids={variable_ids};endif
  if(nargin<4||isempty(chunk_rows)),chunk_rows=5000;endif
  if(nargin<5||isempty(options)),options=struct();endif
  start=field_or(options,'start',0);count=field_or(options,'count',-1);require_direct=field_or(options,'require_direct',false);numeric_transport=field_or(options,'numeric_transport','auto');
  here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(here)));
  bridge=fullfile(root,'core','tcl','table_stream_v3_bridge.tcl');
  if(exist(bridge,'file')!=2),error('GXTXT:TableStream','Table Stream v3 bridge is missing');endif
  args={bridge,char(session),char(dataset_id),strjoin(variable_ids,';'),num2str(chunk_rows),num2str(start),num2str(count),num2str(logical(require_direct)),char(numeric_transport)};
  in=-1;out=-1;pid=-1;
  try
    [in,out,pid]=popen2('tclsh',args);
    if(pid<0),error('GXTXT:TableStream','Cannot start Table Stream v3 bridge');endif
    parts=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(out,pid));
    bridge_error(parts);
    if(numel(parts)!=10||!strcmp(parts{1},'READY')),error('GXTXT:TableStream','Invalid Table Stream v3 READY response');endif
    dataset_id=gxtxt_table_stream_v3_decode(parts{3});provider=gxtxt_table_stream_v3_decode(parts{4});row_dimension=gxtxt_table_stream_v3_decode(parts{5});
    row_count=str2double(parts{6});range_start=str2double(parts{7});range_count=str2double(parts{8});chunk_rows=str2double(parts{9});range_mode=gxtxt_table_stream_v3_decode(parts{10});
    fputs(in,"META\n");fflush(in);
    head=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(out,pid));bridge_error(head);
    if(numel(head)!=3||!strcmp(head{1},'META')),error('GXTXT:TableStream','Invalid Table Stream v3 metadata response');endif
    nfields=str2double(head{2});nvars=str2double(head{3});metadata=struct();capabilities=struct();
    for i=1:nfields
      item=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(out,pid));
      if(numel(item)!=3||!strcmp(item{1},'ITEM')),error('GXTXT:TableStream','Invalid Table Stream v3 metadata field');endif
      key=gxtxt_table_stream_v3_decode(item{2});value=gxtxt_table_stream_v3_decode(item{3});
      if(strncmp(key,'capability.',11)),capabilities.(safe_field(key(12:end)))=logical(str2double(value));
      else metadata.(safe_field(key))=typed_field(key,value);endif
    endfor
    empty={'variable_id','','name','','canonical','','display_label','','dtype','','unit','','semantic_role','','value_kind','','value_format','','decimal_separator','','time_origin','','time_reference','','dimension_ids','','coordinate_role','','axis_kind','','axis_origin','','axis_step','','axis_count',''};
    schema=repmat(struct(empty{:}),1,0);
    for i=1:nvars
      item=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(out,pid));
      if(numel(item)!=18||!strcmp(item{1},'VAR')),error('GXTXT:TableStream','Invalid Table Stream v3 variable metadata');endif
      values=cellfun(@gxtxt_table_stream_v3_decode,item(2:end),'uniformoutput',false);
      v=struct(empty{:});
      fields={'variable_id','canonical','display_label','dtype','unit','semantic_role','value_kind','value_format','decimal_separator','time_origin','time_reference','dimension_ids','coordinate_role','axis_kind','axis_origin','axis_step','axis_count'};
      for k=1:numel(fields),v.(fields{k})=values{k};endfor
      v.name=v.canonical;schema(end+1)=v;
    endfor
    ending=gxtxt_table_stream_v3_readline(out,pid);if(!strcmp(ending,'END')),error('GXTXT:TableStream','Invalid Table Stream v3 metadata terminator');endif
    metadata.capabilities=capabilities;metadata.variables=schema;
    names={schema.name};selected={schema.variable_id};
    S=struct('api_version',3,'transport','canonical_tcl','numeric_transport',char(numeric_transport),'dataset_id',dataset_id,'storage_provider',provider,'row_dimension',row_dimension,'row_count',row_count,'range_start',range_start,'range_count',range_count,'range_mode',range_mode,'chunk_rows',chunk_rows,'selected_variable_ids',{selected},'names',{names},'columns',{names},'schema',schema,'metadata',metadata,'row_number',range_start,'eof',(range_count==0),'bridge_in',in,'bridge_out',out,'bridge_pid',pid,'fid',-1,'closed',false);
  catch err
    if(in>=0),try fclose(in);catch;end_try_catch;endif
    if(out>=0),try fclose(out);catch;end_try_catch;endif
    if(pid>0),try waitpid(pid);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction

function v=field_or(s,name,def),if(isstruct(s)&&isfield(s,name)),v=s.(name);else v=def;endif;endfunction
function name=safe_field(name),name=regexprep(name,'[^A-Za-z0-9_]','_');if(isempty(name)||!isletter(name(1))),name=['x_' name];endif;endfunction
function v=typed_field(key,value)
  if(any(strcmp(key,{'api_version','row_count','range_start','range_count','chunk_rows'}))),v=str2double(value);else v=value;endif
endfunction
function bridge_error(parts)
  if(numel(parts)>=2&&strcmp(parts{1},'ERROR')),error('GXTXT:TableStream','%s',gxtxt_table_stream_v3_decode(parts{2}));endif
endfunction
