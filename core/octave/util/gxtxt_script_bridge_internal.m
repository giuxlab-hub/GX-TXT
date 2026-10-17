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
      previous_typed=getenv('GXTXT_BRIDGE_TYPED_DESCRIPTORS');previous_owner=getenv('GXTXT_BRIDGE_CLIENT_OWNS_RESOURCE');
      oldmask=umask(077);mkdir(buffer_scope);umask(oldmask);
      setenv('GXTXT_BRIDGE_WORKSPACE',buffer_scope);
      setenv('GXTXT_BRIDGE_TYPED_DESCRIPTORS','1');setenv('GXTXT_BRIDGE_CLIENT_OWNS_RESOURCE','0');
      unwind_protect
        [in,out,pid]=popen2(python,{'-u',server,config});
      unwind_protect_cleanup
        setenv('GXTXT_BRIDGE_WORKSPACE',previous_scope);
        setenv('GXTXT_BRIDGE_TYPED_DESCRIPTORS',previous_typed);setenv('GXTXT_BRIDGE_CLIENT_OWNS_RESOURCE',previous_owner);
      end_unwind_protect
      if(pid<0),error('GXTXT:ScriptBridge:Transport','cannot launch CORE bridge server');endif
      GXTXT_SCRIPT_BRIDGE_STATE=struct('active',true,'in',in,'out',out,'pid',pid,'callback_paths',{{}},'buffer_scope',buffer_scope);
      GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays=containers.Map('KeyType','char','ValueType','any');
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
      constant_ids=keys(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays);
      for k=1:numel(constant_ids)
        entry=GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays(constant_ids{k});
        if(strcmp(entry.owner,handle.gxtxt_callback_id)),remove(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays,constant_ids{k});endif
      endfor
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
  response=read_response_frame();
  try envelope=jsondecode(response,'makeValidName',false);
  catch err,error('GXTXT:ScriptBridge:Transport','invalid CORE bridge response: %s',err.message);
  end_try_catch
  while(isstruct(envelope)&&isfield(envelope,'event'))
    if(strcmp(envelope.event,'callback_invoke'))
      serve_callback(envelope);
    elseif(any(strcmp(envelope.event,{'callback_arguments_release','callback_buffers_release'})))
      release_callback_storage(envelope);
    else
      error('GXTXT:ScriptCallback:Transport','Unknown callback lifecycle event');
    endif
    response=read_response_frame();
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

function response=read_response_frame()
  global GXTXT_SCRIPT_BRIDGE_STATE;
  % popen2 returns a nonblocking read stream. fgets may return a partial line
  % at EAGAIN, including a full 64 KiB pipe fragment. Only LF completes a frame.
  started=time();parts={};bytes=0;limit=64*1024*1024;
  while(true)
    piece=fgets(GXTXT_SCRIPT_BRIDGE_STATE.out);
    if(ischar(piece)&&!isempty(piece))
      bytes+=numel(piece);
      if(bytes>limit),error('GXTXT:ScriptBridge:Transport','CORE control response exceeds 64 MiB');endif
      parts{end+1}=piece;
      if(piece(end)==sprintf('\n'))
        response=[parts{:}];response=response(1:end-1);return;
      endif
    endif
    if(time()-started>3600),error('GXTXT:ScriptBridge:Transport','CORE bridge server timed out before a complete response frame');endif
    % Clear the transient stream error before trying to read the next fragment.
    fclear(GXTXT_SCRIPT_BRIDGE_STATE.out);
    if(!ischar(piece)||isempty(piece)),pause(0.001);endif
  endwhile
endfunction

function release_callback_storage(event)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  ids=event.ids;if(ischar(ids)),ids={ids};endif
  if(strcmp(event.event,'callback_arguments_release'))
    for k=1:numel(ids)
      if(isKey(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays,ids{k})),remove(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays,ids{k});endif
    endfor
  else
    retained={};
    for k=1:numel(GXTXT_SCRIPT_BRIDGE_STATE.callback_paths)
      p=GXTXT_SCRIPT_BRIDGE_STATE.callback_paths{k};[parent,name,extension]=fileparts(p);
      if(any(strcmp([name extension],ids))),unlink(p);else,retained{end+1}=p;endif
    endfor
    GXTXT_SCRIPT_BRIDGE_STATE.callback_paths=retained;
  endif
