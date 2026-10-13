% SPDX-License-Identifier: GPL-3.0-or-later
% Stable fingerprint of a Scientific Analysis source_map struct.
% Field order is normalized. Values are expected to be trusted local file paths.
function fp = gxtxt_render_cache_source_fingerprint(source_map)
  if(nargin<1||isempty(source_map)),fp=gxtxt_render_cache_fingerprint({'sources:none'});return;endif
  if(!isstruct(source_map)),error('GXTXT:RenderCache','source_map must be a struct');endif
  names=sort(fieldnames(source_map));parts={'GXTXT_SOURCE_MAP_V1'};
  for i=1:numel(names)
    k=names{i};path=source_map.(k);
    if(!ischar(path)),error('GXTXT:RenderCache','source_map.%s must be a path string',k);endif
    path=strtrim(path);
    if(isempty(path)),h='missing';else h=gxtxt_render_cache_file_fingerprint(path);endif
    parts{end+1}=k;parts{end+1}=path;parts{end+1}=h; %#ok<AGROW>
  endfor
  fp=gxtxt_render_cache_fingerprint(parts);
endfunction
