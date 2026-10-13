function a=gxtxt_ir_frame_annotations(F)
% Persist IR event labels as public PlotSpec data annotations.
% SPDX-License-Identifier: GPL-3.0-or-later
  a={};if(isempty(F.type)),return;endif
  t0=F.start_s(1);bit_index=0;header_seen=false;
  for k=1:numel(F.type)
    label=strtrim(F.label{k});if(isempty(label)),continue;endif
    if(strcmp(label,'HEADER'))
      if(header_seen),continue;endif
      header_seen=true;
    elseif(any(strcmp(label,{'0','1'})))
      if(mod(bit_index,8)!=0),bit_index++;continue;endif
      label=sprintf('b%d=%s',bit_index,label);
      bit_index++;
    endif
    x=((F.start_s(k)+F.end_s(k))/2-t0)*1000;
    y=double(strcmp(F.type{k},'MARK'))+0.12;
    a{end+1}=struct('type','text','axis','left','x',x,'y',y,'label',label);
  endfor
endfunction
