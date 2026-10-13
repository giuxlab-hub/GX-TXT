% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT generic per-graph/per-panel axes override service.
% v0.9.3.3 additively extends the historical 2D contract with first-class Z,
% persistent 3D view and common color presentation.
function gxtxt_plot_axis_overrides(axs, graphKey, panelNames, p, runtimeCfg)
  if (nargin < 2 || isempty(axs) || isempty(strtrim(graphKey))), return; endif
  if (nargin < 3 || isempty(panelNames)), panelNames = {}; endif
  if (nargin < 4), p = gxtxt_plot_config(); endif
  if (nargin < 5), runtimeCfg = struct(); endif

  useRuntime = cfg_has(runtimeCfg,['axis.' graphKey '.enabled']);
  headers = {}; rows = {}; grow = {};
  if (useRuntime)
    getv=@(name,def) cfg_get(runtimeCfg,['axis.' graphKey '.' name],def);
    getn=@(name) cfg_num(runtimeCfg,['axis.' graphKey '.' name]);
    en=str2double(getv('enabled','1'));
    plot_background=strtrim(getv('background',''));
    text_override={strtrim(getv('title','')),strtrim(getv('x_label','')),strtrim(getv('y_label','')),strtrim(getv('y2_label','')),strtrim(getv('z_label',''))};
    xmin=getn('x_min');xmax=getn('x_max');xstep=getn('x_step');xfmt=cleanfmt(getv('x_format','inherit'));
    yminG=getn('y_min');ymaxG=getn('y_max');ystepG=getn('y_step');gyfmt=cleanfmt(getv('y_format','inherit'));
    y2minG=getn('y2_min');y2maxG=getn('y2_max');y2stepG=getn('y2_step');gy2fmt=cleanfmt(getv('y2_format','inherit'));
    zmin=getn('z_min');zmax=getn('z_max');zstep=getn('z_step');zfmt=cleanfmt(getv('z_format','inherit'));
    zscale=lower(strtrim(getv('z_scale','inherit')));zgrid=lower(strtrim(getv('zgrid','inherit')));zlabeltxt=strtrim(getv('z_label',''));
    xscale=lower(strtrim(getv('x_scale','inherit')));yscale=lower(strtrim(getv('y_scale','inherit')));y2scale=lower(strtrim(getv('y2_scale','inherit')));
    gxgrid=lower(strtrim(getv('xgrid','inherit')));gygrid=lower(strtrim(getv('ygrid','inherit')));gysource=lower(strtrim(getv('ygrid_source','inherit')));ggridcolor=strtrim(getv('grid_color',''));
    align=lower(strtrim(getv('align_ylabels','inherit')));gylabelx=getn('ylabel_x');
    az=getn('view_azimuth');el=getn('view_elevation');projection=lower(strtrim(getv('projection','inherit')));
  else
    fn=strtrim(getenv('GXTXT_PLOT_AXIS_OVERRIDE_FILE'));if(isempty(fn)||exist(fn,'file')!=2),return;endif
    [headers,rows]=read_tsv(fn);if(isempty(headers)||isempty(rows)),return;endif
    grow=find_row(headers,rows,graphKey,'*');if(isempty(grow)),return;endif
    en=str2double(val(headers,grow,'enabled','1'));
    plot_background=strtrim(val(headers,grow,'background',''));
    text_override={strtrim(val(headers,grow,'title','')),strtrim(val(headers,grow,'x_label','')),strtrim(val(headers,grow,'y_label','')),strtrim(val(headers,grow,'y2_label','')),strtrim(val(headers,grow,'z_label',''))};
    xmin=numval(headers,grow,'x_min');xmax=numval(headers,grow,'x_max');xstep=numval(headers,grow,'x_step');xfmt=cleanfmt(val(headers,grow,'x_format','inherit'));
    yminG=numval(headers,grow,'y_min');ymaxG=numval(headers,grow,'y_max');ystepG=numval(headers,grow,'y_step');gyfmt=cleanfmt(val(headers,grow,'y_format','inherit'));
    y2minG=numval(headers,grow,'y2_min');y2maxG=numval(headers,grow,'y2_max');y2stepG=numval(headers,grow,'y2_step');gy2fmt=cleanfmt(val(headers,grow,'y2_format','inherit'));
    zmin=numval(headers,grow,'z_min');zmax=numval(headers,grow,'z_max');zstep=numval(headers,grow,'z_step');zfmt=cleanfmt(val(headers,grow,'z_format','inherit'));
    zscale=lower(strtrim(val(headers,grow,'z_scale','inherit')));zgrid=lower(strtrim(val(headers,grow,'zgrid','inherit')));zlabeltxt=strtrim(val(headers,grow,'z_label',''));
    xscale=lower(strtrim(val(headers,grow,'x_scale','inherit')));yscale=lower(strtrim(val(headers,grow,'y_scale','inherit')));y2scale=lower(strtrim(val(headers,grow,'y2_scale','inherit')));
    gxgrid=lower(strtrim(val(headers,grow,'xgrid','inherit')));gygrid=lower(strtrim(val(headers,grow,'ygrid','inherit')));gysource=lower(strtrim(val(headers,grow,'ygrid_source','inherit')));ggridcolor=strtrim(val(headers,grow,'grid_color',''));
    align=lower(strtrim(val(headers,grow,'align_ylabels','inherit')));gylabelx=numval(headers,grow,'ylabel_x');
    az=numval(headers,grow,'view_azimuth');el=numval(headers,grow,'view_elevation');projection=lower(strtrim(val(headers,grow,'projection','inherit')));
  endif

  % Background is independent of the Axes override enable switch. The
  % inherited figure color was already set from global/module graphics.
  if(!isempty(plot_background)&&!strcmpi(plot_background,'inherit'))
    try
      if(strcmpi(plot_background,'transparent'))
        set(ancestor(axs(1),'figure'),'color','none');
      else
        set(ancestor(axs(1),'figure'),'color',gxtxt_plot_color(plot_background,[1 1 1]));
      endif
    catch;end_try_catch
  endif
  % Presentation text is independent of the numeric Axes enable switch.
  % Plot Dataset consumes the same fields while resolving its provider labels.
  if(!strncmp(graphKey,'plot.dataset',12))
    if(!isempty(text_override{1})),title(axs(1),text_override{1},'interpreter','none');endif
    if(!isempty(text_override{2})),xlabel(axs(end),text_override{2},'interpreter','none');endif
    if(!isempty(text_override{3})),ylabel(axs(1),text_override{3},'interpreter','none');endif
    if(!isempty(text_override{5})&&gxtxt_plot_axis_is_3d(axs(1))),zlabel(axs(1),text_override{5},'interpreter','none');endif
    if(!isempty(text_override{4}))
      try figText=ancestor(axs(1),'figure');ovText=findall(figText,'type','axes','tag','gxtxt_overlay_yaxis');if(!isempty(ovText)),ylabel(ovText(1),text_override{4},'interpreter','none');endif;catch;end_try_catch
    endif
  endif
  if(isfinite(en)&&en==0),return;endif

  axs=axs(:)';n=numel(axs);isStacked=(n>1||!isempty(panelNames));
  y2min=NaN;y2max=NaN;y2step=NaN;py2fmt='';
  ygridSources=cell(1,n);gridColors=cell(1,n);
  % Per-axis copies of the resolved panel Y2 state. The scalars above remain
  % for the historical single-overlay path; the arrays let a stacked plot keep
  % each panel's own secondary Y instead of the last panel resolved.
  y2minP=nan(1,n);y2maxP=nan(1,n);y2stepP=nan(1,n);py2fmtP=cell(1,n);
  for k=1:n
    y2minP(k)=NaN;y2maxP(k)=NaN;y2stepP(k)=NaN;py2fmtP{k}='';
    y2min=NaN;y2max=NaN;y2step=NaN;py2fmt='';
    ax=axs(k);
    apply_axis_range(ax,'x',xmin,xmax,xstep,xfmt);apply_axis_range(ax,'y',yminG,ymaxG,ystepG,gyfmt);
    apply_axis_scale(ax,'x',xscale);apply_axis_scale(ax,'y',yscale);
    apply_grid(ax,gxgrid,gygrid);apply_grid_color(ax,ggridcolor);
    effectiveYSource=gysource;effectiveGridColor=ggridcolor;
    if(gxtxt_plot_axis_is_3d(ax))
      apply_axis_range(ax,'z',zmin,zmax,zstep,zfmt);
      if(strcmp(zscale,'linear')||strcmp(zscale,'log')),try set(ax,'zscale',zscale);catch;end_try_catch;endif
      if(strcmp(zgrid,'on')||strcmp(zgrid,'off')),try set(ax,'zgrid',zgrid);catch;end_try_catch;endif
      if(!isempty(zlabeltxt)),try zlabel(ax,zlabeltxt);catch;end_try_catch;endif
      if(isfinite(az)||isfinite(el))
        try v=get(ax,'view');if(!isfinite(az)),az=v(1);endif;if(!isfinite(el)),el=v(2);endif;view(ax,az,el);catch;end_try_catch
      endif
      if(any(strcmp(projection,{'orthographic','perspective'}))),try set(ax,'projection',projection);catch;end_try_catch;endif
    endif

    pn='';if(k<=numel(panelNames)),pn=panelNames{k};endif
    pylabelx=NaN;
    if(useRuntime)
      pidx=runtime_panel_index(runtimeCfg,graphKey,pn);
      if(pidx>0)
        base=sprintf('axis.%s.panel%d_',graphKey,pidx);
        ymin=cfg_num(runtimeCfg,[base 'y_min']);ymax=cfg_num(runtimeCfg,[base 'y_max']);ystep=cfg_num(runtimeCfg,[base 'y_step']);pyfmt=cleanfmt(cfg_get(runtimeCfg,[base 'y_format'],'inherit'));
        y2min=cfg_num(runtimeCfg,[base 'y2_min']);y2max=cfg_num(runtimeCfg,[base 'y2_max']);y2step=cfg_num(runtimeCfg,[base 'y2_step']);py2fmt=cleanfmt(cfg_get(runtimeCfg,[base 'y2_format'],'inherit'));
        y2minP(k)=y2min;y2maxP(k)=y2max;y2stepP(k)=y2step;py2fmtP{k}=py2fmt;
        pxgrid=lower(strtrim(cfg_get(runtimeCfg,[base 'xgrid'],'inherit')));pygrid=lower(strtrim(cfg_get(runtimeCfg,[base 'ygrid'],'inherit')));pysource=lower(strtrim(cfg_get(runtimeCfg,[base 'ygrid_source'],'inherit')));pgridcolor=strtrim(cfg_get(runtimeCfg,[base 'grid_color'],''));pylabelx=cfg_num(runtimeCfg,[base 'ylabel_x']);
        apply_axis_range(ax,'y',ymin,ymax,ystep,pyfmt);apply_grid(ax,pxgrid,pygrid);apply_grid_color(ax,pgridcolor);
        if(!strcmp(pysource,'inherit')),effectiveYSource=pysource;endif;if(!isempty(pgridcolor)),effectiveGridColor=pgridcolor;endif
      endif
    else
      prow=find_row(headers,rows,graphKey,pn);
      if(!isempty(prow))
        ymin=numval(headers,prow,'y_min');ymax=numval(headers,prow,'y_max');ystep=numval(headers,prow,'y_step');pyfmt=cleanfmt(val(headers,prow,'y_format','inherit'));
        y2min=numval(headers,prow,'y2_min');y2max=numval(headers,prow,'y2_max');y2step=numval(headers,prow,'y2_step');py2fmt=cleanfmt(val(headers,prow,'y2_format','inherit'));
        y2minP(k)=y2min;y2maxP(k)=y2max;y2stepP(k)=y2step;py2fmtP{k}=py2fmt;
        pxgrid=lower(strtrim(val(headers,prow,'xgrid','inherit')));pygrid=lower(strtrim(val(headers,prow,'ygrid','inherit')));pysource=lower(strtrim(val(headers,prow,'ygrid_source','inherit')));pgridcolor=strtrim(val(headers,prow,'grid_color',''));pylabelx=numval(headers,prow,'ylabel_x');
        apply_axis_range(ax,'y',ymin,ymax,ystep,pyfmt);apply_grid(ax,pxgrid,pygrid);apply_grid_color(ax,pgridcolor);
        if(!strcmp(pysource,'inherit')),effectiveYSource=pysource;endif;if(!isempty(pgridcolor)),effectiveGridColor=pgridcolor;endif
      endif
    endif
    ygridSources{k}=effectiveYSource;gridColors{k}=effectiveGridColor;
    doAlign=false;if(any(strcmp(align,{'1','on','yes'}))),doAlign=true;elseif(any(strcmp(align,{'0','off','no'}))),doAlign=false;elseif(isStacked&&isfield(p,'stacked_align_ylabels')),doAlign=p.stacked_align_ylabels;endif
    yx=pylabelx;if(!isfinite(yx)),yx=gylabelx;endif;if(!isfinite(yx)&&isfield(p,'stacked_ylabel_x')),yx=p.stacked_ylabel_x;endif;if(doAlign&&isfinite(yx)),set_ylabel_x(ax,yx);endif
  endfor

  % Multi-Y Axis Plot API v1 remains a distinct 2D overlay contract.
  % A figure that declares stacked panel overlays (gxtxt_panel_<n>_overlay_yaxis,
  % v0.9.7.50) resolves one overlay per panel, the same pairing already used by
  % gxtxt_plot_sync_overlay_axes(). Every other figure keeps the historical
  % single-overlay behavior unchanged.
  try
    fig=ancestor(axs(1),'figure');
    if(has_panel_overlays(fig))
      for k=1:n
        ax2=overlay_for_axis(fig,axs(k));
        if(isempty(ax2)),apply_y_grid_source(axs(k),[],ygridSources{k});continue;endif
        apply_axis_scale(ax2,'x',xscale);apply_axis_scale(ax2,'y',y2scale);
        apply_axis_range(ax2,'y',y2minG,y2maxG,y2stepG,gy2fmt);
        if(isfinite(y2minP(k))||isfinite(y2maxP(k))||isfinite(y2stepP(k))||!isempty(py2fmtP{k})),apply_axis_range(ax2,'y',y2minP(k),y2maxP(k),y2stepP(k),py2fmtP{k});endif
        apply_y_grid_source(axs(k),ax2,ygridSources{k});apply_grid_color(ax2,gridColors{k});
      endfor
    else
      ov=findall(fig,'type','axes','tag','gxtxt_overlay_yaxis');
      if(!isempty(ov))
        ax2=ov(1);apply_axis_scale(ax2,'x',xscale);apply_axis_scale(ax2,'y',y2scale);apply_axis_range(ax2,'y',y2minG,y2maxG,y2stepG,gy2fmt);
        if(n==1&&(isfinite(y2minP(1))||isfinite(y2maxP(1))||isfinite(y2stepP(1))||!isempty(py2fmtP{1}))),apply_axis_range(ax2,'y',y2minP(1),y2maxP(1),y2stepP(1),py2fmtP{1});endif
        apply_y_grid_source(axs(1),ax2,ygridSources{1});apply_grid_color(ax2,gridColors{1});
      else
        for k=1:n,apply_y_grid_source(axs(k),[],ygridSources{k});endfor
      endif
    endif
  catch err
    warning('GXTXT:Y2Override','secondary Y override was not applied: %s',err.message);
  end_try_catch

  % Apply common color settings only when the axes are 3D or a C mapping was
  % explicitly published. This avoids introducing a colorbar on ordinary 2D plots.
  try
    ax0=axs(1);if(gxtxt_plot_axis_is_3d(ax0)||axis_has_color_metadata(ax0))
      if(useRuntime)
        cs=gxtxt_plot_color_settings(runtimeCfg,graphKey,p);
        cb_choice=strtrim(cfg_get(runtimeCfg,['axis.' graphKey '.colorbar_visible'],'inherit'));
      else
        cs=gxtxt_plot_color_settings(struct(),graphKey,p);
        q=strtrim(val(headers,grow,'colormap',''));if(!isempty(q)&&!strcmpi(q,'inherit')),cs.colormap=q;endif
        cb_choice=strtrim(val(headers,grow,'colorbar_visible','inherit'));if(!isempty(cb_choice)&&!strcmpi(cb_choice,'inherit')),cs.colorbar_visible=parse_bool_local(cb_choice,cs.colorbar_visible);endif
        q=strtrim(val(headers,grow,'colorbar_label',''));if(!isempty(q)),cs.colorbar_label=q;endif
        q=numval(headers,grow,'color_min');if(isfinite(q)),cs.color_min=q;endif;q=numval(headers,grow,'color_max');if(isfinite(q)),cs.color_max=q;endif
      endif
      % A provider may have enabled its own data colorbar before the final
      % framework pass. An inherited visibility setting must preserve it.
      if(isempty(cb_choice)||strcmpi(cb_choice,'inherit'))
        fig0=ancestor(ax0,'figure');
        if(!isempty(findall(fig0,'type','axes','tag','colorbar'))),cs.colorbar_visible=true;endif
      endif
      gxtxt_plot_apply_color_settings(ax0,cs,cs.colorbar_label);
    endif
  catch err
    warning('GXTXT:ColorOverride','color presentation override was not applied: %s',err.message);
  end_try_catch

  % Colorbars and layout may alter the axes box. Apply the public aspect policy
  % last, without changing the view or projection selected above.
  if(gxtxt_plot_axis_is_3d(axs(1)))
    mode='auto';ratio='';
    if(isfield(p,'aspect_mode')),mode=p.aspect_mode;endif
    if(isfield(p,'aspect_ratio')),ratio=p.aspect_ratio;endif
    if(useRuntime)
      q=lower(strtrim(getv('aspect_mode','inherit')));
      if(!isempty(q)&&!strcmp(q,'inherit')),mode=q;endif
      q=strtrim(getv('aspect_ratio',''));
      if(!isempty(q)),ratio=q;endif
    else
      q=lower(strtrim(val(headers,grow,'aspect_mode','inherit')));
      if(!isempty(q)&&!strcmp(q,'inherit')),mode=q;endif
      q=strtrim(val(headers,grow,'aspect_ratio',''));
      if(!isempty(q)),ratio=q;endif
    endif
    gxtxt_plot_apply_aspect3d(axs(1),mode,ratio);
  else
    mode='auto';
    if(useRuntime)
      q=lower(strtrim(getv('xy_aspect_mode','inherit')));
    else
      q=lower(strtrim(val(headers,grow,'xy_aspect_mode','inherit')));
    endif
    if(!isempty(q)&&!strcmp(q,'inherit')),mode=q;endif
    for k=1:n,gxtxt_plot_apply_aspect2d(axs(k),mode);endfor
  endif

  if(isfield(p,'stacked_bottom_xticks_only')&&p.stacked_bottom_xticks_only&&n>1),for k=1:n-1,try set(axs(k),'xticklabel',[]);catch;end_try_catch;endfor;endif
