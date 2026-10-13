function [key,is_numeric]=pd_family_key(raw,numeric_mode)
% Canonicalize a Family/group value without changing the source dataset.
% Numeric families use a canonical numeric key so 1, 1.0 and 1e0 are one
% scientific family. Categorical families preserve trimmed source text.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<2),numeric_mode=false;endif
  key=strtrim(raw);
  v=str2double(key);is_numeric=isfinite(v);
  if(numeric_mode && is_numeric),key=sprintf('%.17g',v);endif
endfunction
