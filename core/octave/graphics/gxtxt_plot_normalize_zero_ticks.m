% SPDX-License-Identifier: GPL-3.0-or-later
% Normalize only labels that are displayed as mathematical zero. Tick values
% and genuinely nonzero scientific labels are left untouched.
function gxtxt_plot_normalize_zero_ticks(fig)
  axs=findall(fig,'type','axes');
  for k=1:numel(axs)
    for axis_name={'x','y','z'}
      which=axis_name{1};
      try
        labels=get(axs(k),[which 'ticklabel']);
        if(isempty(labels)),continue;endif
        if(ischar(labels)),labels=cellstr(labels);endif
        changed=false;
        for j=1:numel(labels)
          old=labels{j};
          next=regexprep(old,'^([[:space:]]*)[+-](0(?:\.0*)?(?:[eE][+-]?[0-9]+)?)([[:space:]]*)$','$1$2$3');
          if(!strcmp(old,next)),labels{j}=next;changed=true;endif
        endfor
        if(changed),set(axs(k),[which 'ticklabel'],labels);endif
      catch
      end_try_catch
    endfor
  endfor
endfunction
