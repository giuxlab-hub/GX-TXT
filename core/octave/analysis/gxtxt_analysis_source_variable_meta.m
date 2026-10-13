% SPDX-License-Identifier: GPL-3.0-or-later
% Analysis Source Metadata Runtime Extension v1.
% [unit, role, meta] = gxtxt_analysis_source_variable_meta(runtime,source_id,variable_name)
% meta also exposes source_id and canonical dataset_id (v0.9.3.3 additive).
function [unit, role, meta] = gxtxt_analysis_source_variable_meta(runtime,source_id,variable_name)
  dataset_id='';
  if(nargin>=2 && !isempty(runtime) && !isempty(source_id))
    dataset_id=strtrim(gxtxt_ini_get(runtime,['analysis_source.' source_id '.dataset_id'],''));
  endif
  unit=''; role=''; meta=struct('found',false,'source_id',source_id,'dataset_id',dataset_id,'name',variable_name,'variable_id','','unit','','semantic_role','','semantic_source','','semantic_reason','','original_header','','source_column','');
  if(nargin<3 || isempty(runtime) || isempty(source_id) || isempty(variable_name)),return;endif
  n=str2double(strtrim(gxtxt_ini_get(runtime,['analysis_source.' source_id '.variable_count'],'0')));
  if(!isfinite(n)||n<0),n=0;endif
  for i=1:round(n)
    p=sprintf('analysis_source.%s.variable.%d.',source_id,i);
    name=strtrim(gxtxt_ini_get(runtime,[p 'name'],''));
    variable_id=strtrim(gxtxt_ini_get(runtime,[p 'variable_id'],''));
    if(!strcmp(name,variable_name) && !strcmp(variable_id,variable_name)),continue;endif
    unit=strtrim(gxtxt_ini_get(runtime,[p 'unit'],''));
    role=strtrim(gxtxt_ini_get(runtime,[p 'semantic_role'],''));
    meta=struct('found',true,'source_id',source_id,'dataset_id',dataset_id,'name',name,'variable_id',variable_id,'unit',unit,'semantic_role',role, ...
      'semantic_source',strtrim(gxtxt_ini_get(runtime,[p 'semantic_source'],'default')), ...
      'semantic_reason',strtrim(gxtxt_ini_get(runtime,[p 'semantic_reason'],'')), ...
      'original_header',strtrim(gxtxt_ini_get(runtime,[p 'original_header'],'')), ...
      'source_column',strtrim(gxtxt_ini_get(runtime,[p 'source_column'],'')), ...
      'value_kind',strtrim(gxtxt_ini_get(runtime,[p 'value_kind'],'number')), ...
      'value_format',strtrim(gxtxt_ini_get(runtime,[p 'value_format'],'')), ...
      'decimal_separator',strtrim(gxtxt_ini_get(runtime,[p 'decimal_separator'],'.')), ...
      'time_reference',strtrim(gxtxt_ini_get(runtime,[p 'time_reference'],'elapsed')), ...
      'time_origin',strtrim(gxtxt_ini_get(runtime,[p 'time_origin'],'')));
    return;
  endfor
  % Compatibility fallback for runtimes that expose only parallel summary lists.
  vars=parse_list_local(gxtxt_ini_get(runtime,['analysis_source.' source_id '.variables'],''));
  units=parse_list_keep_empty(gxtxt_ini_get(runtime,['analysis_source.' source_id '.units'],''));
  roles=parse_list_keep_empty(gxtxt_ini_get(runtime,['analysis_source.' source_id '.semantic_roles'],''));
  k=find(strcmp(vars,variable_name),1);
  if(!isempty(k))
    if(k<=numel(units)),unit=strtrim(units{k});endif
    if(k<=numel(roles)),role=strtrim(roles{k});endif
    meta.found=true;meta.unit=unit;meta.semantic_role=role;
  endif
endfunction
function out=parse_list_local(s),s=strrep(s,',',';');if(isempty(strtrim(s))),out={};else out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));endif;endfunction
function out=parse_list_keep_empty(s),if(isempty(s)),out={};else out=strsplit(s,';');out=cellfun(@strtrim,out,'UniformOutput',false);endif;endfunction
