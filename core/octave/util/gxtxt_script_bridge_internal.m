function [result,paths] = gxtxt_script_bridge_internal(action, varargin)
% Private transport shared by the stable Octave Script Bridge functions.
% SPDX-License-Identifier: GPL-3.0-or-later
  global GXTXT_SCRIPT_BRIDGE_STATE;
  global GXTXT_SCRIPT_CALLBACKS;
  paths={};
  switch(action)
    case 'start'
      if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE) && isfield(GXTXT_SCRIPT_BRIDGE_STATE,'active') && GXTXT_SCRIPT_BRIDGE_STATE.active)
        error('GXTXT:ScriptBridge:InvalidArguments','Octave Script Bridge is already active');
      endif
      config=varargin{1};execution=varargin{2};
      if(!ischar(config)||exist(config,'file')!=2||!isstruct(execution)||numel(execution)!=1)
        error('GXTXT:ScriptBridge:InvalidArguments','start requires a runtime configuration and scalar execution metadata');
      endif
      required={'script_name','script_sha256','arguments_raw'};
      for k=1:numel(required)
        if(!isfield(execution,required{k})),error('GXTXT:ScriptBridge:InvalidArguments','execution metadata is missing %s',required{k});endif
      endfor
      here=fileparts(mfilename('fullpath'));
      root=fileparts(fileparts(fileparts(here)));
      server=fullfile(root,'core','python','gxtxt_script_bridge_server.py');
      if(exist(server,'file')!=2),error('GXTXT:ScriptBridge:Transport','CORE bridge server is missing');endif
      runtime=gxtxt_ini_read(config);
      python=strtrim(gxtxt_ini_get(runtime,'runtime.python_cmd','python3'));
      if(isempty(python)),python='python3';endif
      % A private local execution buffer scope; no caller-supplied data path.
      previous_scope=getenv('GXTXT_BRIDGE_WORKSPACE');buffer_scope=tempname();
      oldmask=umask(077);mkdir(buffer_scope);umask(oldmask);
      setenv('GXTXT_BRIDGE_WORKSPACE',buffer_scope);
      unwind_protect
        [in,out,pid]=popen2(python,{'-u',server,config});
      unwind_protect_cleanup
        setenv('GXTXT_BRIDGE_WORKSPACE',previous_scope);
      end_unwind_protect
      if(pid<0),error('GXTXT:ScriptBridge:Transport','cannot launch CORE bridge server');endif
      GXTXT_SCRIPT_BRIDGE_STATE=struct('active',true,'in',in,'out',out,'pid',pid,'callback_paths',{{}},'buffer_scope',buffer_scope);
      GXTXT_SCRIPT_CALLBACKS=containers.Map('KeyType','char','ValueType','any');
      request=struct('action','start','execution',execution);
      try
        result=send_request(request);
      catch err
        close_transport();
        rethrow(err);
      end_try_catch
    case 'stop'
      require_active();
      try
        result=send_request(struct('action','stop'));
      catch err
        close_transport();
        rethrow(err);
      end_try_catch
      close_transport();
    case 'request'
      require_active();
      result=send_request(varargin{1});
    case 'register_callback'
      require_active();
      if(!isa(varargin{1},'function_handle'))
        error('GXTXT:ScriptCallback:InvalidArguments','registration requires a function handle');
      endif
      id=send_request(struct('action','callback_register'));
      GXTXT_SCRIPT_CALLBACKS(id)=varargin{1};
      result=struct('gxtxt_callback_id',id);
    case 'release_callback'
      require_active();
      handle=varargin{1};
      if(!isstruct(handle)||!isfield(handle,'gxtxt_callback_id'))
        error('GXTXT:ScriptCallback:InvalidArguments','release requires a callback handle');
      endif
      result=send_request(struct('action','callback_release','id',handle.gxtxt_callback_id));
      if(isKey(GXTXT_SCRIPT_CALLBACKS,handle.gxtxt_callback_id))
        remove(GXTXT_SCRIPT_CALLBACKS,handle.gxtxt_callback_id);
      endif
    case 'pack'
      [result,paths]=pack_value(varargin{1},0);
    otherwise
      error('GXTXT:ScriptBridge:Transport','unknown internal bridge action');
  endswitch
