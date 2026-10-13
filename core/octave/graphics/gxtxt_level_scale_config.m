% SPDX-License-Identifier: GPL-3.0-or-later
% Level Scale API v1: explicit, independent Y1/Y2/Z presentation state.
function spec = gxtxt_level_scale_config(cfg,graph,axis)
  if(!any(strcmp(axis,{'y','y2','z'}))),error('GXTXT:LevelScale','Axis must be y, y2 or z');endif
  prefix=['level_scale.' graph '.' axis '.'];
  spec=struct('scale',lower(strtrim(gxtxt_ini_get(cfg,[prefix 'scale'],'linear'))), ...
      'quantity_kind',lower(strtrim(gxtxt_ini_get(cfg,[prefix 'quantity_kind'],''))), ...
      'amplitude_basis',lower(strtrim(gxtxt_ini_get(cfg,[prefix 'amplitude_basis'],''))), ...
      'reference_value',str2double(gxtxt_ini_get(cfg,[prefix 'reference_value'],'')), ...
      'reference_unit',strtrim(gxtxt_ini_get(cfg,[prefix 'reference_unit'],'')), ...
      'zero_policy',lower(strtrim(gxtxt_ini_get(cfg,[prefix 'zero_policy'],'missing'))));
  if(!any(strcmp(spec.scale,{'linear','db','dbfs','fs'}))),error('GXTXT:LevelScale','Unknown level scale');endif
  if(strcmp(spec.scale,'linear')),return;endif
  if(!any(strcmp(spec.quantity_kind,{'amplitude','power'}))),error('GXTXT:LevelScale','Explicit quantity_kind required');endif
  if(strcmp(spec.quantity_kind,'amplitude')&&!any(strcmp(spec.amplitude_basis,{'peak','rms'}))),error('GXTXT:LevelScale','Explicit peak/rms basis required');endif
  if(!isfinite(spec.reference_value)||spec.reference_value<=0||isempty(spec.reference_unit)),error('GXTXT:LevelScale','Finite positive reference_value and reference_unit required');endif
  if(!any(strcmp(spec.zero_policy,{'missing','negative_infinity'}))),error('GXTXT:LevelScale','Unknown zero policy');endif
endfunction
