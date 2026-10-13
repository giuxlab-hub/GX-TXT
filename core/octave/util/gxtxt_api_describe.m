function descriptor=gxtxt_api_describe(api_id)
% Describe the script-callable operations of one public API.
% SPDX-License-Identifier: GPL-3.0-or-later
  request=struct('action','describe','api_id',api_id);
  descriptor=gxtxt_script_bridge_internal('request',request);
endfunction
