function info=gxtxt_bridge_info()
% Return the active OCTAVE_SCRIPT_BRIDGE_API_v1 descriptor.
% SPDX-License-Identifier: GPL-3.0-or-later
  info=gxtxt_script_bridge_internal('request',struct('action','info'));
endfunction
