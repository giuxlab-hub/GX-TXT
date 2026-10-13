% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT v0.8.1: framework-owned finalization of per-plot axes/grid overrides.
% Modules keep using the normal GX-TXT graphics APIs; this helper resolves the
% Graph Provider ID from the declared output filename and applies the existing
% axis override API just before PNG export.  Legend rendering is intentionally
% untouched.
function gxtxt_plot_finalize_output(fig, target)
  if (nargin < 2 || isempty(fig) || isempty(target)), return; endif
  % Multi-Y Axis Plot API v1: external legend/layout changes may resize the
  % primary axis. Keep framework-created overlay axes synchronized before
  % applying final per-plot overrides.
  try gxtxt_plot_sync_overlay_axes(fig); catch; end_try_catch
  mapfile = strtrim(getenv('GXTXT_PLOT_GRAPH_MAP_FILE'));
  if (isempty(mapfile) || exist(mapfile,'file') != 2), return; endif

  [graphKey, panelNames] = graph_info_for_target(mapfile,target);
  if (isempty(graphKey)), return; endif

  axs = data_axes_for_figure(fig);
  if (isempty(axs)), return; endif

  % Order stacked data axes top-to-bottom so panel overrides match the order
  % exposed by the framework's Axes/grid editor.  Single-axis plots are
  % unaffected.
  axs = sort_axes_top_to_bottom(axs);
  if (numel(panelNames) != numel(axs)), panelNames = {}; endif

  p = gxtxt_plot_config();
  gxtxt_plot_axis_overrides(axs,graphKey,panelNames,p,struct());
  % X overrides belong to the shared data coordinate and must reach overlay
  % axes too; secondary Y limits remain independent.
  try gxtxt_plot_sync_overlay_axes(fig); catch; end_try_catch
  if (!strncmp(graphKey,'plot.dataset',12))
    try auto_label_spacing(fig,axs,p); catch err; warning('GXTXT:AutoLabels','Automatic label spacing failed: %s',err.message); end_try_catch
  endif
endfunction

function auto_label_spacing(fig,axs,p)
  % Measure the final data rectangle after aspect and external legend changes.
  % The native X label already follows that rectangle; GNUplot can instead
  % leave Y labels at the pre-aspect position on wide/equal plots.
  for k=1:numel(axs)
    ax=axs(k);
    if(gxtxt_plot_axis_is_3d(ax) || !isempty(findobj(ax,'tag','GXTXT_ALIGNED_YLABEL'))),continue;endif
    x=label_x(ax,p,false);
    if(isfinite(x)),gxtxt_plot_align_ylabel(ax,x);endif
  endfor
  overlays=findall(fig,'type','axes','tag','gxtxt_overlay_yaxis');
  for k=1:numel(overlays)
    ax=overlays(k);
    if(!isempty(findobj(ax,'tag','GXTXT_ALIGNED_YLABEL'))),continue;endif
    x=label_x(ax,p,true);
    if(isfinite(x)),gxtxt_plot_align_ylabel(ax,x);endif
  endfor
endfunction

function x=label_x(ax,p,right)
  x=NaN;
  yh=get(ax,'ylabel');if(isempty(get(yh,'string'))),return;endif
  old=get(ax,'units');set(ax,'units','normalized');ap=get(ax,'position');set(ax,'units',old);
  if(numel(ap)<4 || ap(3)<=0),return;endif
  fig=ancestor(ax,'figure');fp=get(fig,'position');
  figure_width=max(1,fp(3));figure_height=max(1,fp(4));
  width=max(1,ap(3)*figure_width);height=max(1,ap(4)*figure_height);
  left=0;right_edge=1;
  equal_mode=false;
  try equal_mode=strcmp(getappdata(ax,'gxtxt_plot_xy_aspect_mode'),'xy_equal');catch;end_try_catch
  if(!equal_mode),return;endif
  if(equal_mode)
    ratio=get(ax,'plotboxaspectratio');
    if(numel(ratio)>=2 && all(isfinite(ratio(1:2))) && all(ratio(1:2)>0))
      wanted=ratio(1)/ratio(2);available=width/height;
      if(available>wanted),box_width=height*wanted;else box_width=width;endif
      left=(width-box_width)/(2*width);right_edge=1-left;
    endif
  endif
  fs=max(8,get(yh,'fontsize'));font_px=fs*max(72,p.dpi)/72;
  ticks=get(ax,'yticklabel');
  if(ischar(ticks)),chars=columns(ticks);elseif(iscell(ticks)),chars=max(cellfun(@numel,ticks));else chars=4;endif
  if(isempty(chars)),chars=0;endif
  tick_px=max(8,0.60*chars*font_px);
  gap_px=max(13,2.15*font_px);
  dist=max(0.03,(tick_px+gap_px)/width);
  if(right),x=min(right_edge+dist,(0.965-ap(1))/ap(3));
  else x=max(left-dist,(0.035-ap(1))/ap(3));endif
