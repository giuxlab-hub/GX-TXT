% SPDX-License-Identifier: GPL-3.0-or-later
function h = gxtxt_plot_text(kind,textValue,varargin)
  p = gxtxt_plot_config();
  extra = varargin;
  if (strcmp(kind,'xlabel') || strcmp(kind,'ylabel'))
    fs = p.axis_label_font_size;
    if (isfinite(fs) && fs > 0), extra = [extra {'fontunits','points','fontsize',fs}]; endif
  elseif (strcmp(kind,'title'))
    fs = p.title_font_size;
    if (isfinite(fs) && fs > 0), extra = [extra {'fontunits','points','fontsize',fs}]; endif
  endif
  if (strcmp(kind,'xlabel'))
    h = xlabel(textValue,'interpreter','none',extra{:});
  elseif (strcmp(kind,'ylabel'))
    h = ylabel(textValue,'interpreter','none',extra{:});
  elseif (strcmp(kind,'title'))
    h = title(textValue,'interpreter','none',extra{:});
  else
    error('Unknown plot text type: %s',kind);
  endif
endfunction
