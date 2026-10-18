function gxtxt_debug_capture(__gx_dbg_destination, __gx_dbg_token, __gx_dbg_sha, __gx_dbg_context_stack, __gx_dbg_context_active)
% Observe the actual paused native frame; never evaluate researcher expressions.
% Prefix inspector locals to avoid shadowing names in an Octave debug context.
% SPDX-License-Identifier: GPL-3.0-or-later
  if (nargin >= 5)
    __gx_dbg_stack = __gx_dbg_context_stack;
    __gx_dbg_active = __gx_dbg_context_active;
  else
    [__gx_dbg_stack, __gx_dbg_active] = dbstack('-completenames');
    if (!isempty(__gx_dbg_stack)), __gx_dbg_stack=__gx_dbg_stack(2:end); endif
    __gx_dbg_active = __gx_dbg_active - 1;
  endif
  __gx_dbg_info = evalin('caller','whos');
  __gx_dbg_locals=struct();__gx_dbg_globals=struct();
  for __gx_dbg_k=1:min(numel(__gx_dbg_info),128)
    __gx_dbg_name=__gx_dbg_info(__gx_dbg_k).name;
    if (isempty(regexp(__gx_dbg_name,'^[A-Za-z][A-Za-z0-9_]*$','once')) || strncmp(__gx_dbg_name,'__gx',4)), continue; endif
    __gx_dbg_item=struct('type',__gx_dbg_info(__gx_dbg_k).class,'shape',__gx_dbg_info(__gx_dbg_k).size,'value','Opaque object; no display method called','truncated',prod(__gx_dbg_info(__gx_dbg_k).size)>12);
    try
      if (any(strcmp(__gx_dbg_info(__gx_dbg_k).class,{'double','single','int8','int16','int32','int64','uint8','uint16','uint32','uint64','logical','char','struct'})))
        __gx_dbg_value=evalin('caller',__gx_dbg_name);
        __gx_dbg_class=builtin('class',__gx_dbg_value);
        if (!strcmp(__gx_dbg_class,__gx_dbg_item.type))
          __gx_dbg_item.value='Variable changed during native observation; refresh its frame';
        elseif (strcmp(__gx_dbg_class,'char'))
          __gx_dbg_item.value=__gx_dbg_value(1:min(numel(__gx_dbg_value),512));
        elseif (strcmp(__gx_dbg_class,'struct'))
          __gx_dbg_fields=fieldnames(__gx_dbg_value);__gx_dbg_item.value=__gx_dbg_fields(1:min(numel(__gx_dbg_fields),12));
        elseif (!isreal(__gx_dbg_value))
          __gx_dbg_item.value=struct('real',real(__gx_dbg_value(1:min(numel(__gx_dbg_value),12))),'imaginary',imag(__gx_dbg_value(1:min(numel(__gx_dbg_value),12))));
        else
          __gx_dbg_item.value=__gx_dbg_value(1:min(numel(__gx_dbg_value),12));
        endif
      endif
    catch
      __gx_dbg_item.value='Native value unavailable at this stopped frame';
    end_try_catch
    __gx_dbg_locals.(__gx_dbg_name)=__gx_dbg_item;
    if (__gx_dbg_info(__gx_dbg_k).global), __gx_dbg_globals.(__gx_dbg_name)=__gx_dbg_item; endif
  endfor
  __gx_dbg_record=struct('schema','gxtxt.script_debug.v1','backend','gnu_octave_native','state','PAUSED','source_sha256',__gx_dbg_sha,'token',__gx_dbg_token,'stack',__gx_dbg_stack,'locals',__gx_dbg_locals,'globals',__gx_dbg_globals,'line',0,'function','');
  % dbstack's active index includes this observer frame. Do not assume that
  % the first stopped frame is the frame selected through dbup/dbdown.
  __gx_dbg_selected = max(1, min(numel(__gx_dbg_stack), __gx_dbg_active));
  __gx_dbg_record.selected_frame = __gx_dbg_selected - 1;
  __gx_dbg_record.native_active_index = __gx_dbg_active;
  if (!isempty(__gx_dbg_stack))
    __gx_dbg_record.line=__gx_dbg_stack(__gx_dbg_selected).line;
    __gx_dbg_record.function=__gx_dbg_stack(__gx_dbg_selected).name;
    __gx_dbg_record.execution_line=__gx_dbg_stack(1).line;
    __gx_dbg_record.execution_function=__gx_dbg_stack(1).name;
  endif
  __gx_dbg_temporary=[__gx_dbg_destination '.pending'];__gx_dbg_fd=fopen(__gx_dbg_temporary,'w');
  if (__gx_dbg_fd<0),error('Cannot write managed debugger observation');endif
  unwind_protect
    fputs(__gx_dbg_fd,jsonencode(__gx_dbg_record));
  unwind_protect_cleanup
    fclose(__gx_dbg_fd);
  end_unwind_protect
  [__gx_dbg_ok,__gx_dbg_message]=movefile(__gx_dbg_temporary,__gx_dbg_destination,'f');if (!__gx_dbg_ok),error(__gx_dbg_message);endif
endfunction
