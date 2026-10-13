function [keys,numeric_ok]=pd_3d_family_values(chunk,variable_id)
% Format provider-neutral typed Family values for the existing 3D group policy.
% The only Dataset reader remains CORE Table Stream v3.
% SPDX-License-Identifier: GPL-3.0-or-later
  numeric_ok=true;
  if(isempty(variable_id)),keys=repmat({'__single__'},chunk.nrows,1);numeric_ok=false;return;endif
  values=gxtxt_table_chunk_column(chunk,variable_id);
  if(iscell(values)),keys=values;return;endif
  if(!(isnumeric(values)||islogical(values))),error('plot.dataset: unsupported typed Family column');endif
  keys=cell(chunk.nrows,1);
  if(isinteger(values))
    unsigned=strncmp(class(values),'uint',4);
    for i=1:chunk.nrows
      if(unsigned),keys{i}=sprintf('%u',values(i));else keys{i}=sprintf('%d',values(i));endif
    endfor
    % Exact integer keys outside double precision must not be merged by str2double.
    limit=cast(flintmax,class(values));
    numeric_ok=!any(values>limit);
    if(!unsigned),numeric_ok=numeric_ok&&!any(values < -limit);endif
  else
    for i=1:chunk.nrows
      if(isfinite(values(i))),keys{i}=sprintf('%.17g',double(values(i)));else keys{i}='';endif
    endfor
  endif
endfunction
