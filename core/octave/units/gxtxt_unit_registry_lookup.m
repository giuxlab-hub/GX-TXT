% SPDX-License-Identifier: GPL-3.0-or-later
% Runtime view of the public Unit Registry API v1.
function R = gxtxt_unit_registry_lookup(symbol)
  R=struct();
  path=getenv('GXTXT_UNIT_REGISTRY_FILE');
  if(isempty(path)||exist(path,'file')!=2),return;endif
  cfg=gxtxt_ini_read(path);
  n=str2double(gxtxt_ini_get(cfg,'unit_registry.count','0'));
  if(!isfinite(n)||n<0),return;endif
  for i=1:round(n)
    p=sprintf('unit.%d.',i);
    if(!strcmp(gxtxt_ini_get(cfg,[p 'symbol'],''),symbol)),continue;endif
    R=struct('symbol',symbol, ...
      'canonical_unit',gxtxt_ini_get(cfg,[p 'canonical_unit'],''), ...
      'conversion_kind',gxtxt_ini_get(cfg,[p 'conversion_kind'],'opaque'), ...
      'to_canonical',gxtxt_ini_get(cfg,[p 'to_canonical'],''), ...
      'from_canonical',gxtxt_ini_get(cfg,[p 'from_canonical'],''));
    return;
  endfor
endfunction
