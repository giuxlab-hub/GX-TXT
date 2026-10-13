% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT Pipeline - renderer for additional/cloned Stage Comparison plots.
% User-facing text is English. Stable filenames/IDs remain compatibility-safe.
function produced = gxtxt_compare_render_custom(specFile,outDir,names,labels,colors,t,vals,sigNorm,amplitude,refEdge,nominalCarrier,pstyle,pngDPI,idxPlot)
  produced = 0;
  if (nargin < 14 || isempty(strtrim(specFile)) || exist(specFile,'file') != 2)
    return;
  endif

  fid = fopen(specFile,'r');
  if (fid < 0), warning('GXTXT:CustomPlots','Unable to read %s',specFile); return; endif
  cleaner = onCleanup(@() fclose(fid));
  headerLine = fgetl(fid);
  if (!ischar(headerLine)), return; endif
  headers = regexp(headerLine,'\t','split');
  for hk=1:numel(headers), headers{hk}=lower(strtrim(headers{hk})); endfor

  while (true)
    line = fgetl(fid);
    if (!ischar(line)), break; endif
    if (isempty(strtrim(line))), continue; endif
    parts = regexp(line,'\t','split');

    order = round(str2double(tsv_value(headers,parts,'index','NaN')));
    enabled = str2double(tsv_value(headers,parts,'enabled','1'));
    type = lower(tsv_value(headers,parts,'type','full'));
    layout = lower(tsv_value(headers,parts,'layout','overlay'));
    rawNodes = tsv_value(headers,parts,'nodes','');
    legendMode = lower(tsv_value(headers,parts,'legend_mode','inherit'));
    legendLocation = lower(tsv_value(headers,parts,'legend_location','northeast'));
    legendOrientation = lower(tsv_value(headers,parts,'legend_orientation','inherit'));
    legendBorder = lower(tsv_value(headers,parts,'legend_border','inherit'));
    legendExternalMargin = tsv_value(headers,parts,'legend_external_margin_px','');
    titleText = tsv_value(headers,parts,'title','');
    xLabelText = tsv_value(headers,parts,'xlabel','');
    yLabelText = tsv_value(headers,parts,'ylabel','');
    yLabelTemplate = tsv_value(headers,parts,'ylabel_template','');
    timeUnit = lower(tsv_value(headers,parts,'time_unit','inherit'));

    pcustom = pstyle;
    if (!isempty(legendMode) && !strcmp(legendMode,'inherit')), pcustom.legend_mode = legendMode; endif
    if (!isempty(legendLocation) && !strcmp(legendLocation,'inherit')), pcustom.legend_location = legendLocation; endif
    if (!isempty(legendOrientation) && !strcmp(legendOrientation,'inherit')), pcustom.legend_orientation = legendOrientation; endif
    if (!isempty(legendBorder) && !strcmp(legendBorder,'inherit'))
      vb = str2double(legendBorder);
      if (isfinite(vb))
        pcustom.legend_border = (vb != 0);
        pcustom.legend_external_border = (vb != 0);
      endif
    endif
    vm = str2double(legendExternalMargin);
    if (isfinite(vm) && vm >= 0), pcustom.legend_external_margin_px = min(100,vm); endif
    if (!isfinite(order)), order = produced + 1; endif
    if (!isfinite(enabled) || enabled == 0), continue; endif

    idx = gxtxt_plot_selected_indices(names,rawNodes);
    if (isempty(idx))
      fprintf('[COMPARE] Additional plot %d skipped: no valid node (%s).\n',order,rawNodes);
      continue;
    endif

    if (strcmp(type,'full'))
      key=sprintf('compare.custom.%03d.full',order);
      if (isempty(titleText)), titleText = gxtxt_getenv_default('GXTXT_COMPARE_FULL_TITLE','GX-TXT-v3 - Synchronized analog signal chain'); endif
      [tx,tu]=gxtxt_plot_time_values(t(idxPlot),key,'s',pstyle,timeUnit);
      if (isempty(xLabelText)), xLabelText=gxtxt_getenv_default('GXTXT_COMPARE_FULL_XLABEL','Time [s]'); endif
      xLabelText=gxtxt_plot_time_label(xLabelText,tu);
      if (isempty(yLabelText)), yLabelText=gxtxt_getenv_default('GXTXT_COMPARE_FULL_YLABEL','Voltage [V]'); endif
      if (isempty(yLabelTemplate)), yLabelTemplate=gxtxt_getenv_default('GXTXT_COMPARE_FULL_YLABEL_TEMPLATE','{NODE} [V]'); endif
      f = gxtxt_plot_new_figure(pstyle);
      if (strcmp(layout,'stacked'))
        stackAxes = [];
        for q = 1:numel(idx)
          k = idx(q); subplot(numel(idx),1,q); stackAxes(end+1)=gca();
          args = {'linewidth',pstyle.line_width}; c = gxtxt_plot_color(colors{k},[]); if (!isempty(c)), args=[args {'color',c}]; endif
          plot(tx,vals{k}(idxPlot),'-',args{:}); gxtxt_plot_apply_axes(gca,pstyle);
          gxtxt_plot_text('ylabel',strrep(yLabelTemplate,'{NODE}',labels{k}));
          if (q == 1), gxtxt_plot_text('title',titleText); endif
          if (q == numel(idx)), gxtxt_plot_text('xlabel',xLabelText); endif
        endfor
        gxtxt_plot_finalize_stacked(stackAxes,pstyle); gxtxt_plot_axis_overrides(stackAxes,key,names(idx),pstyle);
      else
        hold on; labs={};
        for q = 1:numel(idx)
          k=idx(q); args={'linewidth',pstyle.line_width}; c=gxtxt_plot_color(colors{k},[]); if(!isempty(c)), args=[args {'color',c}]; endif
          plot(tx,vals{k}(idxPlot),'-',args{:}); labs{end+1}=labels{k};
        endfor
        gxtxt_plot_apply_axes(gca,pstyle); gxtxt_plot_text('xlabel',xLabelText); gxtxt_plot_text('ylabel',yLabelText);
        gxtxt_plot_text('title',titleText); gxtxt_plot_axis_overrides(gca,key,{},pstyle); gxtxt_plot_legend(labs,pcustom,key);
      endif
      filename = sprintf('10_custom_%03d_full.png',order);

    elseif (strcmp(type,'normalized'))
      key=sprintf('compare.custom.%03d.normalized',order);
      if (isempty(titleText)), titleText = gxtxt_getenv_default('GXTXT_COMPARE_NORMALIZED_TITLE','GX-TXT-v3 - Normalized waveform comparison'); endif
      [tx,tu]=gxtxt_plot_time_values(t(idxPlot),key,'s',pstyle,timeUnit);
      if (isempty(xLabelText)), xLabelText=gxtxt_getenv_default('GXTXT_COMPARE_NORMALIZED_XLABEL','Time [s]'); endif
      xLabelText=gxtxt_plot_time_label(xLabelText,tu);
      if (isempty(yLabelText)), yLabelText=gxtxt_getenv_default('GXTXT_COMPARE_NORMALIZED_YLABEL','Normalized excursion'); endif
      if (isempty(yLabelTemplate)), yLabelTemplate='{NODE}'; endif
      f=gxtxt_plot_new_figure(pstyle);
      if (strcmp(layout,'stacked'))
        stackAxes=[];
        for q=1:numel(idx)
          k=idx(q); subplot(numel(idx),1,q); stackAxes(end+1)=gca();
          args={'linewidth',pstyle.line_width}; c=gxtxt_plot_color(colors{k},[]); if(!isempty(c)),args=[args {'color',c}];endif
          plot(tx,sigNorm{k}(idxPlot),'-',args{:}); gxtxt_plot_apply_axes(gca,pstyle);
          gxtxt_plot_text('ylabel',strrep(yLabelTemplate,'{NODE}',labels{k}));
          if(q==1),gxtxt_plot_text('title',titleText);endif; if(q==numel(idx)),gxtxt_plot_text('xlabel',xLabelText);endif
        endfor
        gxtxt_plot_finalize_stacked(stackAxes,pstyle); gxtxt_plot_axis_overrides(stackAxes,key,names(idx),pstyle);
      else
        hold on; labs={};
        for q=1:numel(idx)
          k=idx(q); args={'linewidth',pstyle.line_width}; c=gxtxt_plot_color(colors{k},[]); if(!isempty(c)),args=[args {'color',c}];endif
          plot(tx,sigNorm{k}(idxPlot),'-',args{:}); labs{end+1}=labels{k};
        endfor
        gxtxt_plot_apply_axes(gca,pstyle); gxtxt_plot_text('xlabel',xLabelText); gxtxt_plot_text('ylabel',yLabelText);
        gxtxt_plot_text('title',titleText); gxtxt_plot_axis_overrides(gca,key,{},pstyle); gxtxt_plot_legend(labs,pcustom,key);
      endif
      filename = sprintf('10_custom_%03d_normalized.png',order);

    elseif (strcmp(type,'carrier'))
      key=sprintf('compare.custom.%03d.carrier',order);
      if (!isfinite(refEdge))
        fprintf('[COMPARE] Additional plot %d skipped: carrier reference unavailable.\n',order);
        continue;
      endif
      T0=1/nominalCarrier; t1=max(t(1),refEdge-2*T0); t2=min(t(end),refEdge+12*T0); iz=find(t>=t1 & t<=t2);
      if (isempty(iz)), continue; endif
      if (isempty(titleText)), titleText = gxtxt_getenv_default('GXTXT_COMPARE_CARRIER_TITLE','GX-TXT-v3 - Carrier detail along the signal chain'); endif
      [tx,tu]=gxtxt_plot_time_values(t(iz),key,'us',pstyle,timeUnit);
      if (isempty(xLabelText)), xLabelText=gxtxt_getenv_default('GXTXT_COMPARE_CARRIER_XLABEL','Time [us]'); endif
      xLabelText=gxtxt_plot_time_label(xLabelText,tu);
      if (isempty(yLabelText)), yLabelText=gxtxt_getenv_default('GXTXT_COMPARE_CARRIER_YLABEL','Normalized excursion'); endif
      if (isempty(yLabelTemplate)), yLabelTemplate='{NODE}'; endif
      f=gxtxt_plot_new_figure(pstyle);
      if (strcmp(layout,'stacked'))
        stackAxes=[];
        for q=1:numel(idx)
          k=idx(q); subplot(numel(idx),1,q); stackAxes(end+1)=gca();
          args={'linewidth',pstyle.line_width}; c=gxtxt_plot_color(colors{k},[]); if(!isempty(c)),args=[args {'color',c}];endif
          plot(tx,sigNorm{k}(iz),'-',args{:}); gxtxt_plot_apply_axes(gca,pstyle);
          gxtxt_plot_text('ylabel',strrep(yLabelTemplate,'{NODE}',labels{k}));
          if(q==1),gxtxt_plot_text('title',titleText);endif; if(q==numel(idx)),gxtxt_plot_text('xlabel',xLabelText);endif
        endfor
        gxtxt_plot_finalize_stacked(stackAxes,pstyle); gxtxt_plot_axis_overrides(stackAxes,key,names(idx),pstyle);
      else
        hold on; labs={};
        for q=1:numel(idx)
          k=idx(q); args={'linewidth',pstyle.line_width}; c=gxtxt_plot_color(colors{k},[]); if(!isempty(c)),args=[args {'color',c}];endif
          plot(tx,sigNorm{k}(iz),'-',args{:}); labs{end+1}=labels{k};
        endfor
        gxtxt_plot_apply_axes(gca,pstyle); gxtxt_plot_text('xlabel',xLabelText); gxtxt_plot_text('ylabel',yLabelText);
        gxtxt_plot_text('title',titleText); gxtxt_plot_axis_overrides(gca,key,{},pstyle); gxtxt_plot_legend(labs,pcustom,key);
      endif
      filename = sprintf('10_custom_%03d_carrier.png',order);

    elseif (strcmp(type,'amplitude'))
      key=sprintf('compare.custom.%03d.amplitude',order);
      if (isempty(titleText)), titleText = gxtxt_getenv_default('GXTXT_COMPARE_AMPLITUDE_TITLE','GX-TXT-v3 - Signal excursion at measured nodes'); endif
      if (isempty(yLabelText)), yLabelText=gxtxt_getenv_default('GXTXT_COMPARE_AMPLITUDE_YLABEL','Excursion from baseline [V]'); endif
      f=gxtxt_plot_new_figure(pstyle); hold on; labs={};
      for q=1:numel(idx)
        k=idx(q); c=gxtxt_plot_color(colors{k},[]);
        if (isempty(c)), bar(q,amplitude(k),0.75); else bar(q,amplitude(k),0.75,'facecolor',c); endif
        labs{end+1}=labels{k};
      endfor
      gxtxt_plot_apply_axes(gca,pstyle); set(gca,'xtick',1:numel(idx),'xticklabel',labs);
      try set(gca,'xticklabelrotation',20); catch; end_try_catch
      gxtxt_plot_text('ylabel',yLabelText); gxtxt_plot_text('title',titleText); gxtxt_plot_axis_overrides(gca,key,{},pstyle);
      filename = sprintf('10_custom_%03d_amplitude.png',order);

    else
      fprintf('[COMPARE] Additional plot %d skipped: unknown type %s.\n',order,type);
      continue;
    endif
    gxtxt_print_png_atomic(f,fullfile(outDir,filename),pngDPI); close(f);
    produced += 1;
  endwhile
  fprintf('[COMPARE] Additional plots produced: %d.\n',produced);
endfunction

function v = tsv_value(headers,parts,name,defaultValue)
  v = defaultValue;
  idx = find(strcmp(headers,name),1);
  if (isempty(idx) || idx > numel(parts)), return; endif
  v = strtrim(parts{idx});
  if (isempty(v)), v = defaultValue; endif
endfunction
