function [M,changed]=pd_coordinate_capture(M,cfg,enabled)
% Refresh presentation snapshots without changing prepared canonical arrays.
% Captured snapshots travel with detached Clones; no original source is needed.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  lifetime=gxtxt_presentation_scope_v1(session);contexts=containers.Map();changed=false;
  for graph=enabled
    switch graph{1}
      case 'plot.dataset.xy',field='plot2d_xy';
      case 'plot.dataset.xy_region',field='plot2d_xy_region';
      case 'plot.dataset.xyz',field='plot3d';
      otherwise,continue;
    endswitch
    if(!isfield(M,field)),continue;endif
    P=M.(field);
    if(strcmp(field,'plot3d'))
      id=M.info.dataset_id;c=read_context(contexts,id);
      for role={'x','y','z','color','family'}
        key=[role{1} '_meta'];previous=P.(key);P.(key)=attach(previous,c);
        changed=changed||!isequaln(previous,P.(key));
      endfor
    else
      for k=1:numel(P.series)
        c=read_context(contexts,P.series(k).dataset_id);
        for key={'x_meta','meta'}
          previous=P.series(k).(key{1});P.series(k).(key{1})=attach(previous,c);
          changed=changed||!isequaln(previous,P.series(k).(key{1}));
        endfor
        if(isfield(P.series(k).data,'aux_meta'))
          for j=1:numel(P.series(k).data.aux_meta)
            previous=P.series(k).data.aux_meta{j};P.series(k).data.aux_meta{j}=attach(previous,c);
            changed=changed||!isequaln(previous,P.series(k).data.aux_meta{j});
          endfor
        endif
      endfor
    endif
    M.(field)=P;
  endfor
endfunction
function c=read_context(contexts,id)
  if(!isKey(contexts,id)),contexts(id)=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_read',{id});endif
  c=contexts(id);
endfunction
function m=attach(m,c)
  if(isfield(m,'coordinate_context')),m=rmfield(m,'coordinate_context');endif
  if(!isfield(m,'variable_id')||!isfield(c.variables,m.variable_id)),return;endif
  % Bound each axis snapshot to its own stable Variable ID; no names are keys.
  selected=struct();selected.(m.variable_id)=c.variables.(m.variable_id);c.variables=selected;
  m.coordinate_context=c;
endfunction
