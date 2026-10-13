function yes = gxtxt_api_require(requirements)
% Validate public Script Bridge API identity before scientific execution.
% SPDX-License-Identifier: GPL-3.0-or-later
  if (!iscell(requirements))
    requirements = {requirements};
  endif
  packed = cell(1, numel(requirements));
  for k = 1:numel(requirements)
    item = requirements{k};
    if (ischar(item))
      parts = regexp(strtrim(item), '^([A-Za-z0-9_]+)(?:@([0-9]+))?(?::([A-Za-z0-9._-]+))?(?:\+([A-Za-z0-9_|.-]+))?$', 'tokens', 'once');
      if (isempty(parts))
        error('GXTXT:ScriptBridge:InvalidArguments', 'Invalid required API declaration: %s', item);
      endif
      item = struct('api_id', parts{1});
      if (numel(parts) >= 2 && !isempty(parts{2}))
        item.api_version = str2double(parts{2});
      endif
      if (numel(parts) >= 3 && !isempty(parts{3}))
        item.provider_id = parts{3};
      endif
      if (numel(parts) >= 4 && !isempty(parts{4}))
        item.capabilities = regexp(parts{4}, '\|', 'split');
      endif
    endif
    if (!isstruct(item) || numel(item) != 1 || !isfield(item, 'api_id'))
      error('GXTXT:ScriptBridge:InvalidArguments', 'Each API requirement must declare api_id');
    endif
    packed{k} = gxtxt_script_bridge_internal('pack', item);
  endfor
  yes = gxtxt_script_bridge_internal('request', struct('action', 'require', 'requirements', {packed}));
endfunction
