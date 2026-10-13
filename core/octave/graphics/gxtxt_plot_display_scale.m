% SPDX-License-Identifier: GPL-3.0-or-later
% Unit-aware display scaling for plots. Scientific data are never modified.
% [out, display_unit, factor] = gxtxt_plot_display_scale(values,unit,mode)
% mode: 'auto' (default), 'none', or an explicit display unit.
function [out, display_unit, factor] = gxtxt_plot_display_scale(values,unit,mode)
  if(nargin<3||isempty(mode)),mode='auto';endif
  unit=strtrim(unit);mode=strtrim(mode);out=values;display_unit=unit;factor=1;
  if(any(strcmpi(mode,{'source','inherit'}))),mode='none';endif
  if(isempty(unit)||strcmpi(mode,'none')),return;endif
  finite=values(isfinite(values));if(isempty(finite)),return;endif
  try
    U=gxtxt_unit_parse(unit);
    if(any(strcmp(U.kind,{'registered','opaque'})))
      if(strcmpi(mode,'auto')||strcmp(mode,unit)),display_unit=unit;factor=1;return;endif
      out=gxtxt_unit_convert(values,unit,mode);display_unit=mode;
      factor=gxtxt_unit_convert(1,unit,mode)-gxtxt_unit_convert(0,unit,mode);
      return;
    endif
    if(strcmp(U.kind,'semantic'))
      if(strcmpi(mode,'auto')||strcmp(mode,unit)),display_unit=unit;factor=1;return;endif
      error('GXTXT:PlotUnit','semantic/non-linear unit %s is identity-only; requested %s',unit,mode);
    endif
    % Time has useful non-SI display units in addition to SI prefixes.
    if(gxtxt_unit_compatible(unit,'s'))
      sec=gxtxt_unit_convert(values,unit,'s'); f=sec(isfinite(sec)); mag=max(abs(f));
      target=mode;if(strcmpi(target,'auto')),target=choose_time_unit(mag);endif
      [out,seconds_to_display]=from_seconds(sec,target);display_unit=target;
      % Metadata consumers need source -> display, even when the source
      % itself is a subsecond unit. from_seconds only knows seconds -> display.
      source_to_seconds=gxtxt_unit_convert(1,unit,'s')-gxtxt_unit_convert(0,unit,'s');
      factor=source_to_seconds*seconds_to_display;return;
    endif
    bases={'A','V','Hz','W','J','m','g'};
    base='';for i=1:numel(bases),if(gxtxt_unit_compatible(unit,bases{i})),base=bases{i};break;endif;endfor
    if(isempty(base)),return;endif
    basev=gxtxt_unit_convert(values,unit,base);f=basev(isfinite(basev));mag=max(abs(f));
    target=mode;if(strcmpi(target,'auto')),target=[choose_prefix(mag) base];endif
    out=gxtxt_unit_convert(values,unit,target);display_unit=target;
    % Factor is a unit transform, not a data-derived ratio; it must remain
    % correct even for an all-zero series.
    factor=gxtxt_unit_convert(1,unit,target);
  catch
    out=values;display_unit=unit;factor=1;
  end_try_catch
endfunction
function u=choose_time_unit(m)
  if(m>=172800),u='day';elseif(m>=7200),u='h';elseif(m>=120),u='min';elseif(m>=1),u='s';elseif(m>=1e-3),u='ms';elseif(m>=1e-6),u='us';else u='ns';endif
endfunction
function [v,f]=from_seconds(sec,u)
  switch lower(u)
    case 'day',f=1/86400;
    case 'h',f=1/3600;
    case 'min',f=1/60;
    case 's',f=1;
    case 'ms',f=1e3;
    case {'us','µs','μs'},f=1e6;u='us';
    case 'ns',f=1e9;
    otherwise,error('GXTXT:PlotUnit','unsupported time display unit: %s',u);
  endswitch
  v=sec.*f;
endfunction
function p=choose_prefix(m)
  if(m==0||!isfinite(m)),p='';elseif(m>=1e9),p='G';elseif(m>=1e6),p='M';elseif(m>=1e3),p='k';elseif(m>=1),p='';elseif(m>=1e-3),p='m';elseif(m>=1e-6),p='u';elseif(m>=1e-9),p='n';else p='p';endif
endfunction
