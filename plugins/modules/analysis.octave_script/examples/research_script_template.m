% GX-TXT research-script template.
% SPDX-License-Identifier: GPL-3.0-or-later

ctx = gxtxt_context();

fprintf('GX-TXT module: %s\n', ctx.module_id);
fprintf('Script: %s\n', ctx.script_name);

% Inspect the Dataset aliases bound in the Analysis page.
disp(ctx.inputs);

% Discover public APIs currently available to scripts.
apis = gxtxt_api_list();
fprintf('Script-callable public APIs: %d\n', numel(apis));

% Use exact API IDs for reproducible work.
api_id = 'SOME_PUBLIC_API_v1';
if (!gxtxt_api_has(api_id))
  error('Required GX-TXT API is unavailable: %s', api_id);
endif

api = gxtxt_api_describe(api_id);
disp(api);

% Read the current manual of api_id and call only its documented operations.
% request = struct(...);
% result = gxtxt_api_call(api_id, 'documented_operation', {request});
