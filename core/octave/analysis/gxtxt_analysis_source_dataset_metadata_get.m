% SPDX-License-Identifier: GPL-3.0-or-later
% Exact-key lookup for Analysis Source Dataset Metadata Runtime Extension v1.
%
% [value, found] = gxtxt_analysis_source_dataset_metadata_get(runtime_cfg, source_id, key)
% [value, found, metadata] = ...
%
% found distinguishes a missing field from a present field whose value is ''.
function [value, found, metadata] = gxtxt_analysis_source_dataset_metadata_get(runtime_cfg, source_id, key, default_value)
  if (nargin < 3), error('GXTXT:DatasetMetadata','runtime_cfg, source_id and key are required'); endif
  if (nargin < 4), default_value = ''; endif
  metadata = gxtxt_analysis_source_dataset_metadata(runtime_cfg,source_id);
  key = char(key);
  index = find(strcmp(metadata.keys,key),1);
  if (isempty(index))
    value = default_value;
    found = false;
  else
    value = metadata.values{index};
    found = true;
  endif
endfunction
