function pd_coordinate_view(ax,which,metas,target,cfg,graph,axis_key,declared,panel_id,level)
% Dataset factors alter a freshly fitted viewport, never prepared samples.
% Explicit graph bounds own their axis. Conflicting shared policies fail clearly.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(isempty(ax)||isempty(metas)),return;endif
  if(nargin<8),declared=struct();endif
  if(nargin<9),panel_id='';endif
  if(nargin<10),level=struct('scale','linear');endif
  active=false;
  for k=1:numel(metas)
    m=metas{k};if(isfield(m,'coordinate_context'))
      c=m.coordinate_context;active=active||c.variables.(m.variable_id).view_factor!=1;
    endif
  endfor
  if(!active),return;endif
  status='dataset_view';
  if(manual_bounds(cfg,graph,axis_key,declared,panel_id))
    setappdata(ax,['gxtxt_' which '_coordinate_view_status'],'explicit_graph_range');return;
  endif
  if(!strcmp(level.scale,'linear'))
    error('plot.dataset: Dataset magnification on %s requires a linear level scale or explicit graph limits; a magnitude level has no unique signed canonical inverse',axis_key);
  endif
  reference=get(ax,[which 'lim']);candidate=[];
  for k=1:numel(metas)
    m=metas{k};view=reference;
    if(isfield(m,'coordinate_context'))
      view=gxtxt_coordinate_view_v1(m.coordinate_context,m.variable_id,reference,target);
    endif
    if(isempty(candidate)),candidate=view;
    elseif(norm(candidate-view,Inf)>1e-10*max([1 abs(candidate) abs(view)]))
      error('plot.dataset: conflicting Dataset magnification/pivots on shared %s axis; use matching policies, separate axes/panels, or explicit graph limits',axis_key);
    endif
  endfor
  if(strcmp(get(ax,[which 'scale']),'log')&&any(candidate<=0))
    error('plot.dataset: Dataset magnification crosses the logarithmic %s domain; adjust its canonical pivot or explicit graph limits',axis_key);
  endif
  set(ax,[which 'lim'],candidate);
  setappdata(ax,['gxtxt_' which '_coordinate_view_status'],status);
  setappdata(ax,['gxtxt_' which '_coordinate_reference_range'],reference);
endfunction
function yes=manual_bounds(cfg,graph,axis_key,declared,panel_id)
  yes=false;prefix=['axis.' graph '.'];enabled=str2double(gxtxt_ini_get(cfg,[prefix 'enabled'],'0'));
  prefixes={['plot.' graph '.']};
  if(isfinite(enabled)&&enabled!=0)
    prefixes{end+1}=prefix;
    count=str2double(gxtxt_ini_get(cfg,[prefix 'panel_count'],'0'));
    if(isfinite(count))
      for k=1:count
        if((strcmp(axis_key,'x')&&isempty(panel_id))||(!isempty(panel_id)&&strcmp(gxtxt_ini_get(cfg,sprintf('%spanel%d_name',prefix,k),''),panel_id)))
          prefixes{end+1}=sprintf('%spanel%d_',prefix,k);
        endif
      endfor
    endif
  endif
  for p=prefixes
    for bound={'min','max'}
      if(isfinite(str2double(gxtxt_ini_get(cfg,[p{1} axis_key '_' bound{1}],'')))),yes=true;return;endif
    endfor
  endfor
  for bound={'min','max'}
    if(isfield(declared,bound{1})&&isfinite(str2double(declared.(bound{1})))),yes=true;return;endif
  endfor
endfunction
