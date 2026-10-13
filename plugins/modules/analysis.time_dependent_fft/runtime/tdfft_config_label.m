function s=tdfft_config_label(cfg,graph,key,base,unit)
% Resolve a user plot label, where "auto" means quantity + display unit.
% SPDX-License-Identifier: GPL-3.0-or-later
  s=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' key],'auto'));
  if(isempty(s)||strcmpi(s,'auto')),s=tdfft_axis_label(base,unit);endif
endfunction
