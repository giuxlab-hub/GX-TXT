% SPDX-License-Identifier: GPL-3.0-or-later
% Strict, metadata-driven scalar conversion. elapsed_time/HMS is normalized
% to the public CORE base representation: numeric elapsed seconds.
function value=gxtxt_table_value_numeric(raw,meta)
  value=NaN; s=strtrim(raw);if(isempty(s)),return;endif
  kind='number';format='';decimal='.';unit='';
  if(isfield(meta,'value_kind')),kind=meta.value_kind;endif
  if(isfield(meta,'value_format')),format=meta.value_format;endif
  if(isfield(meta,'decimal_separator')),decimal=meta.decimal_separator;endif
  if(isfield(meta,'unit')),unit=meta.unit;endif
  if(strcmp(kind,'elapsed_time'))
    if(!strcmp(format,'hms')),error('GXTXT:TableValue','Unsupported elapsed-time format: %s',format);endif
    tok=regexp(s,'^([0-9]+):([0-5][0-9]):([0-5][0-9](?:[.,][0-9]+)?)$','tokens','once');
    if(isempty(tok)),return;endif
    if(!any(strcmp(unit,{'s','min','h'}))),error('GXTXT:TableValue','Unsupported elapsed-time unit: %s',unit);endif
    sec=str2double(strrep(tok{3},',','.'));
    % The declared unit remains source/schema metadata. Once an HMS value has
    % been parsed, every public numeric consumer receives seconds. Keeping the
    % base unit invariant prevents identical durations from changing value when
    % they arrive through different CORE data-access paths.
    value=str2double(tok{1})*3600+str2double(tok{2})*60+sec;
    return;
  endif
  if(strcmp(kind,'text')),return;endif
  if(strcmp(decimal,','))
    if(isempty(regexp(s,'^[+-]?(?:[0-9]+(?:,[0-9]*)?|,[0-9]+)(?:[eE][+-]?[0-9]+)?$','once'))),return;endif
    s=strrep(s,',','.');
  else
    if(isempty(regexp(s,'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$','once'))),return;endif
  endif
  value=str2double(s);
endfunction
