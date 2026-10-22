function pd_render_3d(outdir,cfg,P,graph,file_name,preview_dir)
  if(nargin<6),preview_dir='';endif
  lifetime=[];if(any(cellfun(@(key) isfield(P.(key),'coordinate_context'),{'x_meta','y_meta','z_meta','color_meta'}))),lifetime=gxtxt_presentation_scope_v1();endif
  display_groups={};
% Render framework-native XYZ/C data using Plot 3D API v2.
% SPDX-License-Identifier: GPL-3.0-or-later
  pcfg=gxtxt_plot_config();groups=P.groups;ng=numel(groups);ptype=P.plot_type;
  xcells=cell(1,ng);ycells=cell(1,ng);zcells=cell(1,ng);for g=1:ng,xcells{g}=groups(g).x;ycells{g}=groups(g).y;zcells{g}=groups(g).z;endfor
  xmode=axis_mode(cfg,graph,'x');ymode=axis_mode(cfg,graph,'y');zmode=axis_mode(cfg,graph,'z');
  [xdu,~]=pd_common_display_unit(xcells,repmat({P.x_meta},1,ng),xmode,'X axis');
  [ydu,~]=pd_common_display_unit(ycells,repmat({P.y_meta},1,ng),ymode,'Y axis');
  [zdu,~]=pd_common_display_unit(zcells,repmat({P.z_meta},1,ng),zmode,'Z axis');

  zlevel=gxtxt_level_scale_config(cfg,graph,'z');zlevel_label='';
  color_enabled=false;color_name='';color_meta=struct('unit','');ccells={};
  if(!isempty(P.color_name))
    color_enabled=true;color_name=P.color_name;color_meta=P.color_meta;ccells=cell(1,ng);for g=1:ng,ccells{g}=groups(g).c;endfor
  elseif(any(strcmp(ptype,{'surface','mesh','trisurf','contour3','heatmap'})))
    color_enabled=true;color_name=P.z_name;color_meta=P.z_meta;ccells=zcells;
  endif
  cdu='';if(color_enabled)
    cmode=axis_mode(cfg,graph,'c');[cdu,~]=pd_common_display_unit(ccells,repmat({color_meta},1,ng),cmode,'Color');
    if(strcmp(ptype,'contour3')&&!strcmp(normunit(cdu),normunit(zdu)))
      error('plot.dataset: contour3 uses Z itself as color; Z display unit (%s) and Color display unit (%s) must match',zdu,cdu);
    endif
  endif

  fig=gxtxt_plot_new_figure(pcfg);ax=axes('parent',fig);set(ax,'tag','gxtxt_primary_axis');hold(ax,'on');
  lw=parse_line_width(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'inherit'),pcfg.line_width);ms=parse_positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'5'),5);
  order_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.point_order'],'dataset_order')));if(!any(strcmp(order_mode,{'dataset_order','sort_x'}))),order_mode='dataset_order';endif
  legend_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.legend_content'],'auto')));has_family=!isempty(P.family_name);
  if(strcmp(legend_mode,'auto'))
    if(has_family),legend_mode='family';elseif(any(strcmp(ptype,{'surface','mesh','contour3','trisurf','heatmap'}))),legend_mode='none';else legend_mode='series';endif
  endif
  % A GUI legend edit outranks both automatic colorbar presentation and a
  % module's initial `legend_content=none` choice for a single surface.
  enabled=strtrim(gxtxt_ini_get(cfg,['legend.' graph '.enabled'],'0'));
  if(strcmp(enabled,'1')&&strcmp(legend_mode,'none')),legend_mode='series';endif
  if(!any(strcmp(legend_mode,{'none','series','family'}))),legend_mode='series';endif
  [family_labels,family_unit]=family_catalog_labels(cfg,P);
  handles=[];labels={};xf=1;yf=1;zf=1;cf=1;
  for g=1:ng
    [xd,~,xfg]=pd_convert_display(groups(g).x,P.x_meta,xdu,'X');[yd,~,yfg]=pd_convert_display(groups(g).y,P.y_meta,ydu,'Y');[zd,~,zfg]=pd_convert_display(groups(g).z,P.z_meta,zdu,'Z');
    zlinear=zd;[zd,zlevel_label]=gxtxt_level_scale_apply(zd,zdu,zlevel);
    if(g==1),xf=xfg;yf=yfg;zf=zfg;endif
    cd=[];if(color_enabled)
      if(strcmp(ptype,'contour3')),cd=zlinear;cfgf=zfg;else [cd,~,cfgf]=pd_convert_display(ccells{g},color_meta,cdu,'Color');endif
      if(g==1),cf=cfgf;endif
    endif
    if(any(strcmp(ptype,{'line3','scatter3','trisurf'}))&&strcmp(order_mode,'sort_x'))
      [xd,ord]=sort(xd(:));yd=yd(ord);zd=zd(ord);if(!isempty(cd)),cd=cd(ord);endif
    endif
    h=[];
    switch ptype
      case 'line3'
        h=plot3(ax,xd,yd,zd,'-','linewidth',lw);
      case 'scatter3'
        if(!isempty(P.color_name)),h=scatter3(ax,xd,yd,zd,ms^2,cd,'filled');else h=scatter3(ax,xd,yd,zd,ms^2,'filled');endif
      case 'surface'
        if(color_enabled),h=gxtxt_plot_surface(ax,xd,yd,zd,cd);else h=gxtxt_plot_surface(ax,xd,yd,zd);endif
      case 'heatmap'
        [XX,YY]=meshgrid(xd(:)',yd(:));
        h=surface(ax,XX,YY,zeros(size(XX)),cd,'edgecolor','none');
      case 'mesh'
        if(color_enabled),h=gxtxt_plot_mesh(ax,xd,yd,zd,cd);else h=gxtxt_plot_mesh(ax,xd,yd,zd);endif
      case 'contour3'
        levels=round(parse_positive(gxtxt_ini_get(cfg,['plot.' graph '.contour_levels'],'12'),12));h=gxtxt_plot_contour3(ax,xd,yd,zd,levels);
      case 'trisurf'
        if(color_enabled),[h,~]=gxtxt_plot_trisurf(ax,xd,yd,zd,cd);else [h,~]=gxtxt_plot_trisurf(ax,xd,yd,zd);endif
    endswitch
    if(!isempty(preview_dir))
      D=groups(g);D.x=xd;D.y=yd;D.z=zd;D.c=cd;
      fixed=[0.0 0.447 0.741];
      try fixed=get(h(1),'color');catch;try fixed=get(h(1),'cdata');catch;end_try_catch;end_try_catch
      if(!isnumeric(fixed)||numel(fixed)!=3)
        if(isempty(cd)&&any(strcmp(ptype,{'line3','scatter3'}))),close(fig);error('Native3D preview: original series color is not exposed by this graphics handle');endif
        fixed=[0.0 0.447 0.741];
      endif
      color_mode='interp';
      if(strcmp(ptype,'mesh')&&isprop(h,'edgecolor'))
        color_mode=get(h,'edgecolor');
      elseif(isprop(h,'facecolor'))
        color_mode=get(h,'facecolor');
      endif
      display_groups{end+1}=struct('data',D,'color',fixed,'color_mode',color_mode);
    endif
    if(!strcmp(legend_mode,'none')&&!isempty(h))
      handles(end+1)=h(1);if(has_family),labels{end+1}=family_label(groups(g).key,g,family_labels,P,cfg,graph,family_unit);else labels{end+1}=series_label(P.z_name,zdu);endif %#ok<AGROW>
      if(strcmp(legend_mode,'series')&&g==1&&ng>1),handles=handles(1);labels=labels(1);endif
    endif
  endfor
  gxtxt_plot_set_axis_metadata(ax,'x',P.x_name,P.x_meta.unit,xdu,xf,0);gxtxt_plot_set_axis_metadata(ax,'y',P.y_name,P.y_meta.unit,ydu,yf,0);gxtxt_plot_set_axis_metadata(ax,'z',P.z_name,P.z_meta.unit,zdu,zf,0);gxtxt_level_scale_metadata(ax,zlevel,'z');
  if(color_enabled),gxtxt_plot_set_axis_metadata(ax,'c',color_name,color_meta.unit,cdu,cf,0);endif

  title_txt=presentation_value(cfg,graph,'title',gxtxt_ini_get(cfg,['plot.' graph '.title'],'auto'));xl=presentation_value(cfg,graph,'x_label',gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'));yl=presentation_value(cfg,graph,'y_label',gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'));zl=presentation_value(cfg,graph,'z_label',gxtxt_ini_get(cfg,['plot.' graph '.z_label'],'auto'));
  if(is_auto(title_txt)),title_txt=sprintf('%s vs %s / %s',display_name(P.z_name),display_name(P.x_name),display_name(P.y_name));endif
  if(is_auto(xl)),xl=axis_label(display_name(P.x_name),xdu);endif;if(is_auto(yl)),yl=axis_label(display_name(P.y_name),ydu);endif;if(is_auto(zl)),zl=axis_label(display_name(P.z_name),zdu);endif;xl=pd_display_axis_label(xl,P.x_meta.unit,xdu);yl=pd_display_axis_label(yl,P.y_meta.unit,ydu);zl=pd_display_axis_label(zl,P.z_meta.unit,zdu);if(!isempty(zlevel_label)),zl=[zl ' (' zlevel_label ')'];endif
  xlabel(ax,xl,'interpreter','none');ylabel(ax,yl,'interpreter','none');zlabel(ax,zl,'interpreter','none');title(ax,title_txt,'interpreter','none');
  gxtxt_plot_apply_axes3d(ax,pcfg);
  if(any(strcmp(ptype,{'surface','mesh','contour3','trisurf'})))
    zrange=get(ax,'zlim');if(all(isfinite(zrange))&&zrange(2)>zrange(1))
      pad=0.07*(zrange(2)-zrange(1));zlim(ax,[zrange(1)-pad zrange(2)+pad]);
    endif
  endif
  gxtxt_plot_axis_overrides(ax,graph,{},pcfg,cfg);
  if(strcmp(ptype,'heatmap'))
    view(ax,2);axis(ax,'tight');zlabel(ax,'');
    % Grid lines obscure dense cells; explicit per-graph grid overrides still win.
    gx=strtrim(gxtxt_ini_get(cfg,['axis.' graph '.xgrid'],''));
    gy=strtrim(gxtxt_ini_get(cfg,['axis.' graph '.ygrid'],''));
    if(isempty(gx)&&isempty(gy)),grid(ax,'off');endif
  endif
  pd_coordinate_axis_metadata(ax,'x',P.x_meta,xdu);pd_coordinate_axis_metadata(ax,'y',P.y_meta,ydu);
  pd_coordinate_view(ax,'x',{P.x_meta},xdu,cfg,graph,'x');pd_coordinate_view(ax,'y',{P.y_meta},ydu,cfg,graph,'y');
  if(!strcmp(ptype,'heatmap'))
    pd_coordinate_axis_metadata(ax,'z',P.z_meta,zdu);
    pd_coordinate_view(ax,'z',{P.z_meta},zdu,cfg,graph,'z',struct(),'',zlevel);
  endif
  if(color_enabled)
    pd_coordinate_axis_metadata(ax,'c',color_meta,cdu);
    cs=gxtxt_plot_color_settings(cfg,graph,pcfg);
    cb_choice=strtrim(gxtxt_ini_get(cfg,['axis.' graph '.colorbar_visible'],'inherit'));
    if(any(strcmp(ptype,{'scatter3','surface','mesh','contour3','trisurf','heatmap'}))&&(isempty(cb_choice)||strcmpi(cb_choice,'inherit')))
      cs.colorbar_visible=true;
    endif
    auto_cb=axis_label(display_name(color_name),cdu);if(!isempty(strtrim(cs.colorbar_label))),auto_cb=pd_display_axis_label(cs.colorbar_label,color_meta.unit,cdu);endif;gxtxt_plot_apply_color_settings(ax,cs,auto_cb);
    if(cs.colorbar_visible&&is_auto(presentation_value(cfg,graph,'z_label',gxtxt_ini_get(cfg,['plot.' graph '.z_label'],'auto'))))
      zlabel(ax,'');
    endif
  endif
  % Octave's default 3D plot box puts Z labels against the page edge once a
  % colorbar is present. Reserve a stable left margin for default 3D views.
  if(!strcmp(ptype,'heatmap'))
    pos=get(ax,'position');
    shift=max(0,0.18-pos(1));
    if(shift>0),set(ax,'position',[pos(1)+shift pos(2) max(0.48,pos(3)-shift) pos(4)]);endif
    % Gnuplot positions a native 3D Z label over the Z tick labels. Use a
    % figure-space caption, sourced from the same editable axis setting.
    if(!isempty(strtrim(zl)))
      zlabel(ax,'');
      annotation(fig,'textbox',[0.03 0.88 0.36 0.045], ...
        'string',['Z: ' zl],'linestyle','none', ...
        'horizontalalignment','left','verticalalignment','middle', ...
        'interpreter','none','fontsize',6);
    endif
  endif
  apply_3d_layout_override(ax,cfg,graph);
  legend_handle=[];
  if(!isempty(labels)&&!strcmp(legend_mode,'none')),legend_handle=gxtxt_plot_legend(handles,labels,pcfg,graph,cfg);endif
  if(!isempty(preview_dir))
    unwind_protect
      policy=preview_presentation_policy(pcfg,cfg,graph);policy.legend_handle=legend_handle;
      pd_preview_export(fig,ax,P,display_groups,order_mode,cfg,graph,preview_dir,labels,lw,ms,{xl,yl,zl},policy);
    unwind_protect_cleanup
      close(fig);
    end_unwind_protect
    return;
  endif
  target=fullfile(outdir,file_name);gxtxt_print_png_atomic(fig,target,pcfg.dpi);
  fmt=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.extra_format'],'none')));
  if(any(strcmp(fmt,{'svg','pdf'})))
    [parent,base,~]=fileparts(target);extra=fullfile(parent,[base '.' fmt]);
    if(strcmp(fmt,'svg')),print(fig,extra,'-dsvg');else print(fig,extra,'-dpdf','-color');endif
  endif
  close(fig);
  fprintf('[plot.dataset] rendered 3D graph=%s type=%s file=%s groups=%d xunit=%s yunit=%s zunit=%s cunit=%s\n',graph,ptype,target,ng,xdu,ydu,zdu,cdu);
