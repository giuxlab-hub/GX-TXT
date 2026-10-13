% SPDX-License-Identifier: GPL-3.0-or-later
% Keep framework-created overlay Y axes on the same inner data rectangle.
function gxtxt_plot_sync_overlay_axes(fig)
  if(nargin<1||isempty(fig)),fig=gcf();endif
  prim=[];overlays=[];panel_primary=struct();panel_overlays=struct();
  try axs=findall(fig,'type','axes'); catch; axs=[]; end_try_catch
  for k=1:numel(axs)
    tag='';try tag=lower(strtrim(get(axs(k),'tag')));catch;end_try_catch
    if(strcmp(tag,'gxtxt_primary_axis'))
      prim=axs(k);
    elseif(strcmp(tag,'gxtxt_overlay_yaxis'))
      overlays(end+1)=axs(k);
    else
      tok=regexp(tag,'^gxtxt_panel_([0-9]+)$','tokens','once');
      if(!isempty(tok))
        panel_primary.(panel_key(tok{1}))=axs(k);
      else
        tok=regexp(tag,'^gxtxt_panel_([0-9]+)_overlay_yaxis$','tokens','once');
        if(!isempty(tok))
          key=panel_key(tok{1});
          if(!isfield(panel_overlays,key)),panel_overlays.(key)=[];endif
          panel_overlays.(key)(end+1)=axs(k);
        endif
      endif
    endif
  endfor

  % Historical single-panel contract remains unchanged.
  sync_pair(prim,overlays);

  % Multi-panel extension: panel 1 deliberately keeps the standard primary tag
  % for framework discovery, while later primaries use gxtxt_panel_<n>.
  keys=fieldnames(panel_overlays);
  for k=1:numel(keys)
    key=keys{k};p=[];
    if(strcmp(key,'p1')&&!isempty(prim))
      p=prim;
    elseif(isfield(panel_primary,key))
      p=panel_primary.(key);
    endif
    sync_pair(p,panel_overlays.(key));
  endfor
endfunction

function key=panel_key(n)
  key=['p' n];
endfunction

function sync_pair(prim,overlays)
  if(isempty(prim)||isempty(overlays)),return;endif

  % Octave 9.4/GNUplot supports positionconstraint=innerposition. Lock both
  % axes before copying geometry: with outerposition, GNUplot may recalculate a
  % different inner rectangle for each Y label/tick set at print() even though
  % get(position) reports equal values.
  lock_inner_position(prim);
  for k=1:numel(overlays),lock_inner_position(overlays(k));endfor

  oldu=get(prim,'units');
  unwind_protect
    set(prim,'units','normalized');
    pos=get(prim,'position');
    xl=get(prim,'xlim');xs=get(prim,'xscale');xd=get(prim,'xdir');
    for k=1:numel(overlays)
      old=get(overlays(k),'units');
      unwind_protect
        set(overlays(k),'units','normalized');
        set(overlays(k),'position',pos);
        set(overlays(k),'xlim',xl,'xscale',xs,'xdir',xd);
      unwind_protect_cleanup
        set(overlays(k),'units',old);
      end_unwind_protect
    endfor
  unwind_protect_cleanup
    set(prim,'units',oldu);
  end_unwind_protect
endfunction

function lock_inner_position(ax)
  try
    set(ax,'positionconstraint','innerposition');
  catch
    % Older Octave releases expose the equivalent MATLAB-compatible setting
    % under activepositionproperty.
    try set(ax,'activepositionproperty','position');catch;end_try_catch
  end_try_catch
endfunction
