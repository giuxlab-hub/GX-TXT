function result=gxtxt_api_call(api_id,operation,args)
% Invoke only an operation registered by its public API provider.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin!=3||!ischar(api_id)||!ischar(operation)||!iscell(args))
    error('GXTXT:ScriptBridge:InvalidArguments','gxtxt_api_call requires API ID, operation, and a cell array of arguments');
  endif
  packed=cell(1,numel(args));paths={};
  unwind_protect
    for k=1:numel(args)
      [packed{k},new_paths]=gxtxt_script_bridge_internal('pack',args{k});
      paths=[paths new_paths];
    endfor
    request=struct('action','call','api_id',api_id,'operation',operation);
    request.args=packed;
    result=gxtxt_script_bridge_internal('request',request);
  unwind_protect_cleanup
    for k=1:numel(paths),try unlink(paths{k});catch;end_try_catch;endfor
  end_unwind_protect
endfunction