endfunction

function apply_3d_layout_override(ax,cfg,graph)
  prefix=['axis.' graph '.'];
  if(!strcmp(strtrim(gxtxt_ini_get(cfg,[prefix 'layout_auto'],'1')),'0')),return;endif
  keys={'layout_margin_left','layout_margin_bottom','layout_margin_right','layout_margin_top'};
  defaults=[18 11 9.5 7.5];m=defaults;
  for k=1:4
    value=str2double(gxtxt_ini_get(cfg,[prefix keys{k}],num2str(defaults(k))));
    if(isfinite(value)&&value>=0&&value<=30),m(k)=value;endif
  endfor
  pos=[m(1) m(2) 100-m(1)-m(3) 100-m(2)-m(4)]/100;
  if(pos(3)>0.2&&pos(4)>0.1),set(ax,'units','normalized','position',pos);endif
endfunction

function m=axis_mode(cfg,graph,axis_name),m=gxtxt_plot_axis_unit_mode(cfg,graph,axis_name,'auto');if(isempty(m)||strcmpi(m,'inherit')),m='auto';endif;endfunction
function [labels,du]=family_catalog_labels(cfg,P)
  keys={P.groups.key};labels=keys;du='';if(isempty(P.family_name)),return;endif
  nums=nan(numel(keys),1);numeric=true;for i=1:numel(keys),nums(i)=str2double(keys{i});if(!isfinite(nums(i))),numeric=false;break;endif;endfor
  if(!numeric||isempty(strtrim(P.family_meta.unit))),return;endif
  mode=strtrim(gxtxt_ini_get(cfg,'config.family_display_unit','auto'));[du,~]=pd_common_display_unit({nums},{P.family_meta},mode,'Family');[vals,~,~]=pd_convert_display(nums,P.family_meta,du,'Family');for i=1:numel(keys),labels{i}=sprintf('%g',vals(i));endfor
