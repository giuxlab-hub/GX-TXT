function W=pd_2d_preparation_window(cfg,graph,V,G)
% Resolve an X pre-read window only when one source X binding is authoritative
% for every active Graph Series. Heterogeneous X bindings share a display axis
% but remain independent scientific source domains, so graph limits must not be
% translated into source row ranges for them.
% SPDX-License-Identifier: GPL-3.0-or-later
  W=pd_2d_graph_window(cfg,graph,V);
  W.range_safe=false;W.reason='no_window';
  if(!isfield(W,'enabled')||!W.enabled),return;endif
  if(nargin<4||isempty(G)),W.enabled=false;W.reason='no_series';return;endif
  ds=strtrim(G(1).dataset_id);xid=strtrim(G(1).x_variable_id);
  for k=2:numel(G)
    if(!strcmp(strtrim(G(k).dataset_id),ds)||!strcmp(strtrim(G(k).x_variable_id),xid))
      W.enabled=false;W.range_safe=false;W.reason='heterogeneous_x_bindings';
      return;
    endif
  endfor
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(!isempty(session))
    lifetime=gxtxt_presentation_scope_v1(session);
    context=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_read',{ds});
    if(isfield(context.variables,xid)&&!isempty(context.variables.(xid).source.canonical_unit))
      % The old range optimizer understands registry units, not a declared
      % per-Variable relation. Read canonical data normally and crop only the
      % rendered view; never discard rows using a different inverse relation.
      W.enabled=false;W.range_safe=false;W.reason='declared_coordinate_relation';return;
    endif
  endif
  W.range_safe=true;W.reason='shared_x_binding';
endfunction
