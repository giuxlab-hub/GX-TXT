function G=tdfft_reduce_grid(D,window_indices,max_windows,max_frequency_bins,mode,numeric_api)
% Prepare a bounded rectangular rendering grid from the compact render cache.
% No scientific Dataset values are changed; this function only prepares pixels/vertices.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isfield(D,'plot_cache')),error('analysis.time_dependent_fft: render cache has no plot_cache payload');endif
  C=D.plot_cache;idx=window_indices(:);if(isempty(idx)),error('analysis.time_dependent_fft: empty window selection');endif
  if(any(idx<1)||any(idx>D.window_count)),error('analysis.time_dependent_fft: invalid render window index');endif
  mode=lower(strtrim(mode));if(!any(strcmp(mode,{'peak','mean'}))),mode='peak';endif
  if(strcmp(mode,'mean')),Z=C.mean(idx,:);else Z=C.peak(idx,:);endif
  t=D.time_centers(idx);f=C.frequency(:);

  % Frequency aggregation first. It keeps a common monotonic grid.
  if(max_frequency_bins>0 && numel(f)>max_frequency_bins)
    plan=tdfft_reduction_plan(numel(f),max_frequency_bins,1);
    Z2=zeros(size(Z,1),plan.target_bins);f2=zeros(plan.target_bins,1);
    for j=1:plan.target_bins
      a=plan.starts(j);b=plan.ends(j);fs=feval(numeric_api,'reduce_summary',f(a:b));f2(j)=fs.mean;
      zs=feval(numeric_api,'reduce_summary',Z(:,a:b),struct('dimension',2));
      if(strcmp(mode,'mean')),Z2(:,j)=zs.mean;else Z2(:,j)=zs.max;endif
    endfor
    Z=Z2;f=f2;
  endif

  % Time aggregation is used only when the selected windows exceed the display budget.
  if(max_windows>0 && numel(t)>max_windows)
    plan=tdfft_reduction_plan(numel(t),max_windows,1);
    Z2=zeros(plan.target_bins,size(Z,2));t2=zeros(plan.target_bins,1);members=cell(plan.target_bins,1);
    for j=1:plan.target_bins
      a=plan.starts(j);b=plan.ends(j);ts=feval(numeric_api,'reduce_summary',t(a:b));t2(j)=ts.mean;members{j}=idx(a:b);
      zs=feval(numeric_api,'reduce_summary',Z(a:b,:),struct('dimension',1));
      if(strcmp(mode,'mean')),Z2(j,:)=zs.mean;else Z2(j,:)=zs.max;endif
    endfor
    Z=Z2;t=t2;source_groups=members;
  else
    source_groups=cell(numel(idx),1);for j=1:numel(idx),source_groups{j}=idx(j);endfor
  endif
  G=struct('time',t(:),'frequency',f(:),'Z',Z,'source_groups',{source_groups},'reduction',mode);
endfunction
