% SPDX-License-Identifier: GPL-3.0-or-later
function key = gxtxt_unit_dimension_key(unit)
  U=gxtxt_unit_parse(unit);
  if(!strcmp(U.kind,'linear')),key=[U.kind ':' U.semantic];return;endif
  f=sort(fieldnames(U.dims));if(isempty(f)),key='1';return;endif;parts={};for i=1:numel(f),e=U.dims.(f{i});if(e==1),parts{end+1}=f{i};else parts{end+1}=sprintf('%s^%d',f{i},e);endif;endfor;key=strjoin(parts,'*');
endfunction
