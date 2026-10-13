% GX-TXT Octave Script Bridge discovery example.
% SPDX-License-Identifier: GPL-3.0-or-later

info = gxtxt_bridge_info();
disp(info);

ctx = gxtxt_context();
disp(ctx);

apis = gxtxt_api_list();
fprintf('Script-callable GX-TXT public APIs: %d\n', numel(apis));

% The operation names and argument/result semantics come from the manual of the
% public API being used. The bridge itself does not define Dataset/Plot/etc.
%
% Example pattern:
%
% api_id = 'SOME_PUBLIC_API_v1';
% if (!gxtxt_api_has(api_id))
%   error('Required GX-TXT API is unavailable: %s', api_id);
% endif
% description = gxtxt_api_describe(api_id);
% disp(description);
% if (gxtxt_api_has_operation(api_id, 'documented_operation'))
%   request = struct('example', 1);
%   result = gxtxt_api_call(api_id, 'documented_operation', {request});
%   disp(result);
% endif
