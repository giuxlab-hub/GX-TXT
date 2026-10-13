function handle=gxtxt_callback_register(fun)
% Register a function for this script execution only.
% SPDX-License-Identifier: GPL-3.0-or-later
  handle=gxtxt_script_bridge_internal('register_callback',fun);
endfunction