endfunction

function tf=cfg_has(d,key),k=keyfield(key);tf=isstruct(d)&&isfield(d,k);endfunction
function v=cfg_get(d,key,def),k=keyfield(key);if(isstruct(d)&&isfield(d,k)),v=d.(k);else v=def;endif;endfunction
function k=keyfield(key),k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function x=cfg_num(d,key),x=str2double(cfg_get(d,key,''));if(!isfinite(x)),x=NaN;endif;endfunction
function idx=runtime_panel_index(d,graphKey,panelName),idx=0;if(isempty(panelName)),return;endif;n=str2double(cfg_get(d,['axis.' graphKey '.panel_count'],'0'));if(!isfinite(n)),return;endif;for j=1:round(n),if(strcmp(cfg_get(d,sprintf('axis.%s.panel%d_name',graphKey,j),''),panelName)),idx=j;return;endif;endfor;endfunction
function [headers,rows]=read_tsv(fn),headers={};rows={};fid=fopen(fn,'r');if(fid<0),return;endif;c=onCleanup(@()fclose(fid));h=fgetl(fid);if(!ischar(h)),return;endif;headers=regexp(h,'\t','split');for k=1:numel(headers),headers{k}=lower(strtrim(headers{k}));endfor;while(true),l=fgetl(fid);if(!ischar(l)),break;endif;if(isempty(strtrim(l))),continue;endif;rows{end+1}=regexp(l,'\t','split');endwhile;endfunction
function row=find_row(headers,rows,key,panel),row={};if(isempty(panel)),return;endif;for i=1:numel(rows),r=rows{i};if(strcmp(val(headers,r,'key',''),key)&&strcmp(val(headers,r,'panel',''),panel)),row=r;return;endif;endfor;endfunction
function v=val(headers,row,name,def),v=def;idx=find(strcmp(headers,name),1);if(isempty(idx)||idx>numel(row)),return;endif;q=strtrim(row{idx});if(!isempty(q)),v=q;endif;endfunction
function x=numval(headers,row,name),q=val(headers,row,name,'');x=str2double(q);if(!isfinite(x)),x=NaN;endif;endfunction
function fmt=cleanfmt(fmt),fmt=strtrim(fmt);if(isempty(fmt)||strcmpi(fmt,'inherit')||strcmpi(fmt,'auto')),fmt='';endif;endfunction
function apply_axis_range(ax,which,vmin,vmax,step,fmt)
  try
    switch which,case 'x',lim=get(ax,'xlim');case 'y',lim=get(ax,'ylim');case 'z',lim=get(ax,'zlim');otherwise,error('axis');endswitch
    if(isfinite(vmin)),lim(1)=vmin;endif;if(isfinite(vmax)),lim(2)=vmax;endif
    if(lim(2)>lim(1)&&(isfinite(vmin)||isfinite(vmax))),switch which,case 'x',set(ax,'xlim',lim);case 'y',set(ax,'ylim',lim);case 'z',set(ax,'zlim',lim);endswitch;endif
    if(isfinite(step)&&step>0&&lim(2)>lim(1)),first=ceil((lim(1)-step*1e-10)/step)*step;last=floor((lim(2)+step*1e-10)/step)*step;ticks=first:step:last;if(!isempty(ticks)),switch which,case 'x',set(ax,'xtick',ticks);case 'y',set(ax,'ytick',ticks);case 'z',set(ax,'ztick',ticks);endswitch;endif;endif
    if(!isempty(fmt)),apply_tick_format(ax,which,fmt);endif
  catch err,warning('GXTXT:AxisOverride','%s-axis override was not applied: %s',which,err.message);end_try_catch