endfunction
function s=family_label(key,g,labels,P,cfg,graph,unit),v=labels{g};if(!isempty(unit)),v=[v ' ' unit];endif;prefix=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.family_label_prefix'],'auto'));if(is_auto(prefix)),prefix=display_name(P.family_name);endif;if(isempty(prefix)),s=v;else s=[prefix '=' v];endif;endfunction
function s=series_label(name,unit),s=axis_label(display_name(name),unit);endfunction
function s=axis_label(name,unit)
  s=strtrim(name);unit=strtrim(unit);if(isempty(unit)),return;endif
  suffix=[' ' unit];if(numel(s)>numel(suffix)&&strcmpi(s(end-numel(suffix)+1:end),suffix))
    s=strtrim(s(1:end-numel(suffix)));
  endif
  s=[s ' [' unit ']'];
endfunction
function s=display_name(s),s=strrep(s,'_',' ');endfunction
function tf=is_auto(s),tf=isempty(strtrim(s))||strcmpi(strtrim(s),'auto');endfunction
function value=presentation_value(cfg,graph,field,inherited)
  value=strtrim(inherited);override=strtrim(gxtxt_ini_get(cfg,['axis.' graph '.' field],''));
  if(!isempty(override)&&!strcmpi(override,'inherit')),value=override;endif
