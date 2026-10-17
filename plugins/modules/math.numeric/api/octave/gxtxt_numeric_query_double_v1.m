% Retained-query coordinates use binary64; integer conversion must be explicit.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_query_double_v1(values)
  if(isinteger(values)&&(any(values(:)>cast(flintmax,class(values)))||any(values(:)<cast(-flintmax,class(values)))))
    error('GXTXT:Numeric:Query','Integer query values outside the exact binary64 range require an explicit scientific conversion');
  endif
  out=double(values);
endfunction
