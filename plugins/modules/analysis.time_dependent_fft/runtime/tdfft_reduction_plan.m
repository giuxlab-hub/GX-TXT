function P=tdfft_reduction_plan(bin_count,target_bins,df)
% Build a deterministic common-frequency display reduction plan.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(bin_count<1),error('analysis.time_dependent_fft: bin_count must be positive');endif
  if(target_bins<=0||target_bins>=bin_count),target_bins=bin_count;endif
  target_bins=max(1,min(bin_count,fix(target_bins)));
  edges=round(linspace(0,bin_count,target_bins+1));
  starts=zeros(target_bins,1);ends=zeros(target_bins,1);frequency=zeros(target_bins,1);
  prev=0;
  for j=1:target_bins
    a=max(prev+1,edges(j)+1);b=max(a,edges(j+1));b=min(bin_count,b);
    starts(j)=a;ends(j)=b;frequency(j)=(((a+b)/2)-1)*df;prev=b;
  endfor
  ends(end)=bin_count;frequency(end)=(((starts(end)+ends(end))/2)-1)*df;
  P=struct('starts',starts,'ends',ends,'frequency',frequency,'source_bins',bin_count,'target_bins',target_bins,'df',df);
endfunction
