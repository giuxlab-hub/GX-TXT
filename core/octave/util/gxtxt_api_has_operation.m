function yes=gxtxt_api_has_operation(api_id,operation)
% Test exact registration of one public API operation.
% SPDX-License-Identifier: GPL-3.0-or-later
  request=struct('action','has_operation','api_id',api_id,'operation',operation);
  yes=gxtxt_script_bridge_internal('request',request);
endfunction
