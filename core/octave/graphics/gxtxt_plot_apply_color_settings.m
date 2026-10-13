% SPDX-License-Identifier: GPL-3.0-or-later
% Apply common colormap/colorbar/CLim presentation to an axes.
function cb=gxtxt_plot_apply_color_settings(ax,s,label_text)
  cb=[];if(nargin<1||isempty(ax)),ax=gca();endif;if(nargin<2||isempty(s)),s=gxtxt_plot_color_settings(struct(),' ',gxtxt_plot_config());endif
  if(nargin<3),label_text='';endif
  try
    cm=strtrim(s.colormap);if(!isempty(cm)&&!strcmpi(cm,'inherit'))
      try colormap(ax,cm);catch;try axes(ax);colormap(cm);catch;end_try_catch;end_try_catch
    endif
  catch
  end_try_catch
  try
    if(isfinite(s.color_min)&&isfinite(s.color_max)&&s.color_max>s.color_min),caxis(ax,[s.color_min s.color_max]);endif
  catch
  end_try_catch
  if(s.colorbar_visible)
    try cb=colorbar('peer',ax);catch;try cb=colorbar(ax);catch;cb=[];end_try_catch;end_try_catch
    if(isempty(label_text)),label_text=s.colorbar_label;endif
    if(!isempty(cb))
      pcfg=gxtxt_plot_config();tick_size=max(3,pcfg.font_size);
      try set(cb,'fontunits','points','fontsize',tick_size);catch;end_try_catch
      if(!isempty(strtrim(label_text)))
        try
          h=ylabel(cb,label_text);
          if(isfinite(pcfg.axis_label_font_size)),label_size=pcfg.axis_label_font_size;else label_size=pcfg.font_size;endif
          set(h,'fontunits','points','fontsize',max(3,label_size));
        catch;end_try_catch
      endif
    endif
  else
    try colorbar(ax,'off');catch;end_try_catch
  endif
endfunction