endfunction
function apply_axis_scale(ax,which,mode)
  if(!any(strcmp(mode,{'linear','log'}))),return;endif
  if(strcmp(mode,'log'))
    lim=get(ax,[which 'lim']);
    if(lim(2)<=0),error('GXTXT:LogAxis','%s log scale requires positive data or limits',which);endif
  endif
  set(ax,[which 'scale'],mode);
endfunction
function apply_tick_format(ax,which,fmt),try switch which,case 'x',ticks=get(ax,'xtick');case 'y',ticks=get(ax,'ytick');case 'z',ticks=get(ax,'ztick');endswitch;labs=cell(size(ticks));for j=1:numel(ticks),labs{j}=sprintf(fmt,ticks(j));endfor;switch which,case 'x',set(ax,'xticklabel',labs);case 'y',set(ax,'yticklabel',labs);case 'z',set(ax,'zticklabel',labs);endswitch;gxtxt_plot_normalize_zero_ticks(ancestor(ax,'figure'));catch err,warning('GXTXT:TickFormat','Invalid %s-axis tick format (%s): %s',which,fmt,err.message);end_try_catch;endfunction
function apply_grid(ax,xmode,ymode),try if(strcmp(xmode,'on')),set(ax,'xgrid','on');elseif(strcmp(xmode,'off')),set(ax,'xgrid','off');endif;if(strcmp(ymode,'on')),set(ax,'ygrid','on');elseif(strcmp(ymode,'off')),set(ax,'ygrid','off');endif;catch;end_try_catch;endfunction
function tf=has_panel_overlays(fig)
  % True only for figures that declare stacked per-panel right-Y overlays.
  tf=false;
  try axs=findall(fig,'type','axes');catch;return;end_try_catch
  for k=1:numel(axs)
    tag='';try tag=lower(strtrim(get(axs(k),'tag')));catch;end_try_catch
    if(!isempty(regexp(tag,'^gxtxt_panel_[0-9]+_overlay_yaxis$','once'))),tf=true;return;endif
  endfor
