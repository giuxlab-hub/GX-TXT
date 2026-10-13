% SPDX-License-Identifier: GPL-3.0-or-later
% Centralized legend renderer with global and per-graph configuration.
% GX-TXT Pipeline v0.7.7
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
function h = gxtxt_plot_legend(varargin)
  % Supported forms:
  %   gxtxt_plot_legend(labels,p,graphKey)
  %   gxtxt_plot_legend(handles,labels,p,graphKey)
  %   gxtxt_plot_legend(handles,labels,p,graphKey,runtimeCfg)
  %
  % Legend geometry is intentionally split into independent concepts:
  %   placement : inside / above / below / left / right / manual / none
  %   layout    : auto / row / stacked / wrapped
  %   alignment : start / center / end (for external placement)
  %   location  : inside preset only (north, northeast, ...)
  % This prevents the historical ambiguity where "below" and "northeast"
  % competed to describe the same thing.

  h = []; handles = []; labels = {}; p = []; graphKey = ''; runtimeCfg = [];
  if (nargin >= 4)
    handles = varargin{1}; labels = varargin{2}; p = varargin{3}; graphKey = varargin{4};
    if (nargin >= 5), runtimeCfg = varargin{5}; endif
  elseif (nargin >= 1)
    labels = varargin{1};
    if (nargin >= 2), p = varargin{2}; endif
    if (nargin >= 3), graphKey = varargin{3}; endif
  endif
  if (isempty(p)), p = gxtxt_plot_config(); endif
  if (isempty(labels)), return; endif

  % ---- defaults and legacy fallback ----
  placement = lower(getfield_def(p,'legend_mode','inside'));
  loc = lower(getfield_def(p,'legend_location','northeast'));
  legacyOrient = lower(getfield_def(p,'legend_orientation','auto'));
  layout = lower(getfield_def(p,'legend_layout','auto'));
  alignment = lower(getfield_def(p,'legend_alignment','center'));
  columns = getfield_def(p,'legend_columns',1);
  bg = getfield_def(p,'legend_background','#FFFFFF');
  border = logical(getfield_def(p,'legend_border',true));
  edge = getfield_def(p,'legend_border_color','#808080');
  fontSize = getfield_def(p,'legend_font_size',10);
  fontUnit = getfield_def(p,'legend_font_unit',getfield_def(p,'font_unit','px'));
  manualX = getfield_def(p,'legend_manual_x',0.75);
  manualY = getfield_def(p,'legend_manual_y',0.85);
  externalMarginPx = getfield_def(p,'legend_external_margin_px',12);
  externalBorder = logical(getfield_def(p,'legend_external_border',false));
  hasBorderOverride = false;

  % If the new layout field is absent/auto, preserve old orientation semantics.
  if (strcmp(layout,'auto'))
    if (strcmp(legacyOrient,'horizontal')), layout='row';
    elseif (strcmp(legacyOrient,'vertical')), layout='stacked';
    endif
  endif

  % ---- TSV override ----
  o = gxtxt_plot_legend_override(graphKey);
  [placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride] = ...
    apply_override(o,placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride,p);

  % ---- runtime.ini override (authoritative for native module rerender) ----
  ro = runtime_legend_override(runtimeCfg,graphKey);
  if (isfield(ro,'enabled') && ro.enabled)
    [placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride] = ...
      apply_override(ro,placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride,p);
    fprintf('[graphics] legend override %s: placement=%s inside=%s alignment=%s layout=%s columns=%d\n', ...
            graphKey,placement,loc,alignment,layout,round(columns));
  endif

  placement = normalize_placement(placement);
  layout = normalize_layout(layout,placement);
  alignment = normalize_alignment(alignment);
  columns = max(1,round(columns));
  if (strcmp(placement,'none')), return; endif

  % The untouched default may choose a corner from actual 2D data occupancy.
  % Any saved legend override retains its explicit placement and preset.
  explicitLegend=(isfield(o,'enabled')&&o.enabled)||(isfield(ro,'enabled')&&ro.enabled);
  if (!explicitLegend && strcmp(placement,'inside'))
    if (numel(labels)>=5 || sum(cellfun(@numel,labels))>140)
      placement='below';
    else
      loc=least_occupied_corner(gca(),handles,loc);
    endif
  endif

  isExternal = any(strcmp(placement,{'below','above','right','left'}));
  if (isExternal && !hasBorderOverride), border = externalBorder; endif

  % Exact row/stacked/wrapped semantics, independent of placement.
  n = numel(labels);
  if (strcmp(layout,'row'))
    ncols = max(1,n); nrows = 1;
  elseif (strcmp(layout,'stacked'))
    ncols = 1; nrows = max(1,n);
  elseif (strcmp(layout,'wrapped'))
    ncols = min(max(1,columns),max(1,n)); nrows = ceil(n/max(1,ncols));
  else
    if (any(strcmp(placement,{'above','below'}))), ncols=max(1,n); else ncols=1; endif
    nrows=ceil(n/max(1,ncols));
  endif

  ax = gca();
  toolkit = '';
  try toolkit = lower(graphics_toolkit()); catch; end_try_catch

  % GNUplot does not reliably preserve a manually assigned native legend
  % Position during print().  For GNUplot, use a lightweight legend axes for
  % every placement.  Axes positions *are* reliably exported and this also
  % makes placement and layout genuinely independent.
  if (strcmp(toolkit,'gnuplot'))
    h = gxtxt_legend_axes(ax,handles,labels,p,placement,loc,alignment,layout,ncols,nrows, ...
                          bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,graphKey);
    % Keep the legend axes current until print().  With the GNUplot toolkit,
    % switching back to the data axes can place the opaque plot axes in front
    % of the custom legend axes during export, especially for manual/inside
    % placement.  The module calls the legend as its final graphics operation.
    try axes(h); catch; end_try_catch
    return;
  endif

  % Other toolkits can use the native legend object while retaining the same
  % public placement/layout model.
  nativeLayout=layout; if(strcmp(nativeLayout,'auto')),if(any(strcmp(placement,{'above','below'}))),nativeLayout='row';else nativeLayout='stacked';endif;endif
  orient = ternary(strcmp(nativeLayout,'stacked'),'vertical','horizontal');
  nativeLoc = loc;
  if (strcmp(placement,'below')), nativeLoc='southoutside';
  elseif (strcmp(placement,'above')), nativeLoc='northoutside';
  elseif (strcmp(placement,'right')), nativeLoc='eastoutside';
  elseif (strcmp(placement,'left')), nativeLoc='westoutside';
  elseif (strcmp(placement,'manual')), nativeLoc='northeast';
  endif
  try
    if (!isempty(handles)), h=legend(handles,labels,'location',nativeLoc,'orientation',orient,'interpreter','none');
    else h=legend(labels,'location',nativeLoc,'orientation',orient,'interpreter','none'); endif
  catch
    if (!isempty(handles)), h=legend(handles,labels,'location',nativeLoc); else h=legend(labels,'location',nativeLoc); endif
  end_try_catch
  if (isempty(h)), return; endif
  try set(h,'fontunits','points','fontsize',fontSize); catch; end_try_catch
  try set(h,'orientation',orient); catch; end_try_catch
  try set(h,'numcolumns',ncols); catch; end_try_catch
  apply_native_style(h,bg,border,edge);
  drawnow();
  if (strcmp(placement,'manual'))
    try
      set(h,'location','none'); set(h,'units','normalized'); drawnow();
      pos=get(h,'position'); pos(1)=clamp(manualX-pos(3)/2,0,1-pos(3)); pos(2)=clamp(manualY-pos(4)/2,0,1-pos(4));
      set(h,'position',pos); set(h,'location','none'); drawnow();
    catch err
      warning('GXTXT:LegendManual','Manual legend placement failed: %s',err.message);
    end_try_catch
  endif
  try axes(ax); catch; end_try_catch
