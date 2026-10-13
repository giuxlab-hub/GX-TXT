function gxtxt_callback_release(handle)
% Release an execution-scoped registered callback.
% SPDX-License-Identifier: GPL-3.0-or-later
  gxtxt_script_bridge_internal('release_callback',handle);
endfunction
