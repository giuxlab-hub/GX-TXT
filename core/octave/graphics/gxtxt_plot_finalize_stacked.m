% SPDX-License-Identifier: GPL-3.0-or-later
% Finalizzazione comune dei layout stacked GX-TXT.
function gxtxt_plot_finalize_stacked(axs,p)
  if (nargin < 1 || isempty(axs)), return; endif
  if (nargin < 2), p = gxtxt_plot_config(); endif
  axs = axs(:)';
  n = numel(axs);

  % Asse X comune: usa l'estensione complessiva degli assi.
  if (p.stacked_shared_x && n > 1)
    xmin = Inf; xmax = -Inf;
    for k = 1:n
      try
        xl = get(axs(k),'xlim');
        if (numel(xl) == 2)
          xmin = min(xmin,xl(1)); xmax = max(xmax,xl(2));
        endif
      catch
      end_try_catch
    endfor
    if (isfinite(xmin) && isfinite(xmax) && xmax > xmin)
      for k = 1:n
        try set(axs(k),'xlim',[xmin xmax]); catch; end_try_catch
      endfor
    endif
  endif

  % Griglia specifica per stacked. 'inherit' conserva la scelta globale.
  gm = lower(strtrim(p.stacked_grid_mode));
  for k = 1:n
    ax = axs(k);
    try
      if (strcmp(gm,'none'))
        set(ax,'xgrid','off','ygrid','off');
      elseif (strcmp(gm,'vertical'))
        set(ax,'xgrid','on','ygrid','off');
      elseif (strcmp(gm,'horizontal'))
        set(ax,'xgrid','off','ygrid','on');
      elseif (strcmp(gm,'both'))
        set(ax,'xgrid','on','ygrid','on');
      endif
    catch
      if (!strcmp(gm,'inherit'))
        if (strcmp(gm,'none')), grid(ax,'off'); else grid(ax,'on'); endif
      endif
    end_try_catch
  endfor

  % Mantiene le tacche/griglia ma nasconde i numeri X nei pannelli superiori.
  if (p.stacked_bottom_xticks_only && n > 1)
    for k = 1:n-1
      try set(axs(k),'xticklabel',[]); catch; end_try_catch
    endfor
  endif

  % Layout normalizzato indipendente dalle scelte predefinite di subplot().
  left = p.stacked_margin_left_pct / 100;
  right = p.stacked_margin_right_pct / 100;
  topm = p.stacked_margin_top_pct / 100;
  bottom = p.stacked_margin_bottom_pct / 100;
  gap = p.stacked_gap_pct / 100;
  avail = 1 - topm - bottom - gap * max(0,n-1);
  width = 1 - left - right;
  if (avail > 0.10 && width > 0.20)
    h = avail / n;
    for k = 1:n
      y = 1 - topm - k*h - (k-1)*gap;
      try set(axs(k),'position',[left y width h]); catch; end_try_catch
    endfor
  endif

  % Allineamento delle label Y indipendente dalla larghezza delle tacche.
  % Non affidarsi all'autoposition della ylabel: alcuni toolkit la ricalcolano
  % durante drawnow/print in base all'estensione dei numeri dei tick.
  if (isfield(p,'stacked_align_ylabels') && p.stacked_align_ylabels)
    drawnow();
    for k = 1:n
      gxtxt_plot_align_ylabel(axs(k),p.stacked_ylabel_x);
    endfor
  endif
endfunction