endfunction

function loc=least_occupied_corner(ax,handles,fallback)
  loc=fallback;
  if (isempty(handles)), return; endif
  try
    xl=get(ax,'xlim');yl=get(ax,'ylim');
    if (numel(xl)!=2||numel(yl)!=2||any(!isfinite([xl yl]))||diff(xl)<=0||diff(yl)<=0),return;endif
    scores=zeros(1,4); seen=0;
    for k=1:numel(handles)
      if (!ishandle(handles(k))),continue;endif
      xx=get(handles(k),'xdata');yy=get(handles(k),'ydata');
      if (numel(xx)!=numel(yy)),continue;endif
      xx=(xx(:)-xl(1))/diff(xl);yy=(yy(:)-yl(1))/diff(yl);
      valid=isfinite(xx)&isfinite(yy)&xx>=0&xx<=1&yy>=0&yy<=1;
      xx=xx(valid);yy=yy(valid);if(isempty(xx)),continue;endif
      stride=max(1,ceil(numel(xx)/600));xx=xx(1:stride:end);yy=yy(1:stride:end);
      scores=scores+[sum(xx<0.38&yy>0.62),sum(xx>0.62&yy>0.62),sum(xx<0.38&yy<0.38),sum(xx>0.62&yy<0.38)];
      seen=seen+numel(xx);
    endfor
    if (seen>0)
      names={'northwest','northeast','southwest','southeast'};
      [~,i]=min(scores);loc=names{i};
    endif
  catch
    loc=fallback;
  end_try_catch
