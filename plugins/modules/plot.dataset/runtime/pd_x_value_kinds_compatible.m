function ok=pd_x_value_kinds_compatible(role_a,kind_a,role_b,kind_b)
% Internal plot.dataset compatibility helper.
% value_kind is a representation detail; for elapsed time, an HMS field and
% a numeric duration are compatible when the caller has already verified unit
% compatibility. Other explicit mismatches remain incompatible.
% SPDX-License-Identifier: GPL-3.0-or-later
  ak=lower(strtrim(kind_a)); bk=lower(strtrim(kind_b));
  if(isempty(ak)||isempty(bk)||strcmp(ak,bk)),ok=true;return;endif
  ar=lower(strtrim(role_a)); br=lower(strtrim(role_b));
  if(strcmp(ar,'elapsed_time')&&strcmp(br,'elapsed_time'))
    allowed={'elapsed_time','number'};
    ok=any(strcmp(ak,allowed))&&any(strcmp(bk,allowed));
    return;
  endif
  ok=false;
endfunction
