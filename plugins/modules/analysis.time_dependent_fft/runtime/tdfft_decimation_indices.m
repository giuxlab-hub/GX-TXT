function idx=tdfft_decimation_indices(n,maxn)
% Evenly decimate presentation points only; scientific Dataset content is unchanged.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isfinite(maxn)||maxn<=0||n<=maxn),idx=(1:n)';return;endif
  idx=unique(round(linspace(1,n,maxn)))';
endfunction