endfunction

function require_active()
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(!isstruct(GXTXT_SCRIPT_BRIDGE_STATE)||!isfield(GXTXT_SCRIPT_BRIDGE_STATE,'active')||!GXTXT_SCRIPT_BRIDGE_STATE.active)
    error('GXTXT:ScriptBridge:NotActive','Octave Script Bridge is not active');
  endif
endfunction

function close_transport()
  global GXTXT_SCRIPT_BRIDGE_STATE;
  global GXTXT_SCRIPT_CALLBACKS;
  if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE)&&isfield(GXTXT_SCRIPT_BRIDGE_STATE,'pid'))
    if(isfield(GXTXT_SCRIPT_BRIDGE_STATE,'callback_paths'))
      for k=1:numel(GXTXT_SCRIPT_BRIDGE_STATE.callback_paths)
        try unlink(GXTXT_SCRIPT_BRIDGE_STATE.callback_paths{k});catch;end_try_catch
      endfor
    endif
    try fclose(GXTXT_SCRIPT_BRIDGE_STATE.in);catch;end_try_catch
    try fclose(GXTXT_SCRIPT_BRIDGE_STATE.out);catch;end_try_catch
    try waitpid(GXTXT_SCRIPT_BRIDGE_STATE.pid);catch;end_try_catch
    if(isfield(GXTXT_SCRIPT_BRIDGE_STATE,'buffer_scope'))
      try rmdir(GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,'s');catch;end_try_catch
    endif
  endif
  GXTXT_SCRIPT_BRIDGE_STATE=struct('active',false);
  GXTXT_SCRIPT_CALLBACKS=[];
endfunction

function result=send_request(request)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(!isstruct(request)||!isfield(request,'action'))
    error('GXTXT:ScriptBridge:InvalidArguments','invalid bridge request');
  endif
  payload=jsonencode(request);
  fclear(GXTXT_SCRIPT_BRIDGE_STATE.out);
  fputs(GXTXT_SCRIPT_BRIDGE_STATE.in,[payload sprintf('\n')]);
  fflush(GXTXT_SCRIPT_BRIDGE_STATE.in);
  started=time();
  while(true)
    response=fgetl(GXTXT_SCRIPT_BRIDGE_STATE.out);
    if(ischar(response)),break;endif
    if(time()-started>3600)
      error('GXTXT:ScriptBridge:Transport','CORE bridge server timed out');
    endif
    pause(0.01);fclear(GXTXT_SCRIPT_BRIDGE_STATE.out);
  endwhile
  try envelope=jsondecode(response,'makeValidName',false);
  catch err,error('GXTXT:ScriptBridge:Transport','invalid CORE bridge response: %s',err.message);
  end_try_catch
  while(isstruct(envelope)&&isfield(envelope,'event')&&strcmp(envelope.event,'callback_invoke'))
    serve_callback(envelope);
    started=time();
    while(true)
      response=fgetl(GXTXT_SCRIPT_BRIDGE_STATE.out);
      if(ischar(response)),break;endif
      if(time()-started>3600),error('GXTXT:ScriptBridge:Transport','CORE bridge server timed out');endif
      pause(0.01);fclear(GXTXT_SCRIPT_BRIDGE_STATE.out);
    endwhile
    try envelope=jsondecode(response,'makeValidName',false);
    catch err,error('GXTXT:ScriptBridge:Transport','invalid CORE bridge response: %s',err.message);
    end_try_catch
  endwhile
  if(!isstruct(envelope)||!isfield(envelope,'ok'))
    error('GXTXT:ScriptBridge:Transport','incomplete CORE bridge response');
  endif
  for k=1:numel(GXTXT_SCRIPT_BRIDGE_STATE.callback_paths)
    try unlink(GXTXT_SCRIPT_BRIDGE_STATE.callback_paths{k});catch;end_try_catch
  endfor
  GXTXT_SCRIPT_BRIDGE_STATE.callback_paths={};
  if(!envelope.ok)
    if(!isfield(envelope,'identifier')||!isfield(envelope,'message'))
      error('GXTXT:ScriptBridge:Transport','incomplete CORE bridge error');
    endif
    error(envelope.identifier,'%s',envelope.message);
  endif
  result=unpack_value(envelope.value,0);
