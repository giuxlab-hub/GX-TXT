% GX-TXT Computed Data Annotation API v1 writer.
% SPDX-License-Identifier: GPL-3.0-or-later
function path = gxtxt_data_annotations_write(output_dir, relpath, dataset_id, annotations)
  if(nargin<4), error('GXTXT:DataAnnotations','output_dir, relpath, dataset_id, annotations are required'); endif
  if(isempty(regexp(dataset_id,'^[A-Za-z0-9_.-]+$','once'))), error('GXTXT:DataAnnotations','invalid dataset_id'); endif
  if(isempty(relpath) || relpath(1)=='/' || !isempty(regexp(relpath,'(^|[\\/])\.\.([\\/]|$)','once'))), error('GXTXT:DataAnnotations','relpath must be output-relative and may not contain ..'); endif
  path=fullfile(output_dir,relpath); parent=fileparts(path); if(exist(parent,'dir')!=7),mkdir(parent);endif
  if(isempty(annotations)), annotations={}; endif
  if(isstruct(annotations)), annotations=num2cell(annotations); endif
  if(!iscell(annotations)), error('GXTXT:DataAnnotations','annotations must be a struct array or cell array of structs'); endif
  for ii=1:numel(annotations),if(!isstruct(annotations{ii})),error('GXTXT:DataAnnotations','annotation %d is not a struct',ii);endif;endfor
  fid=fopen(path,'w'); if(fid<0), error('GXTXT:DataAnnotations','cannot write %s',path); endif
  unwind_protect
    fprintf(fid,'; GX-TXT Computed Data Annotation API v1\n[annotations]\n');
    kv(fid,'api_version','1'); kv(fid,'dataset_id',dataset_id); kv(fid,'count',num2str(numel(annotations)));
    for i=1:numel(annotations)
      A=annotations{i}; fprintf(fid,'\n[annotation.%d]\n',i);
      if(!isfield(A,'id')||isempty(strtrim(to_text(A.id)))), error('GXTXT:DataAnnotations','annotation %d missing id',i); endif
      if(!isfield(A,'type')||isempty(strtrim(to_text(A.type)))), error('GXTXT:DataAnnotations','annotation %d missing type',i); endif
      type=lower(strtrim(to_text(A.type))); if(!any(strcmp(type,{'vline','hline','point','text'}))),error('GXTXT:DataAnnotations','unsupported type %s',type);endif
      kv(fid,'id',A.id); kv(fid,'type',type);
      fields={'x','x_variable','x_unit','y','y_variable','y_unit','label','style_hint'};
      for k=1:numel(fields), f=fields{k}; if(isfield(A,f)&&!isempty(A.(f))),kv(fid,f,A.(f));endif; endfor
      if(any(strcmp(type,{'vline','point','text'}))), require(A,{'x','x_variable','x_unit'},i); endif
      if(any(strcmp(type,{'hline','point','text'}))), require(A,{'y','y_variable','y_unit'},i); endif
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function require(A,names,i),for k=1:numel(names),f=names{k};if(!isfield(A,f)||isempty(to_text(A.(f)))),error('GXTXT:DataAnnotations','annotation %d missing %s',i,f);endif;endfor;endfunction
function s=to_text(v),if(ischar(v)),s=v;elseif(isnumeric(v)||islogical(v)),s=num2str(v);else s='';endif;endfunction
function kv(fid,k,v),s=to_text(v);s=strrep(s,'\\','\\\\');s=strrep(s,sprintf('\n'),'\\n');s=strrep(s,sprintf('\r'),'\\r');fprintf(fid,'%s=%s\n',k,s);endfunction
