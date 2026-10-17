function contract=gxtxt_signal_constraints_v1(operation)
% Data shared with public discovery: no GUI-owned conditional science table.
% SPDX-License-Identifier: GPL-3.0-or-later
  persistent rows;
  if(isempty(rows))
    path=fullfile(fileparts(fileparts(mfilename('fullpath'))),'operation_constraints_v1.tsv');
    lines=strsplit(fileread(path),'\n');rows={};
    for k=1:numel(lines)
      line=lines{k};if(isempty(line)||line(1)=='#'),continue;endif
      fields=strsplit(line,'|','collapsedelimiters',false);
      if(numel(fields)!=4),error('GXTXT:Signal:InvalidContract','invalid conditional contract');endif
      rows{end+1}=fields;
    endfor
  endif
  contract=struct();
  for k=1:numel(rows)
    fields=rows{k};if(!strcmp(fields{1},operation)),continue;endif
    value=fields{4};
    switch(fields{3})
      case 'map'
        items=strsplit(value,';');mapped=struct();
        for j=1:numel(items)
          colon=find(items{j}==':',1);if(isempty(colon)),error('GXTXT:Signal:InvalidContract','invalid conditional map');endif
          mapped.(items{j}(1:colon-1))=items{j}(colon+1:end);
        endfor
        value=mapped;
      case 'list',value=strsplit(value,';');
      case 'scalar'
      otherwise,error('GXTXT:Signal:InvalidContract','unknown conditional type');
    endswitch
    contract.(fields{2})=value;
  endfor
endfunction