endfunction

function serve_callback(event)
  global GXTXT_SCRIPT_BRIDGE_STATE GXTXT_SCRIPT_CALLBACKS;
  id=event.id;
  try
    if(!isKey(GXTXT_SCRIPT_CALLBACKS,id))
      error('GXTXT:ScriptCallback:UnknownCallback','callback is no longer registered');
    endif
    raw=event.args;
    if(isstruct(raw)),raw=num2cell(raw);endif
    args=cell(1,numel(raw));
    for k=1:numel(raw),args{k}=unpack_value(raw{k},0);endfor
    value=feval(GXTXT_SCRIPT_CALLBACKS(id),args{:});
    [packed,paths]=pack_value(value,0);
    reply=struct('action','callback_result','id',id,'ok',true,'value',packed);
  catch err
    paths={};
    identifier=err.identifier;
    if(isempty(identifier)),identifier='GXTXT:ScriptCallback:Error';endif
    reply=struct('action','callback_result','id',id,'ok',false,'identifier',identifier,'message',err.message);
  end_try_catch
  fputs(GXTXT_SCRIPT_BRIDGE_STATE.in,[jsonencode(reply) sprintf('\n')]);
  fflush(GXTXT_SCRIPT_BRIDGE_STATE.in);
  GXTXT_SCRIPT_BRIDGE_STATE.callback_paths=[GXTXT_SCRIPT_BRIDGE_STATE.callback_paths paths];
endfunction

function [packed,paths]=pack_value(value,depth)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(depth>32),error('GXTXT:ScriptBridge:InvalidArguments','bridge value nesting exceeds 32');endif
  paths={};
  if(isstruct(value)&&numel(value)==1&&isfield(value,'gxtxt_callback_id')&&numel(fieldnames(value))==1)
    packed=struct('kind','callback','id',value.gxtxt_callback_id);
  elseif(ischar(value))
    packed=struct('kind','string','value',value);
  elseif(islogical(value)&&isscalar(value))
    packed=struct('kind','logical','value',logical(value));
  elseif(isinteger(value)&&isscalar(value))
    if(strncmp(class(value),'uint',4)),decimal=sprintf('%u',value);
    else decimal=sprintf('%d',value);endif
    packed=struct('kind','integer_scalar','value',decimal);
  elseif(isnumeric(value)&&isscalar(value))
    packed=struct('kind','numeric_scalar','value',num2str(value,17));
  elseif(isnumeric(value)||islogical(value))
    packed=struct('kind','numeric_array','shape',size(value));
    if(numel(value)>10000)
      if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE)&&isfield(GXTXT_SCRIPT_BRIDGE_STATE,'buffer_scope'))
        path=tempname(GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope);
      else,path=tempname();endif
      fid=fopen(path,'wb','ieee-le');
      if(fid<0),error('GXTXT:ScriptBridge:Transport','cannot create numeric transport');endif
      unwind_protect
        fwrite(fid,double(value(:)),'double');
      unwind_protect_cleanup
        fclose(fid);
      end_unwind_protect
      packed.binary_path=path;paths={path};
    else
      packed.values=arrayfun(@(x)num2str(x,17),value(:),'UniformOutput',false);
    endif
  elseif(iscell(value))
    packed=struct('kind','cell','items',{{}});
    for k=1:numel(value)
      [item,item_paths]=pack_value(value{k},depth+1);
      packed.items{end+1}=item;paths=[paths item_paths];
    endfor
  elseif(isstruct(value))
    if(numel(value)!=1)
      packed=struct('kind','struct_array','items',{{}});
      for k=1:numel(value)
        [item,item_paths]=pack_value(value(k),depth+1);
        packed.items{end+1}=item;paths=[paths item_paths];
      endfor
    else
      fields=struct();names=fieldnames(value);
      for k=1:numel(names)
        [item,item_paths]=pack_value(value.(names{k}),depth+1);
        fields.(names{k})=item;paths=[paths item_paths];
      endfor
      packed=struct('kind','struct','fields',fields);
    endif
  else
    error('GXTXT:ScriptBridge:InvalidArguments','unsupported bridge value type %s',class(value));
  endif
