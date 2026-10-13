% SPDX-License-Identifier: GPL-3.0-or-later
% Apply an explicit level scale after ordinary display-unit conversion.
function [out,label] = gxtxt_level_scale_apply(values,unit,spec)
  out=values;label='';
  if(strcmp(spec.scale,'linear')),return;endif
  if(!isnumeric(values)||!isreal(values)),error('GXTXT:LevelScale','Real numeric values required');endif
  if(isempty(unit)||!gxtxt_unit_compatible(unit,spec.reference_unit)),error('GXTXT:LevelScale','Reference unit is incompatible with axis display unit');endif
  if(any(strcmp(unit,{'dB','dBFS','FS'}))),error('GXTXT:LevelScale','Already-level-valued input cannot be transformed again');endif
  ref=gxtxt_unit_convert(spec.reference_value,spec.reference_unit,unit);
  if(!isfinite(ref)||ref<=0),error('GXTXT:LevelScale','Converted reference must be finite and positive');endif
  out=nan(size(values));finite=isfinite(values);
  if(strcmp(spec.quantity_kind,'amplitude'))
    magnitude=abs(values);
    valid=finite;
  else
    magnitude=values;
    valid=finite & values>=0;
  endif
  if(strcmp(spec.scale,'fs'))
    if(strcmp(spec.quantity_kind,'amplitude')),out(valid)=values(valid)./ref;
    else out(valid)=values(valid)./ref;endif
  else
    pos=valid & magnitude>0;
    mult=20;if(strcmp(spec.quantity_kind,'power')),mult=10;endif
    out(pos)=mult.*log10(magnitude(pos)./ref);
    if(strcmp(spec.zero_policy,'negative_infinity')),out(valid & magnitude==0)=-Inf;endif
  endif
  basis='';if(strcmp(spec.quantity_kind,'amplitude')),basis=[' ' spec.amplitude_basis];endif
  if(strcmp(spec.scale,'db')),scale='dB';elseif(strcmp(spec.scale,'dbfs')),scale='dBFS';else scale='FS';endif
  label=sprintf('%s re %.6g %s%s',scale,spec.reference_value,spec.reference_unit,basis);
endfunction
