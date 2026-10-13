function fp=pd_series_prep_fingerprint(session,G,aux,reduction,target,threshold,window,presentation)
% Only inputs that change prepared values or source-row identities belong here.
% Presentation and display order are assembled from the current PlotSpec.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(strcmp(reduction,'none')||(strcmp(reduction,'auto')&&isfield(G,'dataset_row_count')&&isfinite(G.dataset_row_count)&&G.dataset_row_count<=threshold))
    target=0;threshold=0;
  endif
  p={'PLOT_DATASET_SERIES_PREP_V1',G.dataset_id,G.x_variable_id,G.y_variable_id, ...
     G.secondary_variable_id,G.ordering_variable_id,G.alignment_mode,G.manual_offset_seconds, ...
     G.x_unit,G.x_value_kind,G.x_value_format,G.x_semantic_role,G.x_time_reference,G.x_time_origin, ...
     reduction,target,threshold};
  for i=1:numel(aux),p{end+1}=aux{i};endfor
  for i=1:numel(G.row_filters)
    f=G.row_filters{i};p{end+1}=f.filter_variable_id;p{end+1}=f.predicate;p{end+1}=f.dtype;
    for name={'value','lower','upper'}
      if(isfield(f,name{1})),p{end+1}=f.(name{1});endif
    endfor
    if(isfield(f,'values'))
      p{end+1}=numel(f.values);
      for j=1:numel(f.values),p{end+1}=f.values{j};endfor
    endif
  endfor
  if(isstruct(window)&&isfield(window,'enabled')&&window.enabled)
    p=[p {'window',window.source,window.x_min,window.x_max,window.display_unit}];
  endif
  if(isfield(presentation,'kind')&&any(strcmp(lower(strtrim(presentation.kind)),{'histogram','box_whisker'})))
    p{end+1}='unreduced_distribution';
  endif
  source=dir(G.path);
  if(isempty(source)),error('plot.dataset: Dataset source for %s is unavailable',G.dataset_id);endif
  p=[p {source.bytes,source.datenum}];
  if(isfield(G,'scientific_dataset_identity')&&!isempty(G.scientific_dataset_identity))
    p=[p {G.scientific_dataset_identity}];
  else
    registry=dir(fullfile(session,'metadata','datasets.ini'));
    if(!isempty(registry)),p=[p {registry.bytes,registry.datenum}];endif
  endif
  fp=gxtxt_render_cache_fingerprint(p);
endfunction
