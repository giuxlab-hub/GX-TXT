function [peak_values,mean_values]=tdfft_reduce_values(values,P,numeric_api)
% Reduce one spectrum onto a common display frequency grid.
% peak_values preserves narrow maxima; mean_values preserves local mean level.
% SPDX-License-Identifier: GPL-3.0-or-later
  v=double(values(:));
  if(numel(v)!=P.source_bins),error('analysis.time_dependent_fft: display reduction source size mismatch');endif
  peak_values=zeros(P.target_bins,1);mean_values=zeros(P.target_bins,1);
  for j=1:P.target_bins
    q=v(P.starts(j):P.ends(j));s=feval(numeric_api,'reduce_summary',q);
    peak_values(j)=s.max;mean_values(j)=s.mean;
  endfor
endfunction