endfunction

function value=callback_argument(wire,owner)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(!strcmp(wire.kind,'callback_array')),value=unpack_value(wire,0);return;endif
  id=wire.id;
  if(isfield(wire,'value'))
    if(isKey(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays,id)),error('GXTXT:ScriptCallback:Transport','Repeated constant argument definition');endif
    value=unpack_value(wire.value,0);
    if(!isnumeric(value)&&!islogical(value)),error('GXTXT:ScriptCallback:Transport','Constant argument is not numeric');endif
    GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays(id)=struct('owner',owner,'value',value);
  endif
  if(!isKey(GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays,id)),error('GXTXT:ScriptCallback:Transport','Unknown constant callback argument');endif
  entry=GXTXT_SCRIPT_BRIDGE_STATE.callback_arrays(id);
  if(!strcmp(entry.owner,owner)),error('GXTXT:ScriptCallback:Transport','Foreign constant callback argument');endif
  value=entry.value;
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
    for k=1:numel(raw),args{k}=callback_argument(raw{k},id);endfor
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
  elseif(isnumeric(value)&&isscalar(value)&&isreal(value))
    packed=struct('kind','numeric_scalar','value',num2str(value,17));
  elseif(isnumeric(value)||islogical(value))
    packed=struct('kind','numeric_array','shape',size(value));
    if(numel(value)>64||!isa(value,'double')||!isreal(value))
      if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE)&&isfield(GXTXT_SCRIPT_BRIDGE_STATE,'buffer_scope'))
        packed.binary=gxtxt_binary_resource_v1('write',GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,value);
        paths={fullfile(GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,packed.binary.resource_id)};
      else,error('GXTXT:ScriptBridge:Transport','typed array requires an active managed Bridge');endif
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

function value=unpack_value(wire,depth,arrays)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(nargin<3),arrays=containers.Map('KeyType','char','ValueType','any');endif
  if(depth>32),error('GXTXT:ScriptBridge:Transport','bridge result nesting exceeds 32');endif
  switch(wire.kind)
    case 'string',value=wire.value;
    case 'logical',value=logical(wire.value);
    case 'numeric_scalar',value=str2double(wire.value);
    case 'integer_scalar',value=unpack_integer(wire.value);
    case 'numeric_array_ref'
      if(!isfield(wire,'array_id')||!ischar(wire.array_id)||!isKey(arrays,wire.array_id)),error('GXTXT:ScriptBridge:Transport','unknown response array reference');endif
      value=arrays(wire.array_id);
    case 'numeric_array'
      shape=double(wire.shape(:)');
      if(isfield(wire,'binary'))
        if(!isequal(double(wire.binary.shape(:)'),shape)),error('GXTXT:ScriptBridge:Transport','binary result shape mismatch');endif
        value=gxtxt_binary_resource_v1('read',GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,wire.binary);
        unlink(fullfile(GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,wire.binary.resource_id));
      elseif(isfield(wire,'binary_path'))
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
      if(!isfield(wire,'binary')),value=reshape(values,shape);endif
      if(isfield(wire,'array_id'))
        if(!ischar(wire.array_id)||isKey(arrays,wire.array_id)||arrays.Count>=65536),error('GXTXT:ScriptBridge:Transport','invalid response array identity');endif
        arrays(wire.array_id)=value;
      endif
    case 'cell'
      items=wire.items;value=cell(1,numel(items));
      for k=1:numel(items)
        if(iscell(items)),item=items{k};else item=items(k);endif
        value{k}=unpack_value(item,depth+1,arrays);
      endfor
    case 'struct'
      value=struct();names=fieldnames(wire.fields);
      for k=1:numel(names),value.(names{k})=unpack_value(wire.fields.(names{k}),depth+1,arrays);endfor
    case 'struct_array'
      items=wire.items;value=struct([]);
      for k=1:numel(items)
        if(iscell(items)),item=items{k};else item=items(k);endif
        value(k)=unpack_value(item,depth+1,arrays);
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
