% SPDX-License-Identifier: GPL-3.0-or-later
% Analysis Source Dataset Metadata Runtime Extension v1.
%
% metadata = gxtxt_analysis_source_dataset_metadata(runtime_cfg, source_id)
%
% Returns Dataset Metadata for one Analysis Source without exposing CORE storage.
% Arbitrary Dataset Metadata keys remain strings in metadata.keys; they are never
% normalized into Octave struct field names, because distinct legal keys may
% otherwise collide after punctuation-to-underscore normalization.
function metadata = gxtxt_analysis_source_dataset_metadata(runtime_cfg, source_id)
  if (nargin < 2), error('GXTXT:DatasetMetadata','runtime_cfg and source_id are required'); endif
  cfg = normalize_runtime_local(runtime_cfg);
  source_id = strtrim(char(source_id));
  if (isempty(regexp(source_id,'^[A-Za-z][A-Za-z0-9_]*$','once')))
    error('GXTXT:DatasetMetadata','Invalid Analysis Source ID: %s',source_id);
  endif

  dataset_id = strtrim(gxtxt_ini_get(cfg,['analysis_source.' source_id '.dataset_metadata.dataset_id'],''));
  if (isempty(dataset_id) && strcmp(source_id,'primary'))
    dataset_id = strtrim(gxtxt_ini_get(cfg,'dataset.id',''));
  endif
  api_version = strtrim(gxtxt_ini_get(cfg,['analysis_source.' source_id '.dataset_metadata.api_version'],''));
  found = parse_bool_local(gxtxt_ini_get(cfg,['analysis_source.' source_id '.dataset_metadata.found'],'0'));
  count = parse_count_local(gxtxt_ini_get(cfg,['analysis_source.' source_id '.dataset_metadata.count'],'0'));

  keys = cell(1,count);
  values = cell(1,count);
  for i = 1:count
    prefix = sprintf('analysis_source.%s.dataset_metadata.%d.',source_id,i);
    key = gxtxt_ini_get(cfg,[prefix 'key'],'');
    if (isempty(key))
      error('GXTXT:DatasetMetadata','Dataset Metadata runtime entry %d for source %s has no key',i,source_id);
    endif
    if (any(strcmp(keys(1:i-1),key)))
      error('GXTXT:DatasetMetadata','Duplicate Dataset Metadata key in runtime for source %s: %s',source_id,key);
    endif
    keys{i} = key;
    values{i} = gxtxt_ini_get(cfg,[prefix 'value'],'');
  endfor

  metadata = struct();
  metadata.api_version = api_version;
  metadata.found = found;
  metadata.source_id = source_id;
  metadata.dataset_id = dataset_id;
  metadata.count = count;
  metadata.keys = keys;
  metadata.values = values;
endfunction

function cfg = normalize_runtime_local(runtime_cfg)
  if (ischar(runtime_cfg) || isstring(runtime_cfg))
    cfg = gxtxt_ini_read(char(runtime_cfg));
  elseif (isstruct(runtime_cfg))
    cfg = runtime_cfg;
  else
    error('GXTXT:DatasetMetadata','runtime_cfg must be a parsed runtime struct or runtime.ini path');
  endif
endfunction

function value = parse_bool_local(raw)
  s = lower(strtrim(char(raw)));
  value = any(strcmp(s,{'1','true','yes','on'}));
endfunction

function n = parse_count_local(raw)
  n = str2double(strtrim(char(raw)));
  if (!isfinite(n) || n < 0 || n != fix(n))
    error('GXTXT:DatasetMetadata','Invalid Dataset Metadata entry count: %s',char(raw));
  endif
endfunction
