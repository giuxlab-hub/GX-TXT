function options=pd_3d_options(cfg,base)
% Resolve per-variant 3D presentation budget without changing 2D settings.
% SPDX-License-Identifier: GPL-3.0-or-later
  options=base;prefix='plot.plot.dataset.xyz.';
  mode=lower(strtrim(gxtxt_ini_get(cfg,[prefix 'reduction_mode'],'inherit')));
  if(!isempty(mode)&&!strcmp(mode,'inherit'))
    if(!any(strcmp(mode,{'auto','none','stride','minmax'}))),error('plot.dataset: invalid 3D reduction mode');endif
    options.reduction_mode=mode;
  endif
  raw=strtrim(gxtxt_ini_get(cfg,[prefix 'target_points'],'inherit'));
  if(!isempty(raw)&&!strcmpi(raw,'inherit'))
    n=str2double(raw);if(!isfinite(n)||n!=fix(n)||n<100||n>8000000),error('plot.dataset: 3D target_points must be 100..8000000');endif
    options.target_points=n;
  endif
endfunction