endfunction

function hax = gxtxt_legend_axes(ax,handles,labels,p,placement,loc,alignment,layout,ncols,nrows,bg,border,edge,fontUnit,fontSize,marginPx,manualX,manualY,graphKey)
  fig = ancestor(ax,'figure');
  if(isExternalPlacement(placement))
    try set(ax,'positionconstraint','innerposition');catch;end_try_catch
  endif
  try set(ax,'units','normalized'); catch; end_try_catch
  ap = get(ax,'position');
  n = numel(labels);
  widthPx = max(320,getfield_def(p,'width_px',1600));
  heightPx = max(240,getfield_def(p,'height_px',900));
  dpi = max(72,getfield_def(p,'dpi',200));
  fontPx = fontSize * dpi / 72.0;
  samplePx = max(20,2.2*fontPx);
  gapPx = max(5,0.55*fontPx);
  padXPx = max(5,0.60*fontPx);
  padYPx = max(4,0.45*fontPx);
  rowHPx = max(14,1.55*fontPx);
  charPx = max(4,0.58*fontPx);

  % Determine the maximum physical width available to the legend.  External
  % horizontal bands and manual overlays may use almost the full figure;
  % inside legends are constrained to the data axes; left/right bands are
  % intentionally narrower so the data axes never collapse.
  if (strcmp(placement,'inside'))
    maxBoxNorm=max(0.08,min(0.96,ap(3)*0.97));
  elseif (any(strcmp(placement,{'left','right'})))
    maxBoxNorm=0.42;
  else
    maxBoxNorm=0.96;
  endif
  maxBoxPx=max(80,maxBoxNorm*widthPx);

  itemW=zeros(1,n);
  for i=1:n
    itemW(i)=2*padXPx + samplePx + gapPx + max(12,charPx*numel(labels{i}));
  endfor

  requestedLayout=layout;
  if (strcmp(layout,'auto'))
    if (any(strcmp(placement,{'above','below'}))), layout='row';
    elseif (any(strcmp(placement,{'left','right'}))), layout='stacked';
    else layout='wrapped'; endif
  endif

  if (strcmp(layout,'stacked'))
    ncolsEff=1;
  elseif (strcmp(layout,'row'))
    ncolsEff=max(1,n);
  else
    ncolsEff=min(max(1,ncols),max(1,n));
  endif

  % Fit the requested arrangement to the available width.  A forced one-row
  % legend that physically cannot fit is automatically wrapped rather than
  % clipping its right border or text.  Wrapped layouts reduce the requested
  % column count until every column fits.  The effective layout is logged.
  [fits,colWPx,boxWPx,nrowsEff] = legend_layout_width(itemW,ncolsEff,rowHPx,padYPx,maxBoxPx);
  if (!fits && ncolsEff > 1)
    originalCols=ncolsEff;
    while (ncolsEff > 1)
      ncolsEff=ncolsEff-1;
      [fits,colWPx,boxWPx,nrowsEff] = legend_layout_width(itemW,ncolsEff,rowHPx,padYPx,maxBoxPx);
      if (fits), break; endif
    endwhile
    if (strcmp(layout,'row'))
      fprintf('[graphics] legend auto-wrap %s: requested=row entries=%d -> wrapped columns=%d (available=%gpx)\n', ...
              graphKey,n, ncolsEff,maxBoxPx);
      layout='wrapped';
    elseif (originalCols != ncolsEff)
      fprintf('[graphics] legend fit %s: requested columns=%d -> effective columns=%d (available=%gpx)\n', ...
              graphKey,originalCols,ncolsEff,maxBoxPx);
    endif
  endif
  if (!fits)
    % A single exceptionally long label can still exceed the available width.
    % Keep the box inside the figure and let the text use all available space.
    colWPx=maxBoxPx;
    boxWPx=maxBoxPx;
    nrowsEff=max(1,n);
    ncolsEff=1;
    layout='stacked';
    fprintf('[graphics] legend width clamp %s: single-column width limited to %gpx\n',graphKey,maxBoxPx);
  endif

  nrows=nrowsEff; ncols=ncolsEff;
  boxHPx = nrows*rowHPx + 2*padYPx;
  boxW = min(0.98,max(0.04,boxWPx/widthPx));
  boxH = min(0.98,max(0.035,boxHPx/heightPx));
  mx = max(0,marginPx)/widthPx; my = max(0,marginPx)/heightPx;

  % Reserve external space before positioning the legend axes.
  if (strcmp(placement,'below'))
    % The native X label is rendered below the axes position under GNUplot.
    % Keep the legend below that measured font band, not between the data box
    % and its label.  The reserve is expressed in output pixels.
    sep = my + max(0.045,4.5*fontPx/heightPx);
    needed = boxH + sep + 0.01;
    free = ap(2)-0.01;
    if (needed > free)
      delta=needed-free; ap(2)=ap(2)+delta; ap(4)=max(0.05,ap(4)-delta); set(ax,'position',ap);
    endif
    y=max(0.005,ap(2)-sep-boxH); x=aligned_x(ap,boxW,alignment);
  elseif (strcmp(placement,'above'))
    needed=boxH+my; free=1-(ap(2)+ap(4))-0.01;
    if (needed > free), delta=needed-free; ap(4)=max(0.05,ap(4)-delta); set(ax,'position',ap); endif
    y=min(1-boxH-0.005,ap(2)+ap(4)+my); x=aligned_x(ap,boxW,alignment);
  elseif (strcmp(placement,'right'))
    needed=boxW+mx; free=1-(ap(1)+ap(3))-0.01;
    if (needed > free), delta=needed-free; ap(3)=max(0.05,ap(3)-delta); set(ax,'position',ap); endif
    x=min(1-boxW-0.005,ap(1)+ap(3)+mx); y=aligned_y(ap,boxH,alignment);
  elseif (strcmp(placement,'left'))
    needed=boxW+mx; free=ap(1)-0.01;
    if (needed > free), delta=needed-free; ap(1)=ap(1)+delta; ap(3)=max(0.05,ap(3)-delta); set(ax,'position',ap); endif
    x=max(0.005,ap(1)-mx-boxW); y=aligned_y(ap,boxH,alignment);
  elseif (strcmp(placement,'manual'))
    x=clamp(manualX-boxW/2,0.005,1-boxW-0.005); y=clamp(manualY-boxH/2,0.005,1-boxH-0.005);
  else
    [x,y]=inside_xy(ap,boxW,boxH,loc);
  endif

  % GNUplot custom-legend background/frame policy (v0.7.7):
  %
  % Do NOT use one patch both as the background and as the frame.  With the
  % GNUplot toolkit a patch living on a transparent overlay axes can be
  % exported after the data-axes grid, which makes grid lines appear to pass
  % through the legend even though the patch exists.  Make the legend axes
  % itself opaque when a background is requested, then draw the frame as four
  % independent line objects slightly inside the axes bounds.  This keeps the
  % background and border responsibilities separate and avoids edge clipping.
  if (!(isempty(bg) || strcmpi(bg,'none') || strcmpi(bg,'transparent')))
    fc=gxtxt_plot_color(bg,[1 1 1]);
    axesColor=fc;
    bgOpaque=true;
  else
    fc='none';
    axesColor='none';
    bgOpaque=false;
  endif
  if (border), ec=gxtxt_plot_color(edge,[0.5 0.5 0.5]); else ec='none'; endif

  % The helper axes is only a coordinate container.  Octave/GNUplot 9.4
  % generates malformed GNUplot commands for xcolor/ycolor='none'.  Hide the
  % implicit bottom/left axes by painting them with the effective background
  % color instead.  This preserves the borderless appearance without emitting
  % invalid GNUplot style expressions.  The user-selected frame remains a
  % separate set of four line objects below.
  axisEdgeColor=axesColor;
  if (!bgOpaque)
    try axisEdgeColor=get(fig,'color'); catch; axisEdgeColor=[1 1 1]; end_try_catch
    if (ischar(axisEdgeColor) && strcmpi(axisEdgeColor,'none')), axisEdgeColor=[1 1 1]; endif
  endif
  hax=axes('parent',fig,'units','normalized','position',[x y boxW boxH], ...
           'xlim',[0 1],'ylim',[0 1],'xtick',[],'ytick',[],'box','off','color',axesColor, ...
           'xcolor',axisEdgeColor,'ycolor',axisEdgeColor,'zcolor',axisEdgeColor,'xgrid','off','ygrid','off','zgrid','off');
  hold(hax,'on');

  % Keep each frame segment at least about one physical output pixel inside
  % the legend axes.  Four line objects are substantially more predictable
  % than a rectangle/patch edge under GNUplot print().
  frameInsetX=max(0.0020,1.0/max(1,boxWPx));
  frameInsetY=max(0.0020,1.0/max(1,boxHPx));
  if (border)
    x0=frameInsetX; x1=1-frameInsetX; y0=frameInsetY; y1=1-frameInsetY;
    try
      hb1=line('parent',hax,'xdata',[x0 x1],'ydata',[y0 y0],'color',ec,'linewidth',0.7);
      hb2=line('parent',hax,'xdata',[x0 x1],'ydata',[y1 y1],'color',ec,'linewidth',0.7);
      hb3=line('parent',hax,'xdata',[x0 x0],'ydata',[y0 y1],'color',ec,'linewidth',0.7);
      hb4=line('parent',hax,'xdata',[x1 x1],'ydata',[y0 y1],'color',ec,'linewidth',0.7);
      try set([hb1 hb2 hb3 hb4],'clipping','off'); catch; end_try_catch
    catch
    end_try_catch
  endif

  % Variable-width columns: each column is sized from the longest label that
  % actually occupies it.  This is the key difference from v0.7.0, where one
  % global max-label width was multiplied by the number of columns.
  colStartPx=[0 cumsum(colWPx(1:end-1))];
  for i=1:n
    r=floor((i-1)/ncols); c=mod(i-1,ncols)+1;
    cy=1-(padYPx+(r+0.5)*rowHPx)/boxHPx;
    sx0=(colStartPx(c)+padXPx)/boxWPx;
    sx1=(colStartPx(c)+padXPx+samplePx)/boxWPx;
    tx=(colStartPx(c)+padXPx+samplePx+gapPx)/boxWPx;
    style=source_style(handles,i);
    if (!strcmp(style.linestyle,'none'))
      try line('parent',hax,'xdata',[sx0 sx1],'ydata',[cy cy],'color',style.color,'linestyle',style.linestyle,'linewidth',style.linewidth); catch; end_try_catch
    endif
    if (!strcmp(style.marker,'none'))
      try line('parent',hax,'xdata',(sx0+sx1)/2,'ydata',cy,'color',style.color,'linestyle','none','marker',style.marker,'markersize',style.markersize); catch; end_try_catch
    endif
    try text('parent',hax,'position',[tx cy 0],'string',labels{i},'interpreter','none','verticalalignment','middle','horizontalalignment','left','fontunits','points','fontsize',fontSize); catch; end_try_catch
  endfor

  % Preserve the opaque axes background selected above.  Re-applying
  % color='none' here was another way to undo the intended legend background.
  try
    set(hax,'visible','on','xtick',[],'ytick',[],'box','off', ...
            'xcolor',axisEdgeColor,'ycolor',axisEdgeColor,'zcolor',axisEdgeColor, ...
            'xgrid','off','ygrid','off','zgrid','off');
  catch
  end_try_catch
  drawnow();
  fprintf('[graphics] legend custom axes %s: visible=%s children=%d background=%s frame=%s axes_edges=background font_unit=%s font_pt=%g dpi=%g\n', ...
          graphKey,get(hax,'visible'),numel(get(hax,'children')),ternary(bgOpaque,'opaque','transparent'),ternary(border,'line4','none'),fontUnit,fontSize,dpi);
  fprintf('[graphics] legend geometry %s: placement=%s alignment=%s layout=%s requested_layout=%s rows=%d columns=%d box=[%.4f %.4f %.4f %.4f]\n', ...
          graphKey,placement,alignment,layout,requestedLayout,nrows,ncols,x,y,boxW,boxH);
  if(isExternalPlacement(placement))
    try q=get(ax,'position');fprintf('[graphics] legend data axes %s: position=[%.4f %.4f %.4f %.4f]\n',graphKey,q(1),q(2),q(3),q(4));catch;end_try_catch
    try q=get(ax,'tightinset');fprintf('[graphics] legend data tightinset %s: [%.4f %.4f %.4f %.4f]\n',graphKey,q(1),q(2),q(3),q(4));catch;end_try_catch
  endif
  if (strcmp(placement,'manual'))
    fprintf('[graphics] legend manual %s: anchor=center figure_norm=(%.4f,%.4f) applied=[%.4f %.4f %.4f %.4f] renderer=gnuplot-custom\n', ...
            graphKey,manualX,manualY,x,y,boxW,boxH);
  endif
