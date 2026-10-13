% SPDX-License-Identifier: GPL-3.0-or-later
% Table Stream API v2 discovers session schema and CSV syntax in CORE.
function [delimiter,schema]=gxtxt_table_stream_schema(path,header)
  schema=struct('name',{},'variable_id',{},'value_kind',{},'value_format',{},'decimal_separator',{},'unit',{},'time_origin',{},'time_reference',{});
  candidates={',',';',sprintf('\t')}; counts=zeros(1,3);
  for k=1:3
    try,counts(k)=numel(gxtxt_csv_split_line(header,candidates{k}));catch,counts(k)=0;end_try_catch
  endfor
  [~,best]=max(counts); delimiter=candidates{best};
  folder=fileparts(path);registry='';session='';
  for depth=1:8
    candidate=fullfile(folder,'metadata','datasets.ini');
    if(exist(candidate,'file')==2),registry=candidate;session=folder;break;endif
    parent=fileparts(folder);if(strcmp(parent,folder)),break;endif;folder=parent;
  endfor
  if(isempty(registry)),return;endif
  data=gxtxt_table_registry_dataset(registry,session,path);
  if(isempty(fieldnames(data))),return;endif
  q=field_or(data,'canonical_delimiter','');
  if(strcmp(q,'tab')),delimiter=sprintf('\t');elseif(strcmp(q,'semicolon')),delimiter=';';elseif(strcmp(q,'comma')),delimiter=',';endif
  n=str2double(field_or(data,'var_count','0'));
  if(!isfinite(n)||n<0),return;endif
  for j=1:min(n,100000)
    prefix=['var' num2str(j) '_'];
    name=strtrim(field_or(data,[prefix 'canonical'],''));
    enabled=field_or(data,[prefix 'enabled'],'0');
    if(isempty(name)||strcmp(enabled,'0')),continue;endif
    v=struct('name',name,'variable_id',field_or(data,[prefix 'variable_id'],''), ...
      'value_kind',field_or(data,[prefix 'value_kind'],'number'), ...
      'value_format',field_or(data,[prefix 'value_format'],''), ...
      'decimal_separator',field_or(data,[prefix 'decimal_separator'],'.'), ...
      'unit',field_or(data,[prefix 'unit'],''), ...
      'time_origin',field_or(data,[prefix 'time_origin'],''), ...
      'time_reference',field_or(data,[prefix 'time_reference'],'elapsed'));
    schema(end+1)=v;
  endfor
endfunction

function data=gxtxt_table_registry_dataset(registry,session,path)
  data=struct();entry=struct();inside=false;fid=fopen(registry,'r');
  if(fid<0),return;endif
  target=canonicalize_file_name(path);
  unwind_protect
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif
      if(line(1)=='[')
        if(inside && entry_matches(entry,session,target)),data=entry;return;endif
        inside=!isempty(regexp(line,'^\[dataset\.[^]]+\]$','once'));
        entry=struct();continue;
      endif
      if(!inside),continue;endif
      eq=find(line=='=',1);if(isempty(eq)),continue;endif
      key=strtrim(line(1:eq-1));if(isempty(regexp(key,'^[A-Za-z0-9_]+$','once'))),continue;endif
      entry.(key)=line(eq+1:end);
    endwhile
    if(inside && entry_matches(entry,session,target)),data=entry;endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function yes=entry_matches(entry,session,target)
  yes=false;if(!isfield(entry,'path')),return;endif
  q=entry.path;
  if(!is_absolute_filename(q)),q=fullfile(session,q);endif
  actual=canonicalize_file_name(q);
  yes=!isempty(actual)&&strcmp(actual,target);
endfunction

function v=field_or(entry,key,def)
  if(isfield(entry,key)),v=entry.(key);else v=def;endif
endfunction
