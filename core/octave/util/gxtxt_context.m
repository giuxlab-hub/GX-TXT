function context=gxtxt_context()
% Return the current script execution context without storage paths.
% SPDX-License-Identifier: GPL-3.0-or-later
  context=gxtxt_script_bridge_internal('request',struct('action','context'));
endfunction