endfunction
function v=parse_positive(s,d),v=str2double(s);if(!isfinite(v)||v<=0),v=d;endif;endfunction
function v=parse_line_width(s,d),if(isempty(strtrim(s))||strcmpi(strtrim(s),'inherit')),v=d;else v=parse_positive(s,d);endif;endfunction
function u=normunit(u),u=strrep(strrep(strtrim(u),'µ','u'),'μ','u');endfunction

function policy=preview_presentation_policy(pcfg,cfg,graph)
  % This records placement intent only. Actual geometry/style/text comes from
  % the normal renderer's returned objects, never a second legend renderer.
  explicit=any(strcmpi(strtrim(pcfg.legend_mode),{'manual','above','below','left','right','none','off','hidden'}));
  saved=gxtxt_plot_legend_override(graph); % shared TSV authority/enable rules
  if((isfield(saved,'placement')&&!isempty(saved.placement))||(isfield(saved,'mode')&&!isempty(saved.mode))),explicit=true;endif
  enabled=lower(strtrim(gxtxt_ini_get(cfg,['legend.' graph '.enabled'],'')));
  if(any(strcmp(enabled,{'1','true','yes','on'})))
    placement=strtrim(gxtxt_ini_get(cfg,['legend.' graph '.placement'],''));
    if(isempty(placement)),placement=strtrim(gxtxt_ini_get(cfg,['legend.' graph '.mode'],''));endif
    if(!isempty(placement)),explicit=true;endif
  endif
  policy=struct('legend_position_explicit',explicit, ...
    'layout_auto',!strcmp(strtrim(gxtxt_ini_get(cfg,['axis.' graph '.layout_auto'],'1')),'0'));
endfunction
