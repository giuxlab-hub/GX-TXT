function gxtxt_script_provided_execute(cfg, project)
% Invoke one source-declared function inside the existing supervised runner.
% SPDX-License-Identifier: GPL-3.0-or-later
  if (isempty(project)),error('GXTXT:ProvidedAPI:Snapshot','Exact Project snapshot required');endif
  plan=jsondecode(gxtxt_ini_get(cfg,'provided_api.octave_plan_json',''),'makeValidName',false);
  request=jsondecode(gxtxt_ini_get(cfg,'provided_api.request_json',''),'makeValidName',false);
  if (!strcmp(request.pins.project_sha256,project.sha256)),error('GXTXT:ProvidedAPI:Snapshot','Project source revision differs');endif
  root=gxtxt_ini_get(cfg,'script_project.project_root','');
  expected=canonicalize_file_name(fullfile(root,plan.file));
  if (!strcmp(canonicalize_file_name(which(plan.function)),expected))
    error('GXTXT:ProvidedAPI:Source','Function resolves outside its admitted source file');
  endif
  arguments={};wire=plan.arguments_wire;
  for k=1:numel(wire)
    if(iscell(wire)),item=wire{k};else,item=wire(k);endif
    arguments{end+1}=gxtxt_script_bridge_internal('unpack',item);
  endfor
  result=feval(plan.function,arguments{:});
  packed=provided_pack(result,plan.result_type,0);
  encoded=jsonencode(packed);
  if(numel(unicode2native(encoded,'UTF-8'))>1048576),error('GXTXT:ProvidedAPI:Limit','Result exceeds1MiB');endif
  path=fullfile(gxtxt_ini_get(cfg,'runtime.output_dir',''),'provided_api_result_wire.json');
  if(exist(path,'file')),error('GXTXT:ProvidedAPI:Occupied','Result receipt already exists');endif
  [fd,message]=fopen(path,'wb');if(fd<0),error('GXTXT:ProvidedAPI:Write','%s',message);endif
  unwind_protect
    fwrite(fd,unicode2native([encoded sprintf('\n')],'UTF-8'),'uint8');
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
endfunction

function packed=provided_pack(value,spec,depth)
  if(depth>8),error('GXTXT:ProvidedAPI:Depth','Structured result exceeds declared bound');endif
  switch(spec.kind)
    case 'null'
      if(!isempty(value)),error('GXTXT:ProvidedAPI:Type','Null result must be empty');endif
      packed=struct('kind','null');
    case 'object'
      if(!isstruct(value)||!isscalar(value)),error('GXTXT:ProvidedAPI:Type','Object result requires scalar struct');endif
      fields=struct();names={};definitions=spec.fields;
      for k=1:numel(definitions)
        if(iscell(definitions)),field=definitions{k};else,field=definitions(k);endif
        names{end+1}=field.name;
        if(isfield(value,field.name)),item=value.(field.name);
        elseif(field.required),error('GXTXT:ProvidedAPI:Type','Required result field missing');
        else,continue;endif
        fields.(field.name)=provided_pack(item,field,depth+1);
      endfor
      if(any(!ismember(fieldnames(value),names))),error('GXTXT:ProvidedAPI:Type','Unknown result object field');endif
      packed=struct('kind','struct','fields',fields);
    case 'array'
      if((!iscell(value)&&!isvector(value)&&!isempty(value))||numel(value)>spec.max_items),error('GXTXT:ProvidedAPI:Type','Result array shape/size differs');endif
      packed=struct('kind','cell','items',{{}});
      for k=1:numel(value)
        if(iscell(value)),item=value{k};else,item=value(k);endif
        packed.items{end+1}=provided_pack(item,spec.items,depth+1);
      endfor
    case 'integer'
      if(!isnumeric(value)||!isscalar(value)||!isreal(value)||!isfinite(value)||value!=fix(value)),error('GXTXT:ProvidedAPI:Type','Integer result requires one exact integer');endif
      if(!isinteger(value)&&abs(value)>=flintmax()),error('GXTXT:ProvidedAPI:Type','Large integer result must retain native integer storage');endif
      if(!isinteger(value)),value=int64(value);endif
      [packed,paths]=gxtxt_script_bridge_internal('pack',value);
    case {'number','double'}
      if(!isnumeric(value)||!isscalar(value)||!isreal(value)||!isfinite(value)),error('GXTXT:ProvidedAPI:Type','Number result requires one finite real');endif
      [packed,paths]=gxtxt_script_bridge_internal('pack',value);
    case 'boolean'
      if(!islogical(value)||!isscalar(value)),error('GXTXT:ProvidedAPI:Type','Boolean result requires scalar logical');endif
      [packed,paths]=gxtxt_script_bridge_internal('pack',value);
    case 'string'
      if(!ischar(value)),error('GXTXT:ProvidedAPI:Type','String result requires text');endif
      [packed,paths]=gxtxt_script_bridge_internal('pack',value);
    otherwise,error('GXTXT:ProvidedAPI:Type','Unsupported declared result type');
  endswitch
endfunction
