% SPDX-License-Identifier: GPL-3.0-or-later
% Public Elapsed Time Requested-Unit API v1 binding.
% Canonical elapsed_time values are already seconds.  Never use source_unit as
% from_unit here: doing so would reinterpret source provenance after parsing.
function [out,target_unit] = gxtxt_elapsed_time_convert(values,target_unit)
  if(nargin<2 || isempty(target_unit)),target_unit='s';endif
  target_unit=strtrim(target_unit);
  if(isempty(target_unit)),target_unit='s';endif
  try
    compatible=gxtxt_unit_compatible('s',target_unit);
  catch err
    if(strcmp(err.identifier,'GXTXT:Unit'))
      compatible=false;
    else
      rethrow(err);
    endif
  end_try_catch
  if(!compatible)
    error('GXTXT:ElapsedTimeUnit','unknown or incompatible requested elapsed-time unit: %s',target_unit);
  endif
  out=gxtxt_unit_convert(values,'s',target_unit);
endfunction
