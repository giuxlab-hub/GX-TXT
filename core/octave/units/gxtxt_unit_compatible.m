% SPDX-License-Identifier: GPL-3.0-or-later
function tf = gxtxt_unit_compatible(a,b)
  if(strcmp(strtrim(a),strtrim(b))),tf=true;return;endif
  RA=gxtxt_unit_registry_lookup(a); RB=gxtxt_unit_registry_lookup(b);
  if(!isempty(fieldnames(RA)) && !isempty(RA.canonical_unit)),a=RA.canonical_unit;endif
  if(!isempty(fieldnames(RB)) && !isempty(RB.canonical_unit)),b=RB.canonical_unit;endif
  if(strcmp(a,b)),tf=true;return;endif
  A=gxtxt_unit_parse(a);B=gxtxt_unit_parse(b);
  if(!strcmp(A.kind,'linear')||!strcmp(B.kind,'linear'))
    tf=strcmp(A.kind,B.kind)&&strcmp(A.semantic,B.semantic);return;
  endif
  tf=isequal(orderfields(A.dims),orderfields(B.dims));
endfunction
