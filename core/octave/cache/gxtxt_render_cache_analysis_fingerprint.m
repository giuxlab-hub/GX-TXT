% SPDX-License-Identifier: GPL-3.0-or-later
% Fingerprint of an Analysis Definition descriptor plus effective parameters.
function fp = gxtxt_render_cache_analysis_fingerprint(definition_path,parameters)
  if(nargin<2),parameters=struct();endif
  dh=gxtxt_render_cache_file_fingerprint(definition_path);
  ph=gxtxt_render_cache_parameter_fingerprint(parameters);
  fp=gxtxt_render_cache_fingerprint({'GXTXT_ANALYSIS_V1',definition_path,dh,ph});
endfunction