endfunction

function value=unpack_value(wire,depth)
  if(depth>32),error('GXTXT:ScriptBridge:Transport','bridge result nesting exceeds 32');endif
  switch(wire.kind)
    case 'string',value=wire.value;
    case 'logical',value=logical(wire.value);
    case 'numeric_scalar',value=str2double(wire.value);
    case 'integer_scalar',value=unpack_integer(wire.value);
    case 'numeric_array'
      shape=double(wire.shape(:)');
      if(isfield(wire,'binary_path'))
        fid=fopen(wire.binary_path,'rb','ieee-le');
        if(fid<0),error('GXTXT:ScriptBridge:Transport','cannot read numeric result transport');endif
        unwind_protect
          values=fread(fid,prod(shape),'*double');
        unwind_protect_cleanup
          fclose(fid);
          unlink(wire.binary_path);
        end_unwind_protect
      else
        raw=wire.values;
        if(iscell(raw)),values=cellfun(@str2double,raw(:));
        elseif(ischar(raw)),values=str2double(cellstr(raw));
        else values=double(raw(:));endif
      endif
      value=reshape(values,shape);
    case 'cell'
      items=wire.items;value=cell(1,numel(items));
      for k=1:numel(items)
        if(iscell(items)),item=items{k};else item=items(k);endif
        value{k}=unpack_value(item,depth+1);
      endfor
    case 'struct'
      value=struct();names=fieldnames(wire.fields);
      for k=1:numel(names),value.(names{k})=unpack_value(wire.fields.(names{k}),depth+1);endfor
    case 'struct_array'
      items=wire.items;value=struct([]);
      for k=1:numel(items)
        if(iscell(items)),item=items{k};else item=items(k);endif
        value(k)=unpack_value(item,depth+1);
      endfor
    otherwise,error('GXTXT:ScriptBridge:Transport','unknown bridge value kind %s',wire.kind);
  endswitch
endfunction

% Keep ordinary bridge integers as doubles for existing consumers, and retain
% exact identity beyond flintmax with native integer scalars.
function value=unpack_integer(decimal)
  approx=str2double(decimal);
  if(abs(approx)<flintmax()),value=approx;return;endif
  negative=decimal(1)=='-';
  if(negative||decimal(1)=='+'),digits=decimal(2:end);else digits=decimal;endif
  if(isempty(digits)||any(digits<'0'|digits>'9'))
    error('GXTXT:ScriptBridge:Transport','invalid integer scalar');
  endif
  number=uint64(0);limit=intmax('uint64');ten=uint64(10);
  for digit=digits
    d=uint64(double(digit)-double('0'));
    if(number>idivide(limit-d,ten,'floor'))
      error('GXTXT:ScriptBridge:Transport','integer exceeds 64-bit transport');
    endif
    number=number*ten+d;
  endfor
  if(negative)
    boundary=uint64(intmax('int64'))+uint64(1);
    if(number>boundary),error('GXTXT:ScriptBridge:Transport','integer below int64 range');endif
    if(number==boundary),value=intmin('int64');else value=-int64(number);endif
  elseif(number<=uint64(intmax('int64'))),value=int64(number);
  else value=number;endif
endfunction
