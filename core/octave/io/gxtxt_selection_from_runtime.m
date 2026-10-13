function S = gxtxt_selection_from_runtime(runtime_cfg, key)
  % GX-TXT Dataset Selection API v1 helper.
  % Returns canonical dataset-coordinate bounds from [selection.<key>].
  % SPDX-License-Identifier: GPL-3.0-or-later
  if (nargin < 2 || isempty(key)), key = 'selection'; endif
  if (ischar(runtime_cfg) || isstring(runtime_cfg))
    cfg = gxtxt_ini_read(char(runtime_cfg));
  else
    cfg = runtime_cfg;
  endif
  p = ['selection.' char(key) '.'];
  S = struct();
  S.api_version = strtrim(gxtxt_ini_get(cfg,[p 'api_version'],'1'));
  S.id = strtrim(gxtxt_ini_get(cfg,[p 'id'],''));
  S.enabled = parse_bool(gxtxt_ini_get(cfg,[p 'enabled'],'0'));
  S.type = lower(strtrim(gxtxt_ini_get(cfg,[p 'type'],'')));
  S.source_dataset_id = strtrim(gxtxt_ini_get(cfg,[p 'source_dataset_id'],''));
  S.source_role = strtrim(gxtxt_ini_get(cfg,[p 'source_role'],'primary'));
  S.x_variable = strtrim(gxtxt_ini_get(cfg,[p 'x_variable'],''));
  S.x_variable_id = strtrim(gxtxt_ini_get(cfg,[p 'x_variable_id'],''));
  S.x_unit = strtrim(gxtxt_ini_get(cfg,[p 'x_unit'],''));
  S.x_min = parse_num(gxtxt_ini_get(cfg,[p 'x_min'],'NaN'));
  S.x_max = parse_num(gxtxt_ini_get(cfg,[p 'x_max'],'NaN'));
  S.x_coordinate_space = lower(strtrim(gxtxt_ini_get(cfg,[p 'x_coordinate_space'],'source')));
  S.x_display_unit = strtrim(gxtxt_ini_get(cfg,[p 'x_display_unit'],''));
  S.x_display_min = parse_num(gxtxt_ini_get(cfg,[p 'x_display_min'],'NaN'));
  S.x_display_max = parse_num(gxtxt_ini_get(cfg,[p 'x_display_max'],'NaN'));
  S.x_binding_count = parse_count(gxtxt_ini_get(cfg,[p 'x_binding_count'],'0'));
  S.x_bindings = split_tokens(gxtxt_ini_get(cfg,[p 'x_bindings'],''));
  S.y_variable = strtrim(gxtxt_ini_get(cfg,[p 'y_variable'],''));
  S.y_variable_id = strtrim(gxtxt_ini_get(cfg,[p 'y_variable_id'],''));
  S.y_unit = strtrim(gxtxt_ini_get(cfg,[p 'y_unit'],''));
  S.y_min = parse_num(gxtxt_ini_get(cfg,[p 'y_min'],'NaN'));
  S.y_max = parse_num(gxtxt_ini_get(cfg,[p 'y_max'],'NaN'));
  S.producer_module = strtrim(gxtxt_ini_get(cfg,[p 'producer_module'],''));
  S.producer_graph = strtrim(gxtxt_ini_get(cfg,[p 'producer_graph'],''));
  S.producer_variant = strtrim(gxtxt_ini_get(cfg,[p 'producer_variant'],''));
  if (S.enabled)
    if (!any(strcmp(S.type,{'x_range','rectangle'})))
      error('GXTXT:Selection','Unsupported Dataset Selection type: %s',S.type);
    endif
    if (isempty(S.source_dataset_id) || (isempty(S.x_variable) && isempty(S.x_variable_id)) || !isfinite(S.x_min) || !isfinite(S.x_max))
      error('GXTXT:Selection','Incomplete Dataset Selection runtime section: %s',key);
    endif
    if (strcmp(S.type,'rectangle') && ((isempty(S.y_variable) && isempty(S.y_variable_id)) || !isfinite(S.y_min) || !isfinite(S.y_max)))
      error('GXTXT:Selection','Rectangle selection is missing Y metadata: %s',key);
    endif
  endif
endfunction

function v = parse_num(s)
  v = str2double(strtrim(s));
endfunction

function b = parse_bool(s)
  q=lower(strtrim(s)); b=any(strcmp(q,{'1','true','yes','on'}));
endfunction


function n = parse_count(s)
  n = str2double(strtrim(s));
  if (!isfinite(n) || n < 0 || n != fix(n)), n = 0; endif
endfunction

function out = split_tokens(s)
  s = strtrim(s);
  if (isempty(s)), out = {}; else out = strsplit(s,';'); endif
endfunction
