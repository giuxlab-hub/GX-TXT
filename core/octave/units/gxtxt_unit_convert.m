% SPDX-License-Identifier: GPL-3.0-or-later
function out = gxtxt_unit_convert(value,from_unit,to_unit)
  if(strcmp(strtrim(from_unit),strtrim(to_unit))),out=value;return;endif
  A=gxtxt_unit_registry_lookup(from_unit); B=gxtxt_unit_registry_lookup(to_unit);
  if(!isempty(fieldnames(A)) && !isempty(A.canonical_unit))
    value=gxtxt_unit_formula_eval(A.to_canonical,value);
    from_unit=A.canonical_unit;
  endif
  target=to_unit;
  if(!isempty(fieldnames(B)) && !isempty(B.canonical_unit)),target=B.canonical_unit;endif
  if(strcmp(from_unit,target)),intermediate=value;else
    P=gxtxt_unit_parse(from_unit);Q=gxtxt_unit_parse(target);
    if(!strcmp(P.kind,'linear')||!strcmp(Q.kind,'linear'))
      error('GXTXT:Unit','semantic/non-linear units are identity-only: %s -> %s',from_unit,target);
    endif
    if(!isequal(orderfields(P.dims),orderfields(Q.dims))),error('GXTXT:Unit','incompatible units: %s -> %s',from_unit,target);endif
    intermediate=value.*(P.scale/Q.scale);
  endif
  if(!isempty(fieldnames(B)) && !isempty(B.canonical_unit))
    out=gxtxt_unit_formula_eval(B.from_canonical,intermediate);
  else out=intermediate;endif
endfunction