endfunction
function ax2=overlay_for_axis(fig,ax)
  % Same pairing as gxtxt_plot_sync_overlay_axes(): panel <n> owns
  % gxtxt_panel_<n>_overlay_yaxis, and a stacked panel 1 may carry the
  % historical gxtxt_primary_axis tag while its overlay keeps the panel form.
  ax2=[];tag='';
  try tag=lower(strtrim(get(ax,'tag')));catch;end_try_catch
  tok=regexp(tag,'^gxtxt_panel_([0-9]+)$','tokens','once');
  if(!isempty(tok))
    want={sprintf('gxtxt_panel_%s_overlay_yaxis',tok{1})};
  elseif(strcmp(tag,'gxtxt_primary_axis'))
    want={'gxtxt_overlay_yaxis','gxtxt_panel_1_overlay_yaxis'};
  else
    want={'gxtxt_overlay_yaxis'};
  endif
  for i=1:numel(want)
    ov=[];try ov=findall(fig,'type','axes','tag',want{i});catch;end_try_catch
    if(!isempty(ov)),ax2=ov(1);return;endif
  endfor
endfunction
function apply_y_grid_source(left,right,source)
  source=lower(strtrim(source));if(isempty(source)||strcmp(source,'inherit')),return;endif
  try
    switch source
      case 'left',set(left,'ygrid','on');if(!isempty(right)),set(right,'ygrid','off');endif
      case 'right',if(isempty(right)),set(left,'ygrid','on');else set(left,'ygrid','off');set(right,'ygrid','on');endif
      case 'none',set(left,'ygrid','off');if(!isempty(right)),set(right,'ygrid','off');endif
    endswitch
  catch
  end_try_catch
endfunction
function apply_grid_color(ax,spec),if(isempty(strtrim(spec))),return;endif;try c=gxtxt_plot_color(spec,[]);if(!isempty(c)),set(ax,'gridcolor',c);endif;catch;end_try_catch;endfunction
function set_ylabel_x(ax,x),try gxtxt_plot_align_ylabel(ax,x);catch;end_try_catch;endfunction
function tf=axis_has_color_metadata(ax),tf=false;try q=getappdata(ax,'gxtxt_c_source_variable');tf=!isempty(q);catch;end_try_catch;endfunction
function b=parse_bool_local(v,d),q=lower(strtrim(v));if(any(strcmp(q,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(q,{'0','false','no','off'}))),b=false;else b=d;endif;endfunction
