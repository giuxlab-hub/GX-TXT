% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT common plot configuration from environment.
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
function p = gxtxt_plot_config()
  p.width_px = round(gxtxt_envnum_default('GXTXT_PLOT_WIDTH_PX',1600));
  p.height_px = round(gxtxt_envnum_default('GXTXT_PLOT_HEIGHT_PX',900));
  p.dpi = round(gxtxt_envnum_default('GXTXT_PNG_DPI',200));
  p.font_unit = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_FONT_UNIT','px')));
  if (!any(strcmp(p.font_unit,{'px','pt'}))), p.font_unit='px'; endif
  p.font_size_input = gxtxt_envnum_default('GXTXT_PLOT_FONT_SIZE',12);
  p.axis_label_font_size_input = str2double(strtrim(getenv('GXTXT_PLOT_AXIS_LABEL_FONT_SIZE')));
  p.title_font_size_input = str2double(strtrim(getenv('GXTXT_PLOT_TITLE_FONT_SIZE')));
  p.legend_font_unit = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_FONT_UNIT','inherit')));
  if (isempty(p.legend_font_unit) || strcmp(p.legend_font_unit,'inherit')), p.legend_font_unit=p.font_unit; endif
  if (!any(strcmp(p.legend_font_unit,{'px','pt'}))), p.legend_font_unit=p.font_unit; endif
  p.legend_font_size_input = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_FONT_SIZE',10);
  p.font_size = gxtxt_plot_font_to_points(p.font_size_input,p.font_unit,p.dpi);
  p.axis_label_font_size = gxtxt_plot_font_to_points(p.axis_label_font_size_input,p.font_unit,p.dpi);
  p.title_font_size = gxtxt_plot_font_to_points(p.title_font_size_input,p.font_unit,p.dpi);
  p.legend_font_size = gxtxt_plot_font_to_points(p.legend_font_size_input,p.legend_font_unit,p.dpi);
  p.line_width = gxtxt_envnum_default('GXTXT_PLOT_LINE_WIDTH',1.4);
  p.grid = gxtxt_envnum_default('GXTXT_PLOT_GRID',1) != 0;
  p.grid_mode = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_GRID_MODE','inherit')));
  if (!any(strcmp(p.grid_mode,{'inherit','both','vertical','horizontal','none'}))), p.grid_mode='inherit'; endif
  p.grid_color = strtrim(gxtxt_getenv_default('GXTXT_PLOT_GRID_COLOR',''));
  p.time_unit = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_TIME_UNIT','auto')));
  p.time_unit = strrep(p.time_unit,'µ','u'); p.time_unit = strrep(p.time_unit,'μ','u');
  if (!any(strcmp(p.time_unit,{'auto','source','none','s','ms','us','ns','min','h','day'}))), p.time_unit='auto'; endif
  p.stacked_shared_x = gxtxt_envnum_default('GXTXT_PLOT_STACKED_SHARED_X',1) != 0;
  p.stacked_bottom_xticks_only = gxtxt_envnum_default('GXTXT_PLOT_STACKED_BOTTOM_XTICKS_ONLY',1) != 0;
  p.stacked_grid_mode = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_STACKED_GRID_MODE','inherit')));
  p.stacked_margin_left_pct = gxtxt_envnum_default('GXTXT_PLOT_STACKED_MARGIN_LEFT_PCT',10);
  p.stacked_margin_right_pct = gxtxt_envnum_default('GXTXT_PLOT_STACKED_MARGIN_RIGHT_PCT',4);
  p.stacked_margin_top_pct = gxtxt_envnum_default('GXTXT_PLOT_STACKED_MARGIN_TOP_PCT',10);
  p.stacked_margin_bottom_pct = gxtxt_envnum_default('GXTXT_PLOT_STACKED_MARGIN_BOTTOM_PCT',10);
  p.stacked_gap_pct = gxtxt_envnum_default('GXTXT_PLOT_STACKED_GAP_PCT',2.5);
  p.stacked_align_ylabels = gxtxt_envnum_default('GXTXT_PLOT_STACKED_ALIGN_YLABELS',1) != 0;
  p.stacked_ylabel_x = gxtxt_envnum_default('GXTXT_PLOT_STACKED_YLABEL_X',-0.085);
  p.legend_mode = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_MODE','inside')));
  p.legend_location = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_LOCATION','northeast')));
  p.legend_orientation = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_ORIENTATION','auto'))); % legacy fallback
  p.legend_layout = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_LAYOUT','auto')));
  p.legend_alignment = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_ALIGNMENT','center')));
  if (!any(strcmp(p.legend_layout,{'auto','row','stacked','wrapped'}))), p.legend_layout='auto'; endif
  if (!any(strcmp(p.legend_alignment,{'start','center','end'}))), p.legend_alignment='center'; endif
  p.legend_columns = round(gxtxt_envnum_default('GXTXT_PLOT_LEGEND_COLUMNS',1));
  p.legend_background = strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_BACKGROUND','#FFFFFF'));
  p.legend_border = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_BORDER',1) != 0;
  p.legend_external_border = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_EXTERNAL_BORDER',0) != 0;
  p.legend_border_color = strtrim(gxtxt_getenv_default('GXTXT_PLOT_LEGEND_BORDER_COLOR','#808080'));
  p.legend_external_margin_px = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_EXTERNAL_MARGIN_PX',12);
  p.legend_manual_x = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_MANUAL_X',0.75);
  p.legend_manual_y = gxtxt_envnum_default('GXTXT_PLOT_LEGEND_MANUAL_Y',0.85);
  p.background = gxtxt_getenv_default('GXTXT_PLOT_BACKGROUND','#FFFFFF');
  % Scientific Plot Framework API v1: generic 3D view and color defaults.
  p.view_azimuth = gxtxt_envnum_default('GXTXT_PLOT3D_AZIMUTH',-37.5);
  p.view_elevation = gxtxt_envnum_default('GXTXT_PLOT3D_ELEVATION',30);
  p.projection = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT3D_PROJECTION','orthographic')));
  if (!any(strcmp(p.projection,{'orthographic','perspective'}))), p.projection='orthographic'; endif
  p.aspect_mode = lower(strtrim(gxtxt_getenv_default('GXTXT_PLOT3D_ASPECT_MODE','auto')));
  p.aspect_ratio = strtrim(gxtxt_getenv_default('GXTXT_PLOT3D_ASPECT_RATIO',''));
  if (!any(strcmp(p.aspect_mode,{'auto','xy_equal','data_equal','manual'})))
    error('GXTXT:AspectMode','Unknown 3D aspect mode: %s',p.aspect_mode);
  endif
  p.colormap = strtrim(gxtxt_getenv_default('GXTXT_PLOT_COLORMAP','viridis'));
  p.colorbar_visible = gxtxt_envnum_default('GXTXT_PLOT_COLORBAR_VISIBLE',0) != 0;
  p.colorbar_label = strtrim(gxtxt_getenv_default('GXTXT_PLOT_COLORBAR_LABEL',''));
  p.color_unit = strtrim(gxtxt_getenv_default('GXTXT_PLOT_COLOR_UNIT','auto'));
  p.color_min = str2double(strtrim(getenv('GXTXT_PLOT_COLOR_MIN')));
  p.color_max = str2double(strtrim(getenv('GXTXT_PLOT_COLOR_MAX')));

  if (!isfinite(p.width_px) || p.width_px < 320), p.width_px = 1600; endif
  if (!isfinite(p.height_px) || p.height_px < 240), p.height_px = 900; endif
  if (!isfinite(p.dpi) || p.dpi < 72), p.dpi = 200; endif
  if (!isfinite(p.font_size) || p.font_size <= 0), p.font_size = gxtxt_plot_font_to_points(12,p.font_unit,p.dpi); endif
  if (!isfinite(p.axis_label_font_size) || p.axis_label_font_size <= 0), p.axis_label_font_size = NaN; endif
  if (!isfinite(p.title_font_size) || p.title_font_size <= 0), p.title_font_size = NaN; endif
  if (!isfinite(p.legend_font_size) || p.legend_font_size <= 0), p.legend_font_size = gxtxt_plot_font_to_points(10,p.legend_font_unit,p.dpi); endif
  p.stacked_margin_left_pct = min(30,max(0,p.stacked_margin_left_pct));
  p.stacked_margin_right_pct = min(30,max(0,p.stacked_margin_right_pct));
  p.stacked_margin_top_pct = min(30,max(0,p.stacked_margin_top_pct));
  p.stacked_margin_bottom_pct = min(30,max(0,p.stacked_margin_bottom_pct));
  p.stacked_gap_pct = min(30,max(0,p.stacked_gap_pct));
  if (!isfinite(p.stacked_ylabel_x)), p.stacked_ylabel_x = -0.085; endif
  p.stacked_ylabel_x = min(0.2,max(-0.5,p.stacked_ylabel_x));
  if (!isfinite(p.line_width) || p.line_width <= 0), p.line_width = 1.4; endif
  if (!isfinite(p.legend_columns) || p.legend_columns < 1), p.legend_columns = 1; endif
  if (!isfinite(p.legend_external_margin_px) || p.legend_external_margin_px < 0), p.legend_external_margin_px = 12; endif
  p.legend_external_margin_px = min(100,max(0,p.legend_external_margin_px));
  if (!isfinite(p.legend_manual_x)), p.legend_manual_x = 0.75; endif
  if (!isfinite(p.legend_manual_y)), p.legend_manual_y = 0.85; endif
  if (!isfinite(p.view_azimuth)), p.view_azimuth=-37.5; endif
  if (!isfinite(p.view_elevation)), p.view_elevation=30; endif
  p.view_elevation=min(90,max(-90,p.view_elevation));
  if (isempty(p.colormap)), p.colormap='viridis'; endif
  if (!isfinite(p.color_min)), p.color_min=NaN; endif
  if (!isfinite(p.color_max)), p.color_max=NaN; endif
  if (isfinite(p.color_min) && isfinite(p.color_max) && p.color_min>=p.color_max), p.color_min=NaN; p.color_max=NaN; endif
  p.legend_manual_x = min(1,max(0,p.legend_manual_x));
  p.legend_manual_y = min(1,max(0,p.legend_manual_y));
endfunction
