% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT: posiziona una ylabel in modo realmente manuale e riproducibile.
% Usa un text object normalizzato invece della posizione automatica della ylabel,
% che con alcuni toolkit Octave viene ricalcolata in funzione della larghezza dei tick.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
function h = gxtxt_plot_align_ylabel(ax,x)
  h = [];
  if (nargin < 2 || isempty(ax) || !isfinite(x)), return; endif
  try
    yh = get(ax,'ylabel');
    s = get(yh,'string');
    old = findobj(ax,'tag','GXTXT_ALIGNED_YLABEL');
    if (isempty(s) && !isempty(old))
      try s = get(old(1),'string'); catch; s=''; end_try_catch
    endif
    if (isempty(s)), return; endif

    fs = get(yh,'fontsize'); fn = get(yh,'fontname'); fw = get(yh,'fontweight');
    fa = get(yh,'fontangle'); c = get(yh,'color');
    try interp = get(yh,'interpreter'); catch; interp='none'; end_try_catch
    if (!isempty(old)), delete(old); endif

    % La ylabel nativa resta vuota: evita che il toolkit la riposizioni al print().
    set(yh,'string','');
    % Importante: crea prima l'oggetto e imposta Units=normalized PRIMA
    % della posizione. Su alcuni toolkit, passare x/y a text() e cambiare
    % Units nella stessa chiamata puo' convertire la posizione iniziale dalle
    % data-units, ottenendo X diverse fra pannelli con scale differenti.
    h = text(ax,0,0,s);
    set(h, ...
      'units','normalized', ...
      'position',[x 0.5 0], ...
      'rotation',90, ...
      'horizontalalignment','center', ...
      'verticalalignment','middle', ...
      'clipping','off', ...
      'fontsize',fs, ...
      'fontname',fn, ...
      'fontweight',fw, ...
      'fontangle',fa, ...
      'color',c, ...
      'interpreter',interp, ...
      'tag','GXTXT_ALIGNED_YLABEL');
  catch err
    warning('GXTXT:YLabelAlign','Y-label alignment was not applied: %s',err.message);
  end_try_catch
endfunction