endfunction

function tf=isExternalPlacement(placement)
  tf=any(strcmp(placement,{'below','above','left','right'}));
endfunction

function [fits,colW,boxW,nrows] = legend_layout_width(itemW,ncols,rowHPx,padYPx,maxBoxPx)
  n=numel(itemW); ncols=max(1,min(ncols,max(1,n))); nrows=ceil(n/ncols);
  colW=zeros(1,ncols);
  for i=1:n
    c=mod(i-1,ncols)+1;
    colW(c)=max(colW(c),itemW(i));
  endfor
  boxW=sum(colW);
  fits=(boxW <= maxBoxPx+1e-9);
endfunction

function s=source_style(handles,i)
  s=struct('color',[0 0 0],'linestyle','-','linewidth',1,'marker','none','markersize',5);
  if (isempty(handles) || i>numel(handles)), return; endif
  h=handles(i);
  try s.color=get(h,'color'); catch; end_try_catch
  try s.linestyle=get(h,'linestyle'); catch; end_try_catch
  try s.linewidth=get(h,'linewidth'); catch; end_try_catch
  try s.marker=get(h,'marker'); catch; end_try_catch
  try s.markersize=get(h,'markersize'); catch; end_try_catch
endfunction

function [x,y]=inside_xy(ap,w,h,loc)
  pad=0.008; loc=lower(strtrim(loc));
  switch loc
    case 'north', x=ap(1)+(ap(3)-w)/2; y=ap(2)+ap(4)-h-pad;
    case 'northeast', x=ap(1)+ap(3)-w-pad; y=ap(2)+ap(4)-h-pad;
    case 'east', x=ap(1)+ap(3)-w-pad; y=ap(2)+(ap(4)-h)/2;
    case 'southeast', x=ap(1)+ap(3)-w-pad; y=ap(2)+pad;
    case 'south', x=ap(1)+(ap(3)-w)/2; y=ap(2)+pad;
    case 'southwest', x=ap(1)+pad; y=ap(2)+pad;
    case 'west', x=ap(1)+pad; y=ap(2)+(ap(4)-h)/2;
    otherwise, x=ap(1)+pad; y=ap(2)+ap(4)-h-pad;
  endswitch
  x=clamp(x,0.005,1-w-0.005); y=clamp(y,0.005,1-h-0.005);
