% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT pipeline - configurazione grafica Octave server-side.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% GNU GPL v3 or later.

function info = gxtxt_setup_graphics()
  mode = lower(strtrim(getenv('GXTXT_GRAPHICS_MODE')));
  if (isempty(mode)), mode = 'headless'; endif

  requested = lower(strtrim(getenv('GXTXT_GRAPHICS_TOOLKIT')));
  if (isempty(requested)), requested = 'auto'; endif

  visRaw = lower(strtrim(getenv('GXTXT_GRAPHICS_VISIBLE')));
  visible = any(strcmp(visRaw, {'1','true','yes','on'}));

  dispValue = getenv('DISPLAY');
  available = available_graphics_toolkits();

  if (strcmp(requested,'auto'))
    if (strcmp(mode,'headless') || isempty(dispValue))
      preferred = {'gnuplot','qt','fltk'};
    else
      preferred = {'qt','fltk','gnuplot'};
    endif
    toolkit = '';
    for k = 1:numel(preferred)
      if (any(strcmp(available,preferred{k})))
        toolkit = preferred{k};
        break;
      endif
    endfor
  else
    toolkit = requested;
  endif

  if (isempty(toolkit) || !any(strcmp(available,toolkit)))
    error('Requested graphics toolkit is unavailable: %s. Available: %s', ...
          toolkit,strjoin(available,', '));
  endif

  % A local Qt renderer needs a direct GLX context. Shells used for remote X
  % forwarding can retain LIBGL_ALWAYS_INDIRECT=1 after DISPLAY changes to a
  % local server. On Debian Qt6 this can leave a null OpenGL context and crash
  % Octave during print(), before an Octave exception can be raised. Apply the
  % local policy before toolkit/figure creation; remote display policy remains
  % owned by its caller. Do not switch renderers or alter scientific geometry.
  context_policy='inherited';
  if(strcmp(toolkit,'qt')&&!isempty(regexp(dispValue,'^(:|unix:)[0-9]+(\.[0-9]+)?$','once')))
    setenv('LIBGL_ALWAYS_INDIRECT','0');
    context_policy='local_direct';
  endif
  graphics_toolkit(toolkit);
  if (visible)
    set(0,'defaultfigurevisible','on');
  else
    set(0,'defaultfigurevisible','off');
  endif

  info.mode = mode;
  info.toolkit = toolkit;
  info.display = dispValue;
  info.visible = visible;
  info.context_policy = context_policy;

  if (isempty(dispValue)), dshow = '<empty>'; else dshow = dispValue; endif
  fprintf('[GRAPHICS] mode=%s toolkit=%s DISPLAY=%s figure_visible=%d context_policy=%s\n', ...
          mode,toolkit,dshow,visible,context_policy);
endfunction