endfunction

function [key, panels] = graph_info_for_target(fn,target)
  key=''; panels={};
  fid=fopen(fn,'r'); if(fid<0),return;endif
  c=onCleanup(@() fclose(fid));
  hdr=fgetl(fid); if(!ischar(hdr)),return;endif
  want=canonical_path(target);
  while(true)
    line=fgetl(fid); if(!ischar(line)),break;endif
    if(isempty(strtrim(line))),continue;endif
    cols=regexp(line,'\t','split');
    if(numel(cols)<2),continue;endif
    if(strcmp(canonical_path(cols{1}),want))
      key=strtrim(cols{2});
      if(numel(cols)>=3 && !isempty(strtrim(cols{3})))
        panels=regexp(strtrim(cols{3}),';','split');
      endif
      return;
    endif
  endwhile
endfunction

function p = canonical_path(p)
  p=strtrim(p);
  if(isempty(p)),return;endif
  original=p;
  try q=canonicalize_file_name(p); catch; q=''; end_try_catch
  if(!isempty(q)), p=q; else p=original; endif
endfunction

function axs = data_axes_for_figure(fig)
  axs=[];
  try allaxs=findall(fig,'type','axes'); catch; allaxs=[]; end_try_catch
  for k=1:numel(allaxs)
    ax=allaxs(k);
    if (is_legend_helper_axes(ax) || is_overlay_axis(ax)), continue; endif
    axs(end+1)=ax;
  endfor
endfunction


function tf = is_overlay_axis(ax)
  tf=false;
  % plot.dataset multi-panel: panel right-Y overlays use gxtxt_panel_<n>_overlay_yaxis;
  % keep every GX-TXT *_overlay_yaxis out of primary stacked-axis finalization.
  try
    tag=lower(strtrim(get(ax,'tag'))); suffix='_overlay_yaxis';
    tf=strncmp(tag,'gxtxt_',6) && numel(tag)>=numel(suffix) && strcmp(tag(end-numel(suffix)+1:end),suffix);
  catch
  end_try_catch
endfunction

function tf = is_legend_helper_axes(ax)
  tf=false;
  % Native legend objects commonly carry a legend tag.
  try
    tag=lower(strtrim(get(ax,'tag')));
    if(!isempty(strfind(tag,'legend'))||!isempty(strfind(tag,'colorbar'))||strcmp(tag,'scribeoverlay')),tf=true;return;endif
  catch
  end_try_catch

  % GX-TXT's GNUplot legend helper is an axes in normalized 0..1 coordinates
  % with no ticks and no axis/title text.  Detect it without changing legend
  % code or legend state.
  try
    xt=get(ax,'xtick'); yt=get(ax,'ytick'); xl=get(ax,'xlim'); yl=get(ax,'ylim');
    xs=get(get(ax,'xlabel'),'string'); ys=get(get(ax,'ylabel'),'string'); ts=get(get(ax,'title'),'string');
    if(isempty(xt) && isempty(yt) && numel(xl)==2 && numel(yl)==2 && ...
       abs(xl(1))<1e-12 && abs(xl(2)-1)<1e-12 && abs(yl(1))<1e-12 && abs(yl(2)-1)<1e-12 && ...
       isempty_string(xs) && isempty_string(ys) && isempty_string(ts))
      tf=true;
    endif
  catch
  end_try_catch
endfunction

function tf = isempty_string(s)
  if(iscell(s)), tf=isempty(s) || all(cellfun(@isempty,s)); else tf=isempty(s); endif
endfunction

function axs = sort_axes_top_to_bottom(axs)
  if(numel(axs)<=1),return;endif
  y=zeros(1,numel(axs));
  for k=1:numel(axs)
    try
      old=get(axs(k),'units'); set(axs(k),'units','normalized'); pos=get(axs(k),'position'); y(k)=pos(2)+pos(4)/2; set(axs(k),'units',old);
    catch
      y(k)=0;
    end_try_catch
  endfor
  [~,ord]=sort(y,'descend'); axs=axs(ord);
endfunction
