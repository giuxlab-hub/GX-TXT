% Explicit GX-TXT public-API preflight example.
% SPDX-License-Identifier: GPL-3.0-or-later

required = {
  'SOME_PUBLIC_API_v1',
  'ANOTHER_PUBLIC_API_v1'
};

for k = 1:numel(required)
  if (!gxtxt_api_has(required{k}))
    error('Missing required GX-TXT API: %s', required{k});
  endif
endfor

fprintf('All required APIs are available.\n');
