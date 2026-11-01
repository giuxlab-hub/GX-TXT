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
      declaration = strtrim(item);
      if (isempty(regexp(declaration, '^[A-Za-z0-9_]+(?:@[0-9]+)?(?::[A-Za-z0-9._-]+)?(?:\+[A-Za-z0-9_|.-]+)?$', 'once')))
        error('GXTXT:ScriptBridge:InvalidArguments', 'Invalid required API declaration: %s', item);
      endif
      % Octave omits unmatched optional captures. Extract each labelled field
      % separately so a missing version/provider cannot shift capabilities.
      item = struct('api_id', regexp(declaration, '^[A-Za-z0-9_]+', 'match', 'once'));
      version = regexp(declaration, '@([0-9]+)', 'tokens', 'once');
      provider = regexp(declaration, ':([A-Za-z0-9._-]+)', 'tokens', 'once');
      capabilities = regexp(declaration, '\+([A-Za-z0-9_|.-]+)', 'tokens', 'once');
      if (!isempty(version))
        item.api_version = str2double(version{1});
      endif
      if (!isempty(provider))
        item.provider_id = provider{1};
      endif
      if (!isempty(capabilities))
        item.capabilities = regexp(capabilities{1}, '\|', 'split');
      endif
    endif
    if (!isstruct(item) || numel(item) != 1 || !isfield(item, 'api_id'))
      error('GXTXT:ScriptBridge:InvalidArguments', 'Each API requirement must declare api_id');
    endif
    packed{k} = gxtxt_script_bridge_internal('pack', item);
  endfor
  yes = gxtxt_script_bridge_internal('request', struct('action', 'require', 'requirements', {packed}));
endfunction
