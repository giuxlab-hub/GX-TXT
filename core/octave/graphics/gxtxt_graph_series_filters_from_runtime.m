function filters=gxtxt_graph_series_filters_from_runtime(cfg,prefix)
% Decode the public Graph Series row-filter descriptor from a runtime INI.
% SPDX-License-Identifier: GPL-3.0-or-later
  count=str2double(gxtxt_ini_get(cfg,[prefix 'filter_count'],'0'));
  if(!isfinite(count)||count<0||count!=fix(count)),error('GXTXT:GraphSeries','invalid row-filter count');endif
  filters=cell(1,count);
  for j=1:count
    q=[prefix sprintf('filter_%d_',j)];
    f=struct('filter_variable_id',gxtxt_ini_get(cfg,[q 'filter_variable_id'],''), ...
      'predicate',gxtxt_ini_get(cfg,[q 'predicate'],''),'dtype',gxtxt_ini_get(cfg,[q 'dtype'],''), ...
      'value',gxtxt_ini_get(cfg,[q 'value'],''),'lower',gxtxt_ini_get(cfg,[q 'lower'],''), ...
      'upper',gxtxt_ini_get(cfg,[q 'upper'],''),'values',{{}});
    if(isempty(f.filter_variable_id)||isempty(f.predicate)||isempty(f.dtype)),error('GXTXT:GraphSeries','incomplete row filter');endif
    if(strcmp(f.predicate,'in_set'))
      n=str2double(gxtxt_ini_get(cfg,[q 'value_count'],'0'));
      if(!isfinite(n)||n<1||n!=fix(n)),error('GXTXT:GraphSeries','invalid in_set value count');endif
      for k=1:n,f.values{end+1}=gxtxt_ini_get(cfg,[q sprintf('value_%d',k)],'');endfor
    endif
    filters{j}=f;
  endfor
endfunction
