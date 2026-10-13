% GX-TXT Computed Data Annotation API v1 renderer for 2D plots.
% Draws module-produced, data-coordinate annotations without changing dataset data.
% SPDX-License-Identifier: GPL-3.0-or-later
function handles = gxtxt_plot_data_annotations_2d(ax_left, ax_right, annotations, ctx)
  handles=[]; if(isempty(annotations)||isempty(ax_left)),return;endif
  xl=xlim(ax_left); yl=ylim(ax_left); if(!isempty(ax_right)),yr=ylim(ax_right);else yr=[];endif
  for i=1:numel(annotations)
    A=annotations(i); [ls,mk]=style_for(A.style_hint);
    try
      if(strcmp(A.type,'vline'))
        if(!strcmp(A.x_variable,ctx.x_variable)),continue;endif
        x=convertv(A.x,A.x_unit,ctx.x_display_unit); h=line(ax_left,[x x],yl,'linestyle',ls,'linewidth',1.1);handles(end+1)=h;
        if(!isempty(A.label)),text(ax_left,x,yl(2),[' ' A.label],'verticalalignment','top','interpreter','none');endif
      elseif(strcmp(A.type,'hline'))
        [ax,du]=y_axis_for(A.y_variable,ctx,ax_left,ax_right); if(isempty(ax)),continue;endif
        y=convertv(A.y,A.y_unit,du); lim=ylim(ax); xla=xlim(ax);h=line(ax,xla,[y y],'linestyle',ls,'linewidth',1.1);handles(end+1)=h;
        if(!isempty(A.label)),text(ax,xla(2),y,[' ' A.label],'horizontalalignment','right','verticalalignment','bottom','interpreter','none');endif
      elseif(any(strcmp(A.type,{'point','text'})))
        if(!strcmp(A.x_variable,ctx.x_variable)),continue;endif
        [ax,du]=y_axis_for(A.y_variable,ctx,ax_left,ax_right);if(isempty(ax)),continue;endif
        x=convertv(A.x,A.x_unit,ctx.x_display_unit);y=convertv(A.y,A.y_unit,du);
        if(strcmp(A.type,'point')),h=plot(ax,x,y,mk,'linestyle','none','markersize',7,'linewidth',1.2);handles(end+1)=h;endif
        if(!isempty(A.label)),text(ax,x,y,[' ' A.label],'verticalalignment','bottom','interpreter','none');elseif(strcmp(A.type,'text')),text(ax,x,y,A.id,'verticalalignment','bottom','interpreter','none');endif
      endif
    catch err
      warning('GXTXT:DataAnnotations','Skipping computed annotation %s: %s',A.id,err.message);
    end_try_catch
  endfor
  xlim(ax_left,xl);ylim(ax_left,yl);if(!isempty(ax_right)),ylim(ax_right,yr);endif
endfunction
function v=convertv(v,from,to),if(isempty(from)||isempty(to)||strcmp(from,to)),return;endif;v=gxtxt_unit_convert(v,from,to);endfunction
function [ax,du]=y_axis_for(var,ctx,axl,axr)
  ax=[];du='';if(any(strcmp(ctx.y_left_variables,var))),ax=axl;du=ctx.y_left_display_unit;return;endif
  if(!isempty(axr)&&any(strcmp(ctx.y_right_variables,var))),ax=axr;du=ctx.y_right_display_unit;endif
endfunction
function [ls,mk]=style_for(h)
  h=lower(strtrim(h));ls='-';mk='o';
  if(strcmp(h,'harmonic')),ls='--';mk='s';elseif(strcmp(h,'spur')),ls=':';mk='x';elseif(any(strcmp(h,{'warning','threshold'}))),ls='-.';mk='d';elseif(strcmp(h,'secondary')),ls='--';mk='^';endif
endfunction
