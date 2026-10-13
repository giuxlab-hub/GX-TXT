% SPDX-License-Identifier: GPL-3.0-or-later
% Common time-axis conversion for GX-TXT renderers.
% Input data are always expressed in seconds. The displayed unit can be
% selected globally or overridden for a single plot through the axis TSV.
function [x, unit, scale] = gxtxt_plot_time_values(x_seconds, graphKey, defaultUnit, p, explicitUnit)
  if (nargin < 2), graphKey=''; endif
  if (nargin < 3 || isempty(defaultUnit)), defaultUnit='s'; endif
  if (nargin < 4 || isempty(p)), p=gxtxt_plot_config(); endif
  if (nargin < 5), explicitUnit=''; endif

  unit = normalize_unit(explicitUnit);
  if (isempty(unit) || strcmp(unit,'inherit') || strcmp(unit,'auto'))
    unit = axis_override_unit(graphKey);
  endif
  if (isempty(unit) || strcmp(unit,'inherit') || strcmp(unit,'auto'))
    if (isfield(p,'time_unit')), unit=normalize_unit(p.time_unit); else unit='auto'; endif
  endif
  if (isempty(unit) || strcmp(unit,'inherit') || strcmp(unit,'auto'))
    unit = normalize_unit(defaultUnit);
  endif
  if (isempty(unit)), unit='s'; endif

  switch unit
    case 's',  scale=1;
    case 'ms', scale=1e3;
    case 'us', scale=1e6;
    case 'ns', scale=1e9;
    case 'min', scale=1/60;
    case 'h', scale=1/3600;
    case 'day', scale=1/86400;
    otherwise, unit='s'; scale=1;
  endswitch
  x = x_seconds .* scale;
endfunction

function unit = normalize_unit(unit)
  unit=lower(strtrim(unit));
  unit=strrep(unit,'µ','u'); unit=strrep(unit,'μ','u');
  if (strcmp(unit,'microseconds') || strcmp(unit,'microsecond')), unit='us'; endif
  if (strcmp(unit,'milliseconds') || strcmp(unit,'millisecond')), unit='ms'; endif
  if (strcmp(unit,'nanoseconds') || strcmp(unit,'nanosecond')), unit='ns'; endif
  if (strcmp(unit,'seconds') || strcmp(unit,'second')), unit='s'; endif
  if (any(strcmp(unit,{'minute','minutes','mins'}))), unit='min'; endif
  if (any(strcmp(unit,{'hour','hours','hr','hrs'}))), unit='h'; endif
  if (any(strcmp(unit,{'days'}))), unit='day'; endif
  if (!any(strcmp(unit,{'','inherit','auto','s','ms','us','ns','min','h','day'}))), unit=''; endif
endfunction

function unit = axis_override_unit(graphKey)
  unit='';
  if (isempty(strtrim(graphKey))), return; endif
  fn=strtrim(getenv('GXTXT_PLOT_AXIS_OVERRIDE_FILE'));
  if (isempty(fn) || exist(fn,'file') != 2), return; endif
  fid=fopen(fn,'r'); if (fid < 0), return; endif
  c=onCleanup(@() fclose(fid));
  h=fgetl(fid); if (!ischar(h)), return; endif
  headers=regexp(h,'\t','split');
  for k=1:numel(headers), headers{k}=lower(strtrim(headers{k})); endfor
  ik=find(strcmp(headers,'key'),1); ip=find(strcmp(headers,'panel'),1); iu=find(strcmp(headers,'time_unit'),1);
  if (isempty(ik) || isempty(ip) || isempty(iu)), return; endif
  while (true)
    l=fgetl(fid); if (!ischar(l)), break; endif
    if (isempty(strtrim(l))), continue; endif
    r=regexp(l,'\t','split');
    if (ik<=numel(r) && ip<=numel(r) && strcmp(strtrim(r{ik}),graphKey) && strcmp(strtrim(r{ip}),'*'))
      if (iu<=numel(r)), unit=normalize_unit(r{iu}); endif
      return;
    endif
  endwhile
endfunction
