function yes=gxtxt_api_has(api_id)
% Test exact registration of a public GX-TXT API ID.
% SPDX-License-Identifier: GPL-3.0-or-later
  request=struct('action','has','api_id',api_id);
  yes=gxtxt_script_bridge_internal('request',request);
endfunction
