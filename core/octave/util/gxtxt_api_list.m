function apis=gxtxt_api_list()
% List registered script-callable public GX-TXT APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
  apis=gxtxt_script_bridge_internal('request',struct('action','list'));
endfunction
