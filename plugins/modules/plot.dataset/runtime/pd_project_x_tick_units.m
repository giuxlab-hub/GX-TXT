function V=pd_project_x_tick_units(V,P,display_unit)
% Project the existing persistent shared numeric/caption pairs into the actual
% rendered X unit. This is presentation only; never modify the PlotSpec file.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isfield(V,'enabled')||!V.enabled||!isfield(V,'axes')||!isfield(V.axes,'x')),return;endif
  a=V.axes.x;
  if(!isfield(a,'tick_positions')||!isfield(a,'tick_labels')||isempty(a.tick_positions)),return;endif
  source_unit='';if(isfield(a,'display_unit')),source_unit=strtrim(a.display_unit);endif
  if(isempty(source_unit)||any(strcmpi(source_unit,{'auto','source','none','inherit'})))
    source_unit=P.series(1).x_meta.unit;
  endif
  if(strcmp(source_unit,display_unit)),return;endif
  positions=cellfun(@str2double,strsplit(a.tick_positions,';'));
  labels=strsplit(a.tick_labels,';');
  if(numel(positions)!=numel(labels)||any(!isfinite(positions))),error('plot.dataset: invalid persistent X tick pairs');endif
  positions=gxtxt_unit_convert(positions,source_unit,display_unit);
  if(any(!isfinite(positions))||any(abs(positions)>1e300)),error('plot.dataset: converted X tick positions exceed the finite presentation limit');endif
  tokens=arrayfun(@(x) sprintf('%.17g',x),positions,'UniformOutput',false);
  V.axes.x.tick_positions=strjoin(tokens,';');
endfunction
