% SPDX-License-Identifier: GPL-3.0-or-later
% Plot Region Selection API v1 geometry sidecar writer.
function path = gxtxt_plot_write_metadata(fig,target,raster)
  path='';if(nargin<2||isempty(fig)||isempty(target)),return;endif
  [d,n,~]=fileparts(target);if(isempty(d)),d=pwd();endif
  md=fullfile(d,'.gxtxt_plotmeta');if(exist(md,'dir')!=7),mkdir(md);endif
  path=fullfile(md,[n '.ini']);
  axs=[];try axs=findall(fig,'type','axes');catch;end_try_catch
  data=[];overlay=[];
  for k=1:numel(axs)
    tag='';try tag=lower(strtrim(get(axs(k),'tag')));catch;end_try_catch
    if(!isempty(strfind(tag,'legend'))||!isempty(strfind(tag,'colorbar'))||strcmp(tag,'scribeoverlay')),continue;endif
    if(strcmp(tag,'gxtxt_overlay_yaxis')||!isempty(regexp(tag,'^gxtxt_panel_[0-9]+_overlay_yaxis$','once'))),overlay(end+1)=axs(k);continue;endif
    if(is_helper_axes(axs(k))),continue;endif
    data(end+1)=axs(k);
  endfor
  % Topology and exported-raster calibration are independent facts. Region
  % Selection API v1 needs both, but diagnostics must not describe a valid 2D
  % plot as multi-panel/3D merely because its raster frame was not calibrated.
  primary_axis_is_3d=false;
  if(numel(data)==1),primary_axis_is_3d=gxtxt_plot_axis_is_3d(data(1));endif
  topology_supported=(numel(data)==1 && !primary_axis_is_3d);
  rect=[];image_size=[];calibration_valid=false;
  if(topology_supported && nargin>=3 && !isempty(raster))
    [rect,image_size]=raster_data_rect(raster);
    calibration_valid=!isempty(rect);
  endif
  selection_supported=(topology_supported && calibration_valid);
  fid=fopen(path,'w');if(fid<0),path='';return;endif;c=onCleanup(@() fclose(fid));
  fprintf(fid,'[plot_metadata]\napi_version=1\n');
  bg=get(fig,'color');
  if(ischar(bg)&&strcmpi(strtrim(bg),'none'))
    fprintf(fid,'effective_background=transparent\n');
  elseif(isnumeric(bg)&&numel(bg)==3)
    rgb=round(255*min(1,max(0,bg(:)')));
    fprintf(fid,'effective_background=#%02X%02X%02X\n',rgb(1),rgb(2),rgb(3));
  endif
  fprintf(fid,'selection_supported=%d\n',selection_supported);
  fprintf(fid,'selection_topology_supported=%d\n',topology_supported);
  fprintf(fid,'selection_calibration_valid=%d\n',calibration_valid);
  fprintf(fid,'primary_axis_is_3d=%d\n',primary_axis_is_3d);
  fprintf(fid,'primary_axes_count=%d\noverlay_axes_count=%d\n',numel(data),numel(overlay));
  if(!isempty(image_size)),fprintf(fid,'image_width=%d\nimage_height=%d\n',image_size(1),image_size(2));endif
  for k=1:numel(data),write_axis(fid,sprintf('axis.%d',k),data(k),k==1);if(k==1&&!isempty(rect)),fprintf(fid,'pixel_rect=%d;%d;%d;%d\n',rect);endif;endfor
  for k=1:numel(overlay),write_axis(fid,sprintf('overlay_axis.%d',k),overlay(k),false);endfor
endfunction
function write_axis(fid,sec,ax,isprimary)
  old='';try old=get(ax,'units');set(ax,'units','normalized');pos=get(ax,'position');catch;pos=[0 0 1 1];end_try_catch
  if(!isempty(old)),try set(ax,'units',old);catch;end_try_catch;endif
  xl=get_safe(ax,'xlim',[0 1]);yl=get_safe(ax,'ylim',[0 1]);zl=get_safe(ax,'zlim',[0 1]);
  fprintf(fid,'\n[%s]\n',sec);fprintf(fid,'primary=%d\n',isprimary);fprintf(fid,'position=%.17g;%.17g;%.17g;%.17g\n',pos);
  fprintf(fid,'xlim=%.17g;%.17g\nylim=%.17g;%.17g\nzlim=%.17g;%.17g\n',xl,yl,zl);
  fprintf(fid,'xscale=%s\nyscale=%s\nzscale=%s\n',get_str(ax,'xscale','linear'),get_str(ax,'yscale','linear'),get_str(ax,'zscale','linear'));
  fprintf(fid,'xdir=%s\nydir=%s\nzdir=%s\n',get_str(ax,'xdir','normal'),get_str(ax,'ydir','normal'),get_str(ax,'zdir','normal'));
  fprintf(fid,'tag=%s\n',get_str(ax,'tag',''));
  write_mapping(fid,ax,'x');
  write_mapping(fid,ax,'y');
  write_mapping(fid,ax,'z');
  write_mapping(fid,ax,'c');
  try v=get(ax,'view');if(numel(v)>=2),fprintf(fid,'view_azimuth=%.17g\nview_elevation=%.17g\n',v(1),v(2));endif;catch;end_try_catch
  try pr=get(ax,'projection');if(ischar(pr)),fprintf(fid,'projection=%s\n',pr);endif;catch;end_try_catch
  try ar=get(ax,'dataaspectratio');if(numel(ar)==3),fprintf(fid,'data_aspect_ratio=%.17g;%.17g;%.17g\n',ar);endif;catch;end_try_catch
  try ar=get(ax,'plotboxaspectratio');if(numel(ar)==3),fprintf(fid,'plot_box_aspect_ratio=%.17g;%.17g;%.17g\n',ar);endif;catch;end_try_catch
  fprintf(fid,'aspect_mode=%s\n',get_app_str(ax,'gxtxt_plot_aspect_mode','auto'));
  if(!gxtxt_plot_axis_is_3d(ax))
    fprintf(fid,'xy_aspect_mode=%s\n',get_app_str(ax,'gxtxt_plot_xy_aspect_mode','auto'));
  endif
  try cl=caxis(ax);if(numel(cl)==2),fprintf(fid,'clim=%.17g;%.17g\n',cl(1),cl(2));endif;catch;end_try_catch
endfunction
function write_mapping(fid,ax,which)
  fprintf(fid,'%s_source_variable=%s\n',which,get_app_str(ax,['gxtxt_' which '_source_variable'],''));
  fprintf(fid,'%s_source_unit=%s\n',which,get_app_str(ax,['gxtxt_' which '_source_unit'],''));
  fprintf(fid,'%s_display_unit=%s\n',which,get_app_str(ax,['gxtxt_' which '_display_unit'],''));
  fprintf(fid,'%s_display_to_source_scale=%.17g\n',which,get_app_num(ax,['gxtxt_' which '_display_to_source_scale'],1));
  fprintf(fid,'%s_display_to_source_offset=%.17g\n',which,get_app_num(ax,['gxtxt_' which '_display_to_source_offset'],0));
  fprintf(fid,'%s_transform=%s\n',which,get_app_str(ax,['gxtxt_' which '_transform'],'affine'));
  fprintf(fid,'%s_coordinate_view_status=%s\n',which,get_app_str(ax,['gxtxt_' which '_coordinate_view_status'],'identity'));
  fprintf(fid,'%s_coordinate_view_factor=%.17g\n',which,get_app_num(ax,['gxtxt_' which '_coordinate_view_factor'],1));
  fprintf(fid,'%s_coordinate_view_pivot=%.17g\n',which,get_app_num(ax,['gxtxt_' which '_coordinate_view_pivot'],0));
  if(any(strcmp(which,{'y','z'})))
    for f={'scale','quantity_kind','amplitude_basis','reference_value','reference_unit','zero_policy'}
      name=f{1};fprintf(fid,'%s_level_%s=%s\n',which,name,get_app_str(ax,['gxtxt_' which '_level_' name],''));
    endfor
  endif
endfunction
function s=get_app_str(ax,k,d),try s=getappdata(ax,k);catch;s=d;end_try_catch;if(isempty(s)||!ischar(s)),s=d;endif;endfunction
function v=get_app_num(ax,k,d),try v=getappdata(ax,k);catch;v=d;end_try_catch;if(!isnumeric(v)||!isscalar(v)||!isfinite(v)),v=d;endif;endfunction
function v=get_safe(ax,k,d),try v=get(ax,k);catch;v=d;end_try_catch;if(numel(v)!=2),v=d;endif;endfunction
function s=get_str(ax,k,d),try s=get(ax,k);catch;s=d;end_try_catch;if(!ischar(s)),s=d;endif;endfunction
function tf=is_helper_axes(ax)
  tf=false;
  try
    tag=strtrim(get(ax,'tag'));xt=get(ax,'xtick');yt=get(ax,'ytick');xl=get(ax,'xlim');yl=get(ax,'ylim');children=get(ax,'children');
    if(isempty(children)&&isempty(xt)&&isempty(yt)&&numel(xl)==2&&numel(yl)==2&&abs(xl(1))<1e-12&&abs(xl(2)-1)<1e-12&&abs(yl(1))<1e-12&&abs(yl(2)-1)<1e-12),tf=true;return;endif
    % Octave's external legend can be an untagged axes with text/line
    % children. Its tiny unit-square box is not a separate data panel.
    old=get(ax,'units');set(ax,'units','normalized');pos=get(ax,'position');set(ax,'units',old);
    if(isempty(tag)&&numel(pos)==4&&pos(3)<0.15&&pos(4)<0.15&& ...
       numel(xl)==2&&numel(yl)==2&&all(abs(xl-[0 1])<1e-12)&&all(abs(yl-[0 1])<1e-12)&& ...
       isempty(get_app_str(ax,'gxtxt_x_source_variable',''))&&isempty(get_app_str(ax,'gxtxt_y_source_variable','')))
      tf=true;
    endif
  catch
  end_try_catch
endfunction

function [rect,sz]=raster_data_rect(path)
  % Infer the actual solid data frame from the exported PNG. GNUplot can
  % change that frame without updating the in-memory axes.Position property.
  %
  % A valid frame may lose one pair of raster borders when an external legend
  % or a synchronized dual-Y overlay is exported. Accept a complete matching
  % pair of vertical or horizontal frame lines; when both are available,
  % combine their outer bounds. This remains based on the real PNG and never
  % falls back to another graph or variant's metadata.
  rect=[];sz=[];
  try [rgb,map,alpha]=imread(path);catch;return;end_try_catch
  if(ndims(rgb)==2),rgb=repmat(rgb,[1 1 3]);endif
  if(size(rgb,3)<3),return;endif
  h=size(rgb,1);w=size(rgb,2);sz=[w h];
  if(w<100||h<100),return;endif
  dark=all(double(rgb(:,:,1:3))<120,3);
  % Invisible RGB samples are not raster frame lines. pngcairo retains black
  % RGB under alpha-zero pixels; treating them as visible creates a false
  % whole-image frame and breaks graph point/area selection.
  if(!isempty(alpha))
    dark&=double(alpha)>0;
  endif
  horiz=zeros(0,4);vert=zeros(0,4);
  for y=1:h
    line=dark(y,:);
    if(!isempty(alpha)),line=raster_join_frame_gaps(line,max(2,round(0.02*min(w,h))),0.2*w);endif
    edges=diff([false line false]);
    starts=find(edges==1);ends=find(edges==-1)-1;
    if(isempty(starts)),continue;endif
    [len,k]=max(ends-starts+1);
    if(len>=0.4*w),horiz(end+1,:)=[y starts(k) ends(k) len];endif
  endfor
  for x=1:w
    line=dark(:,x)';
    if(!isempty(alpha)),line=raster_join_frame_gaps(line,max(2,round(0.02*min(w,h))),0.2*h);endif
    edges=diff([false line false]);
    starts=find(edges==1);ends=find(edges==-1)-1;
    if(isempty(starts)),continue;endif
    [len,k]=max(ends-starts+1);
    if(len>=0.4*h),vert(end+1,:)=[x starts(k) ends(k) len];endif
  endfor

  hr=frame_from_horizontal_runs(horiz,w,h);
  vr=frame_from_vertical_runs(vert,w,h);
  % Outside legends can interrupt the top frame and a borderless style can
  % omit the right frame. A measured left/bottom corner still fixes all four
  % data bounds without trusting GNUplot's stale in-memory axes.Position.
  cr=frame_from_corner_runs(horiz,vert,w,h);
  if(isempty(hr)&&isempty(vr)&&isempty(cr)),return;endif
  if(isempty(hr))
    if(isempty(vr)),candidate=cr;else candidate=vr;endif
  elseif(isempty(vr))
    candidate=hr;
  elseif(rectangles_agree(hr,vr,4))
    candidate=[min(hr(1),vr(1)) min(hr(2),vr(2)) max(hr(3),vr(3)) max(hr(4),vr(4))];
  elseif(rect_area(hr)>=rect_area(vr))
    candidate=hr;
  else
    candidate=vr;
  endif
  if(!isempty(cr)&&rect_area(cr)>rect_area(candidate)),candidate=cr;endif
  if(candidate(3)-candidate(1)<0.4*w||candidate(4)-candidate(2)<0.4*h),return;endif
  rect=round(candidate)-1;
endfunction

function line=raster_join_frame_gaps(line,limit,min_run)
  % Colored foreground can interrupt a pngcairo frame by a marker-width gap.
  % Recover only short interior gaps; the existing matching-frame checks still
  % require measured bounds on opposite sides of a large data rectangle.
  edges=diff([false line false]);starts=find(edges==1);ends=find(edges==-1)-1;
  % Text strokes are not partial frame lines. Require an already measured
  % substantial solid run before bridging foreground interruptions.
  if(isempty(starts)||max(ends-starts+1)<min_run),return;endif
  for k=1:numel(starts)-1
    if(starts(k+1)-ends(k)-1<=limit&&ends(k)-starts(k)+1>=min_run/2&&ends(k+1)-starts(k+1)+1>=min_run/2)
      line(ends(k)+1:starts(k+1)-1)=true;
    endif
  endfor
endfunction

function r=frame_from_corner_runs(horiz,vert,w,h)
  r=[];best=-Inf;
  for i=1:rows(horiz)
    yy=horiz(i,1);xa=horiz(i,2);xb=horiz(i,3);
    for j=1:rows(vert)
      xx=vert(j,1);ya=vert(j,2);yb=vert(j,3);
      if(min(abs(xx-xa),abs(xx-xb))>4 || min(abs(yy-ya),abs(yy-yb))>4),continue;endif
      candidate=[min(xa,xx) min(ya,yy) max(xb,xx) max(yb,yy)];
      if(candidate(3)-candidate(1)<0.4*w||candidate(4)-candidate(2)<0.4*h),continue;endif
      score=rect_area(candidate);
      if(score>best),best=score;r=candidate;endif
    endfor
  endfor
endfunction

function r=frame_from_horizontal_runs(lines,w,h)
  r=[];best=-Inf;
  for i=1:rows(lines)
    for j=i+1:rows(lines)
      if(abs(lines(i,2)-lines(j,2))>3||abs(lines(i,3)-lines(j,3))>3),continue;endif
      y0=min(lines(i,1),lines(j,1));y1=max(lines(i,1),lines(j,1));
      x0=round((lines(i,2)+lines(j,2))/2);x1=round((lines(i,3)+lines(j,3))/2);
      if(x1-x0<0.4*w||y1-y0<0.4*h),continue;endif
      score=(x1-x0)*(y1-y0);
      if(score>best),best=score;r=[x0 y0 x1 y1];endif
    endfor
  endfor
endfunction

function r=frame_from_vertical_runs(lines,w,h)
  r=[];best=-Inf;
  for i=1:rows(lines)
    for j=i+1:rows(lines)
      if(abs(lines(i,2)-lines(j,2))>3||abs(lines(i,3)-lines(j,3))>3),continue;endif
      x0=min(lines(i,1),lines(j,1));x1=max(lines(i,1),lines(j,1));
      y0=round((lines(i,2)+lines(j,2))/2);y1=round((lines(i,3)+lines(j,3))/2);
      if(x1-x0<0.4*w||y1-y0<0.4*h),continue;endif
      score=(x1-x0)*(y1-y0);
      if(score>best),best=score;r=[x0 y0 x1 y1];endif
    endfor
  endfor
endfunction

function tf=rectangles_agree(a,b,tol)
  tf=all(abs(a-b)<=tol);
endfunction

function a=rect_area(r)
  a=max(0,r(3)-r(1))*max(0,r(4)-r(2));
endfunction