endfunction

function x=aligned_x(ap,w,a)
  if (strcmp(a,'start')), x=ap(1);
  elseif (strcmp(a,'end')), x=ap(1)+ap(3)-w;
  else x=ap(1)+(ap(3)-w)/2; endif
  x=clamp(x,0.005,1-w-0.005);
endfunction
function y=aligned_y(ap,h,a)
  % For vertical external bands: start=top, center=center, end=bottom.
  if (strcmp(a,'start')), y=ap(2)+ap(4)-h;
  elseif (strcmp(a,'end')), y=ap(2);
  else y=ap(2)+(ap(4)-h)/2; endif
  y=clamp(y,0.005,1-h-0.005);
endfunction

function p=normalize_placement(p)
  p=lower(strtrim(p));
  if (strcmp(p,'off') || strcmp(p,'hidden')), p='none'; endif
  if (!any(strcmp(p,{'none','inside','above','below','left','right','manual'}))), p='inside'; endif
endfunction
function l=normalize_layout(l,placement)
  l=lower(strtrim(l));
  if (strcmp(l,'vertical')), l='stacked'; elseif (strcmp(l,'horizontal')), l='row'; endif
  if (!any(strcmp(l,{'auto','row','stacked','wrapped'}))), l='auto'; endif
endfunction
function a=normalize_alignment(a)
  a=lower(strtrim(a)); if (!any(strcmp(a,{'start','center','end'}))), a='center'; endif
