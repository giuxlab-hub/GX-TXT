function request_path = gxtxt_dataset_publish_request(output_dir, dataset_id, contract, format, relpath, meta)
% GX-TXT Dataset Publication API v1.
% Create one framework publication request for a module-produced dataset.
% The framework, not this helper, computes SHA-256 and updates datasets.ini.
  if(nargin < 5), error('GXTXT:DatasetPublication','output_dir, dataset_id, contract, format and relpath are required'); endif
  if(nargin < 6 || isempty(meta)), meta=struct(); endif
  dataset_id=strtrim(dataset_id); contract=strtrim(contract); format=strtrim(format); relpath=strtrim(relpath);
  if(isempty(regexp(dataset_id,'^[A-Za-z0-9_.-]+$','once'))), error('GXTXT:DatasetPublication','invalid dataset_id'); endif
  if(isempty(contract) || isempty(format) || isempty(relpath)), error('GXTXT:DatasetPublication','contract, format and relpath are required'); endif
  if(relpath(1)=='/' || !isempty(regexp(relpath,'(^|[\\/])\.\.([\\/]|$)','once'))), error('GXTXT:DatasetPublication','path must be module-output-relative and may not contain ..'); endif
  reqdir=fullfile(output_dir,'dataset_publications'); if(exist(reqdir,'dir')!=7), mkdir(reqdir); endif
  request_path=fullfile(reqdir,[dataset_id '.ini']);
  fid=fopen(request_path,'w'); if(fid<0), error('GXTXT:DatasetPublication','cannot write %s',request_path); endif
  unwind_protect
    fprintf(fid,'; GX-TXT Dataset Publication API v1\n[publication]\n');
    write_kv(fid,'api_version','1'); write_kv(fid,'dataset_id',dataset_id); write_kv(fid,'contract',contract); write_kv(fid,'format',format); write_kv(fid,'path',relpath);
    for k={'variables','units','semantic_roles','source','provenance'}
      name=k{1}; if(isfield(meta,name)), v=value_text(meta.(name)); else v=''; endif; write_kv(fid,name,v);
    endfor
    if(isfield(meta,'notes')), write_kv(fid,'notes',value_text(meta.notes)); endif
    if(isfield(meta,'storage_kind')), write_kv(fid,'storage_kind',value_text(meta.storage_kind)); endif
    if(isfield(meta,'media_type')), write_kv(fid,'media_type',value_text(meta.media_type)); endif
    if(isfield(meta,'computed_annotations')), write_kv(fid,'computed_annotations',value_text(meta.computed_annotations)); endif
    if(isfield(meta,'schema_source_dataset_id')), write_kv(fid,'schema_source_dataset_id',value_text(meta.schema_source_dataset_id)); endif
    if(isfield(meta,'schema_source_variable_ids')), write_kv(fid,'schema_source_variable_ids',value_text(meta.schema_source_variable_ids)); endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function s=value_text(v)
  if(iscell(v)), s=strjoin(cellfun(@to_text,v,'uniformoutput',false),';'); else s=to_text(v); endif
endfunction
function s=to_text(v)
  if(ischar(v)), s=v; elseif(isnumeric(v) || islogical(v)), s=num2str(v); else s=''; endif
endfunction
function write_kv(fid,k,v)
  v=strrep(v,'\\','\\\\'); v=strrep(v,sprintf('\n'),'\\n'); v=strrep(v,sprintf('\r'),'\\r'); fprintf(fid,'%s=%s\n',k,v);
endfunction
