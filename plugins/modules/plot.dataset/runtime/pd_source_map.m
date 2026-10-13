function sources=pd_source_map(cfg,info,enabled)
% Render Cache API v1 file-source map.
% 2-D Graph Series are dataset-native in 3.0.0, so their physical storage paths
% are deliberately not part of module data access or cache identity. Canonical
% Dataset IDs and Variable IDs participate in the 2-D preparation fingerprint.
% The preserved 3-D path still uses the Standard Module primary file source.
% SPDX-License-Identifier: GPL-3.0-or-later
  sources=struct();
  if(any(strcmp(enabled,'plot.dataset.xyz'))&&!isempty(info.source_path)),sources.primary=info.source_path;endif
endfunction