endfunction
function v=clamp(v,lo,hi), if(hi<lo),hi=lo;endif; v=min(hi,max(lo,v)); endfunction
function v=getfield_def(s,n,d), if(isstruct(s)&&isfield(s,n)),v=s.(n);else v=d;endif; endfunction
function y=ternary(c,a,b), if(c),y=a;else y=b;endif; endfunction

function apply_native_style(h,bg,border,edge)
  if (isempty(bg) || strcmpi(bg,'none') || strcmpi(bg,'transparent'))
    try set(h,'color','none'); catch; end_try_catch
  else
    c=gxtxt_plot_color(bg,[]); if(!isempty(c)),try set(h,'color',c);catch;end_try_catch;endif
  endif
  if(border),try set(h,'box','on');catch;end_try_catch;else try set(h,'box','off');catch;end_try_catch;endif
  c=gxtxt_plot_color(edge,[]); if(!isempty(c)),try set(h,'edgecolor',c);catch;end_try_catch;endif
endfunction

function [placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride] = ...
  apply_override(o,placement,loc,alignment,layout,columns,bg,border,edge,fontUnit,fontSize,externalMarginPx,manualX,manualY,hasBorderOverride,p)
  if (isempty(o) || !isstruct(o)), return; endif
  % New names take priority; old names are migration aliases.
  if (isfield(o,'placement') && !isempty(o.placement)), placement=lower(o.placement);
  elseif (isfield(o,'mode') && !isempty(o.mode)), placement=lower(o.mode); endif
  if (isfield(o,'location') && !isempty(o.location)), loc=lower(o.location); endif
  if (isfield(o,'alignment') && !isempty(o.alignment)), alignment=lower(o.alignment); endif
  if (isfield(o,'layout') && !isempty(o.layout)), layout=lower(o.layout);
  elseif (isfield(o,'orientation') && !isempty(o.orientation))
    oo=lower(o.orientation); if(strcmp(oo,'horizontal')),layout='row';elseif(strcmp(oo,'vertical')),layout='stacked';endif
  endif
  if (isfield(o,'columns')),v=str2double(o.columns);if(isfinite(v)&&v>=1),columns=round(v);endif;endif
  % Empty/inherit means exactly that: keep the parent (module/global) value.
  % An explicit 'none' background remains a valid request for transparency.
  if (isfield(o,'background'))
    vv=strtrim(o.background);
    if (!isempty(vv) && !strcmpi(vv,'inherit')), bg=vv; endif
  endif
  if (isfield(o,'border'))
    vv=strtrim(o.border);
    if (!isempty(vv) && !strcmpi(vv,'inherit'))
      v=str2double(vv);
      if(isfinite(v)),border=(v!=0);else border=any(strcmpi(vv,{'on','true','yes'}));endif
      hasBorderOverride=true;
    endif
  endif
  if (isfield(o,'border_color'))
    vv=strtrim(o.border_color);
    if (!isempty(vv) && !strcmpi(vv,'inherit')), edge=vv; endif
  endif
  if (isfield(o,'font_unit') && !isempty(strtrim(o.font_unit)))
    fu=lower(strtrim(o.font_unit)); if(any(strcmp(fu,{'px','pt'}))),fontUnit=fu;endif
  endif
  if (isfield(o,'font_size')),v=str2double(o.font_size);if(isfinite(v)&&v>0),fontSize=gxtxt_plot_font_to_points(v,fontUnit,p.dpi);endif;endif
  if (isfield(o,'external_margin_px')),v=str2double(o.external_margin_px);if(isfinite(v)&&v>=0),externalMarginPx=min(100,v);endif;endif
  if (isfield(o,'manual_x')),v=str2double(o.manual_x);if(isfinite(v)),manualX=clamp(v,0,1);endif;endif
  if (isfield(o,'manual_y')),v=str2double(o.manual_y);if(isfinite(v)),manualY=clamp(v,0,1);endif;endif
endfunction

function o = runtime_legend_override(cfg,graphKey)
  o=struct(); if(isempty(cfg)||!isstruct(cfg)||isempty(strtrim(graphKey))),return;endif
  ek=runtime_key(['legend.' graphKey '.enabled']); if(!isfield(cfg,ek)),return;endif
  ev=lower(strtrim(cfg.(ek))); o.enabled=any(strcmp(ev,{'1','true','yes','on'})); if(!o.enabled),return;endif
  fields={'mode','placement','location','alignment','orientation','layout','columns','background','border','border_color','font_unit','font_size','external_margin_px','manual_x','manual_y'};
  for kk=1:numel(fields),k=runtime_key(['legend.' graphKey '.' fields{kk}]);if(isfield(cfg,k)),o.(fields{kk})=strtrim(cfg.(k));endif;endfor
endfunction
function k=runtime_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
