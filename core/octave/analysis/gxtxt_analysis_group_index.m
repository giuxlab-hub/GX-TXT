% SPDX-License-Identifier: GPL-3.0-or-later
% Stable grouping helper used by Scientific Analysis Definition API v1.
function [vals,idx,kind] = gxtxt_analysis_group_index(group,n)
  if(nargin<2),n=numel(group);endif
  if(isempty(group))
    vals={'__global__'};idx={find(true(n,1))};kind='global';return;
  endif
  if(numel(group)!=n),error('GXTXT:AnalysisGroup','group length mismatch');endif
  if(iscell(group))
    kind='string';vals=unique(group,'stable');idx=cell(numel(vals),1);
    for i=1:numel(vals),idx{i}=find(strcmp(group,vals{i}));endfor
  elseif(isnumeric(group)||islogical(group))
    kind='numeric';finite=isfinite(group(:));q=unique(group(finite),'stable');vals=num2cell(q(:));idx=cell(numel(vals),1);
    for i=1:numel(vals),idx{i}=find(group(:)==vals{i});endfor
  else
    error('GXTXT:AnalysisGroup','group must be numeric, logical or cell-string');
  endif
endfunction
