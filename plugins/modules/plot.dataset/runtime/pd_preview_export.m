function pd_preview_export(fig,ax,P,groups,point_order,cfg,graph,out,labels,lw,ms,axis_labels,prepared)
% Read-only projection of the SAME prepared graph after its normal presentation.
% Never prints/replaces the static graph, publishes data or creates a Document.
  mkdir(out);limits=[];scales={};directions={};units={};
  dar=get(ax,'dataaspectratio');
  for name={'x','y','z'}
    a=name{1};limits=[limits;get(ax,[a 'lim'])];scales{end+1}=get(ax,[a 'scale']);
    directions{end+1}=get(ax,[a 'dir']);
    units{end+1}=struct('source_variable',getappdata(ax,['gxtxt_' a '_source_variable']),'source_unit',getappdata(ax,['gxtxt_' a '_source_unit']),'display_unit',getappdata(ax,['gxtxt_' a '_display_unit']));
  endfor
  if(any(!strcmp(scales,'linear'))||any(!strcmp(directions,'normal')))
    error('Native3D preview: logarithmic/reversed axes need a CORE coordinate mapping API; static graph preserved');
  endif
  if(any(!isfinite(dar))||any(dar<=0)),error('Native3D preview: invalid rendered aspect');endif
  meta=struct('plot_type',P.plot_type,'limits',limits,'scales',{scales},'directions',{directions}, ...
    'axis_ticks',{{get(ax,'xtick'),get(ax,'ytick'),get(ax,'ztick')}},'axis_labels',{axis_labels},'axis_identity',{units},'title',get(get(ax,'title'),'string'),'legend',{labels}, ...
    'aspect',dar,'camera_position',get(ax,'cameraposition')./dar, ...
    'camera_target',get(ax,'cameratarget')./dar,'camera_up',get(ax,'cameraupvector')./dar, ...
    'fov',get(ax,'cameraviewangle'),'projection',get(ax,'projection'), ...
    'background',get(ax,'color'),'clim',get(ax,'clim'),'colormap',colormap(ax), ...
    'view',get(ax,'view'),'line_width',lw,'point_size',ms,'stats',P.stats,'layers',{{}});
  meta.coordinate_policies=struct();meta.calibration_applied=false;
  for role={'x','y','z'}
    m=P.([role{1} '_meta']);
    if(isfield(m,'coordinate_context'))
      c=m.coordinate_context;meta.coordinate_policies.(role{1})=c.variables.(m.variable_id);
    endif
  endfor
  if(!isnumeric(meta.background)),meta.background=get(fig,'color');endif
  if(!isnumeric(meta.background)||numel(meta.background)!=3),error('Native3D preview: transparent backgrounds require a CORE alpha-background API; static graph preserved');endif
  cb=findobj(fig,'tag','colorbar');meta.colorbar_visible=!isempty(cb);meta.colorbar_label='';
  if(!isempty(cb)),meta.colorbar_label=get(get(cb(1),'ylabel'),'string');endif
  if(nargin>=13),meta.prepared_presentation=prepared_presentation(fig,ax,prepared);endif
  levels=str2double(gxtxt_ini_get(cfg,['plot.' graph '.contour_levels'],'12'));
  if(numel(groups)>16),error('Native3D preview: at most 16 prepared series');endif
  total_points=0;
  for i=1:numel(groups)
    G=groups{i}.data;
    % Coordinates, Z-level transforms and C are exactly those used by pd_render_3d.
    [xyz,scalar,verts,lines,polys,primitive]=pd_scene_group(P,G,'dataset_order',levels);
    if(strcmp(P.plot_type,'contour3')),scalar=xyz(:,3);endif
    total_points+=rows(xyz);
    if(total_points>200000||rows(polys)>400000),error('Native3D preview: prepared geometry exceeds bounded display budget; static graph preserved');endif
    rgb=[];
    if(!isempty(scalar))
      span=diff(meta.clim);if(span<=0),error('Native3D preview: invalid color limits');endif
      idx=max(1,min(rows(meta.colormap),1+floor((scalar-meta.clim(1))/span*rows(meta.colormap))));
      rgb=meta.colormap(idx,:);
    endif
    path=sprintf('scene_%04d.vtp',i);
    cell_rgb=[];color_array='display_rgb';
    color_mode=groups{i}.color_mode;
    if(strcmp(primitive,'surface')&&ischar(color_mode)&&strcmp(color_mode,'flat')&&!isempty(rgb))
      % Preserve the original surface quad's constant color on BOTH triangles.
      cell_rgb=rgb(polys(:,1)+1,:);color_array='display_rgb_cell';
    elseif(strcmp(primitive,'surface')&&isnumeric(color_mode)&&numel(color_mode)==3)
      cell_rgb=repmat(color_mode(:)',rows(polys),1);color_array='display_rgb_cell';
    elseif(strcmp(P.plot_type,'mesh')&&ischar(color_mode)&&strcmp(color_mode,'flat')&&!isempty(rgb))
      starts=cellfun(@(edge) edge(1)+1,lines);
      cell_rgb=rgb(starts,:);color_array='display_rgb_cell';
    elseif(strcmp(P.plot_type,'mesh')&&isnumeric(color_mode)&&numel(color_mode)==3)
      cell_rgb=repmat(color_mode(:)',numel(lines),1);color_array='display_rgb_cell';
    endif
    pd_scene_write_vtp(fullfile(out,path),xyz,scalar,verts,lines,polys,rgb,cell_rgb);
    meta.layers{end+1}=struct('path',path,'primitive',primitive,'color',groups{i}.color,'scalar',!isempty(scalar),'color_array',color_array,'color_mode',color_mode);
  endfor
  f=fopen(fullfile(out,'presentation.json'),'w');
  unwind_protect;fputs(f,jsonencode(meta));unwind_protect_cleanup;fclose(f);end_unwind_protect
endfunction

function result=prepared_presentation(fig,ax,prepared)
  % All coordinates/fonts below describe effective normal graphics objects.
  % Reading normalized properties does not modify the objects or their units.
  if(!strcmp(get(fig,'units'),'pixels')||!strcmp(get(fig,'paperunits'),'inches')||!strcmp(get(ax,'units'),'normalized'))
    error('Native3D preview: prepared presentation needs normalized axes and pixel/inch figure units');
  endif
  fp=get(fig,'position');paper=get(fig,'paperposition');dpi=fp(3)/paper(3);
  if(!isfinite(dpi)||dpi<=0),error('Native3D preview: invalid prepared output DPI');endif
  result=struct('version',1,'layout_auto',prepared.layout_auto,'axes_position',get(ax,'position'), ...
    'legend',struct('visible',false,'position_explicit',prepared.legend_position_explicit));
  h=prepared.legend_handle;
  if(isempty(h)||!ishandle(h)||!strcmp(get(h,'visible'),'on')),return;endif
  if(!strcmp(get(h,'units'),'normalized')),error('Native3D preview: legend position is not normalized');endif
  box=get(h,'position');
  if(numel(box)!=4||any(!isfinite(box))||any(box(3:4)<=0)),error('Native3D preview: invalid effective legend box');endif
  entries=struct('text',{},'position',{},'font_px',{},'alignment',{});
  texts=findobj(h,'type','text');
  for i=1:numel(texts)
    t=texts(i);value=get(t,'string');if(isempty(value)),continue;endif
    if(iscell(value)),value=strjoin(value,'\n');endif
    if(!ischar(value)),error('Native3D preview: unsupported legend text');endif
    if(!strcmp(get(t,'fontunits'),'points')),error('Native3D preview: unsupported prepared legend font units');endif
    pos=get(t,'position');u=get(t,'units');
    if(strcmp(u,'data'))
      xl=get(h,'xlim');yl=get(h,'ylim');pos(1)=(pos(1)-xl(1))/diff(xl);pos(2)=(pos(2)-yl(1))/diff(yl);
    elseif(!strcmp(u,'normalized')),error('Native3D preview: unsupported legend text coordinates');endif
    entries(end+1)=struct('text',value,'position',pos(1:2),'font_px',get(t,'fontsize')*dpi/72,'alignment',get(t,'horizontalalignment'));
  endfor
  if(isempty(entries)),return;endif
  % Graphics child order is not display order. Preserve actual rows/columns.
  coordinates=vertcat(entries.position);[~,order]=sortrows([-coordinates(:,2),coordinates(:,1)],[1 2]);entries=entries(order);
  edge=get(h,'color');background=isnumeric(edge)&&numel(edge)==3;
  border=false;border_color=[0.5 0.5 0.5];lines=findobj(h,'type','line');
  for i=1:numel(lines)
    xx=get(lines(i),'xdata');yy=get(lines(i),'ydata');
    if(numel(xx)==2&&numel(yy)==2&&(all(xx<0.03)||all(xx>0.97))&&abs(diff(yy))>0.9)
      border=true;border_color=get(lines(i),'color');break;
    endif
  endfor
  if(!background),edge=[1 1 1];endif
  % A native legend may use its own box rather than the GNUplot frame lines.
  if(isprop(h,'box')&&strcmp(get(h,'box'),'on')),border=true;if(isprop(h,'edgecolor')),border_color=get(h,'edgecolor');endif;endif
  result.legend=struct('visible',true,'position_explicit',prepared.legend_position_explicit, ...
    'box',box,'entries',{entries},'background',background,'background_rgb',edge,'border',border,'border_rgb',border_color);
endfunction
