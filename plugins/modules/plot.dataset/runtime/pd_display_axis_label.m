% Keep an explicit source-unit suffix consistent with display-unit conversion.
% SPDX-License-Identifier: GPL-3.0-or-later
function label=pd_display_axis_label(label,source_unit,display_unit)
  source_unit=strtrim(source_unit);display_unit=strtrim(display_unit);
  if(isempty(source_unit)||strcmp(source_unit,display_unit)),return;endif
  suffix=[' [' source_unit ']'];
  if(numel(label)<numel(suffix)||!strcmp(label(end-numel(suffix)+1:end),suffix)),return;endif
  label=label(1:end-numel(suffix));
  if(!isempty(display_unit)),label=[label ' [' display_unit ']'];endif
endfunction
