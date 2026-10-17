% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT: scrive un PNG su file temporaneo e sostituisce il target solo a stampa riuscita.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
function gxtxt_print_png_atomic(fig, target, dpi)
  if (nargin < 3 || !isfinite(dpi) || dpi < 72), dpi = 200; endif
  [d,n,e] = fileparts(target);
  if (isempty(d)), d = pwd(); endif
  if (exist(d,'dir') != 7), mkdir(d); endif
  if (isempty(e)), e = '.png'; endif
  nonce = sprintf('%08x', randi([0 2^31-1]));
  tmp = fullfile(d, ['.' n '.gxtxt_' nonce e]);
  unwind_protect
    % Framework-owned finalization: apply current per-plot Axes/grid overrides
    % after the plugin has finished drawing and immediately before export.
    % This deliberately does not alter legend configuration or rendering.
    try gxtxt_plot_finalize_output(fig,target); catch err; warning('GXTXT:PlotFinalize','Plot finalization failed for %s: %s',target,err.message); end_try_catch
    % Flush automatic ticks/labels/layout, then synchronize the inner data
    % rectangle once more at the last safe point before GNUplot export.
    try drawnow(); gxtxt_plot_sync_overlay_axes(fig); catch err; warning('GXTXT:OverlaySync','Dual-Y axis sync failed for %s: %s',target,err.message); end_try_catch
    % Reapply after all colorbar, legend and layout changes. The axis stores
    % the resolved public policy; no camera setting is changed here.
    axs=findall(fig,'type','axes');
    for k=1:numel(axs)
      mode='auto';ratio='';
      try mode=getappdata(axs(k),'gxtxt_plot_aspect_mode');catch;end_try_catch
      try ratio=getappdata(axs(k),'gxtxt_plot_aspect_ratio');catch;end_try_catch
      if(gxtxt_plot_axis_is_3d(axs(k)))
        gxtxt_plot_apply_aspect3d(axs(k),mode,ratio);
      elseif(strcmp(mode,'xy_equal'))
        gxtxt_plot_apply_aspect2d(axs(k),mode);
      endif
    endfor
    gxtxt_plot_normalize_zero_ticks(fig);
    background=[1 1 1];
    try background=get(fig,'color');catch;end_try_catch
    toolkit='';try toolkit=graphics_toolkit(fig);catch;end_try_catch
    transparent=ischar(background)&&strcmpi(strtrim(background),'none');
    if(transparent)
      if(!strcmpi(toolkit,'gnuplot')),error('GXTXT:TransparentBackground','Transparent PNG requires the GNUplot pngcairo renderer');endif
      prior_hardcopy=get(fig,'inverthardcopy');
      data_axes=[];prior_colors={};
      for k=1:numel(axs)
        tag='';try tag=lower(get(axs(k),'tag'));catch;end_try_catch
        if(!isempty(strfind(tag,'legend'))||!isempty(strfind(tag,'colorbar'))),continue;endif
        data_axes(end+1)=axs(k);prior_colors{end+1}=get(axs(k),'color');
        set(axs(k),'color','none');
      endfor
      unwind_protect
        set(fig,'inverthardcopy','off');
        % pngcairo uses a fixed raster resolution for paper sizes. Supply the
        % requested pixel dimensions explicitly so transparency preserves the
        % same image-size contract as the normal PNG renderer.
        prior_units=get(fig,'units');
        set(fig,'units','pixels');position=get(fig,'position');
        set(fig,'units',prior_units);
        print(fig,tmp,'-dpngcairo',sprintf('-S%d,%d',round(position(3)),round(position(4))));
      unwind_protect_cleanup
        set(fig,'inverthardcopy',prior_hardcopy);
        for k=1:numel(data_axes),try set(data_axes(k),'color',prior_colors{k});catch;end_try_catch;endfor
      end_unwind_protect
    elseif(strcmpi(toolkit,'gnuplot')&&isnumeric(background)&&numel(background)==3&&any(abs(background(:)'-[1 1 1])>1e-6))
      raw=fullfile(d,['.' n '.gxtxt_' nonce '.raw.png']);
      unwind_protect
        print(fig,raw,'-dpng',sprintf('-r%d',round(dpi)));
        rgb=round(255*min(1,max(0,background(:)')));
        hex=sprintf('#%02x%02x%02x',rgb(1),rgb(2),rgb(3));
        helper=fullfile(fileparts(mfilename('fullpath')),'gxtxt_png_background.py');
        command=sprintf('python3 %s %s %s %s',shell_quote(helper),shell_quote(raw),shell_quote(tmp),shell_quote(hex));
        [status,output]=system(command);
        if(status!=0),error('GXTXT:BackgroundRaster','%s',output);endif
      unwind_protect_cleanup
        if(exist(raw,'file')==2),unlink(raw);endif
      end_unwind_protect
    elseif(strcmpi(toolkit,'qt'))
      % Qt print otherwise replaces the configured figure background with
      % white. Preserve the same explicit color contract as the other CORE
      % renderers, restoring the caller's figure on success or export error.
      prior_hardcopy=get(fig,'inverthardcopy');
      unwind_protect
        set(fig,'inverthardcopy','off');
        print(fig,tmp,'-dpng',sprintf('-r%d',round(dpi)));
      unwind_protect_cleanup
        set(fig,'inverthardcopy',prior_hardcopy);
      end_unwind_protect
    else
      print(fig,tmp,'-dpng',sprintf('-r%d',round(dpi)));
    endif
    % Calibrate selection geometry against the exported raster itself. GNUplot
    % can change the inner plot rectangle without changing axes.Position.
    try
      gxtxt_plot_write_metadata(fig,target,tmp);
    catch err
      [meta_dir,meta_name,~]=fileparts(target);
      try unlink(fullfile(meta_dir,'.gxtxt_plotmeta',[meta_name '.ini']));catch;end_try_catch
      warning('GXTXT:PlotMetadata','Plot metadata failed for %s: %s',target,err.message);
    end_try_catch
    [ok,msg] = movefile(tmp,target,'f');
    if (!ok), error('GXTXT:PNGReplace','Unable to replace %s: %s',target,msg); endif
  unwind_protect_cleanup
    if (exist(tmp,'file') == 2), unlink(tmp); endif
  end_unwind_protect
endfunction

function q=shell_quote(value)
  q=['''' strrep(value,'''','''\''''') ''''];
endfunction
