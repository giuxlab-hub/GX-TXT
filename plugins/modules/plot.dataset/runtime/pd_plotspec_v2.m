function V=pd_plotspec_v2(cfg,graph)
% Load optional public PLOT_DATASET_PLOTSPEC_v2 sidecar for one 2D graph.
% Missing sidecar means the stable v1 rendering path is unchanged.
% PlotSpec v2 supports one or more vertically stacked shared-X panels for
% plot.dataset.xy; plot.dataset.xy_region remains single-panel.
% SPDX-License-Identifier: GPL-3.0-or-later
  V=empty_spec();
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)||isempty(graph)),return;endif
  variant='';pg=strtrim(gxtxt_ini_get(cfg,'plot_variant.graph_id',''));if(strcmp(pg,graph)),variant=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));endif
  token=strrep(strrep(strrep(graph,'.','_'),'/','_'),'\\','_');if(isempty(variant)),vtoken='base';else vtoken=variant;endif
  path=fullfile(session,'metadata','plot.dataset','plotspec_v2',[token '--' vtoken '.ini']);
  if(exist(path,'file')!=2),return;endif
  d=gxtxt_ini_read(path);
  if(!strcmp(strtrim(gxtxt_ini_get(d,'plotspec.schema','')),'PLOT_DATASET_PLOTSPEC_v2')),error('plot.dataset: invalid PlotSpec v2 schema: %s',path);endif
  if(!strcmp(strtrim(gxtxt_ini_get(d,'plotspec.graph_id','')),graph)),error('plot.dataset: PlotSpec v2 graph mismatch');endif
  V.enabled=true;V.path=path;V.graph_type=strtrim(gxtxt_ini_get(d,'plotspec.graph_type','cartesian_2d'));V.variant_id=variant;
  V.title_present=is_true(gxtxt_ini_get(d,'plotspec.title_present','0'));V.title=gxtxt_ini_get(d,'plotspec.title','');
  V.output_extra_format=lower(strtrim(gxtxt_ini_get(d,'plotspec.output_extra_format','none')));
  V.default_style=read_style(d,'plotspec','default_style');
  pc=parse_count(gxtxt_ini_get(d,'plotspec.panel_count','1'),'panel_count');if(pc<1),error('plot.dataset: PlotSpec v2 requires at least one panel');endif
  mp_present=is_true(gxtxt_ini_get(d,'plotspec.multi_panel_present','0'));
  if(mp_present),V.multi_panel=is_true(gxtxt_ini_get(d,'plotspec.multi_panel','0'));else V.multi_panel=(pc>1);endif
  if(strcmp(graph,'plot.dataset.xy_region')&&(pc!=1||V.multi_panel)),error('plot.dataset: plot.dataset.xy_region remains single-panel');endif
  for pi=1:pc
    psec=sprintf('panel.%d',pi);P=empty_panel();
    P.id=strtrim(gxtxt_ini_get(d,[psec '.id'],sprintf('panel%d',pi)));
    if(is_true(gxtxt_ini_get(d,[psec '.title_present'],'0'))),P.title=gxtxt_ini_get(d,[psec '.title'],'');endif
    P.axes.x=read_axis(d,psec,'axis.x');P.axes.y_left=read_axis(d,psec,'axis.y_left');P.axes.y_right=read_axis(d,psec,'axis.y_right');
    n=parse_count(gxtxt_ini_get(d,[psec '.series_count'],'0'),'series_count');
    for i=1:n
      sec=sprintf('%s.series.%d',psec,i);s=empty_series();
      s.id=strtrim(gxtxt_ini_get(d,[sec '.id'],''));s.panel_id=P.id;s.dataset_id=strtrim(gxtxt_ini_get(d,[sec '.dataset_id'],''));s.x_variable_id=strtrim(gxtxt_ini_get(d,[sec '.x_variable_id'],''));s.y_variable_id=strtrim(gxtxt_ini_get(d,[sec '.y_variable_id'],''));
      s.axis=lower(strtrim(gxtxt_ini_get(d,[sec '.axis'],'left')));s.family_variable_id=strtrim(gxtxt_ini_get(d,[sec '.family_variable_id'],''));s.family_label_prefix=gxtxt_ini_get(d,[sec '.family_label_prefix'],'');s.source_row_continuity=is_true(gxtxt_ini_get(d,[sec '.source_row_continuity'],'0'));s.label=gxtxt_ini_get(d,[sec '.label'],'');s.enabled=is_true(gxtxt_ini_get(d,[sec '.enabled'],'1'));s.kind=lower(strtrim(gxtxt_ini_get(d,[sec '.kind'],'auto')));s.order=str2double(gxtxt_ini_get(d,[sec '.order'],sprintf('%d',i)));if(!isfinite(s.order)),s.order=i;endif
      s.step_mode=lower(strtrim(gxtxt_ini_get(d,[sec '.step_mode'],'post')));s.bar_width=strtrim(gxtxt_ini_get(d,[sec '.bar_width'],'auto'));s.bar_baseline=strtrim(gxtxt_ini_get(d,[sec '.bar_baseline'],'auto'));
      s.histogram_bins=strtrim(gxtxt_ini_get(d,[sec '.histogram_bins'],'auto'));s.histogram_normalization=lower(strtrim(gxtxt_ini_get(d,[sec '.histogram_normalization'],'count')));
      s.box_whisker_iqr=strtrim(gxtxt_ini_get(d,[sec '.box_whisker_iqr'],'1.5'));s.box_show_outliers=is_true(gxtxt_ini_get(d,[sec '.box_show_outliers'],'1'));
      s.style=read_style(d,sec,'style');s.x_error=read_error(d,sec,'x_error');s.y_error=read_error(d,sec,'y_error');s.band=read_band(d,sec,'band');s.bar_bounds=read_bar_bounds(d,sec,'bar_bounds');
      P.series_ids{end+1}=s.id;V.series(end+1)=s; %#ok<AGROW>
    endfor
    n=parse_count(gxtxt_ini_get(d,[psec '.annotation_count'],'0'),'annotation_count');
    for i=1:n
      sec=sprintf('%s.annotation.%d',psec,i);a=empty_annotation();
      for f={'type','axis','value','min','max','x','y','label','color','line_style','line_width','opacity'}
        q=gxtxt_ini_get(d,[sec '.' f{1}],'');if(!isempty(q)),a.(f{1})=q;endif
      endfor
      P.annotations(end+1)=a; %#ok<AGROW>
    endfor
    V.panels(end+1)=P; %#ok<AGROW>
  endfor
  V.panel_count=numel(V.panels);
  % Backward-compatible aliases used by existing helpers.  X is graph-wide
  % for multi-panel plots, so merge the compatible panel declarations instead
  % of silently treating panel 1 as the X authority.  Y aliases remain panel 1
  % because legacy helpers are single-panel/Y-local by design.
  if(V.panel_count>=1)
    V.axes=V.panels(1).axes;V.axes.x=merged_shared_x(V.panels);V.annotations=V.panels(1).annotations;
  endif
endfunction

function x=merged_shared_x(panels)
  x=struct();
  fields={'label','display_unit','scale','direction','min','max','tick_positions','tick_labels','major_step','minor_grid'};
  for pi=1:numel(panels)
    if(!isfield(panels(pi),'axes')||!isfield(panels(pi).axes,'x')),continue;endif
    a=panels(pi).axes.x;
    for fi=1:numel(fields)
      f=fields{fi};if(!isfield(a,f)),continue;endif
      v=a.(f);if(ischar(v)),v=strtrim(v);endif
      if(isempty(v)),continue;endif
      if(!isfield(x,f)),x.(f)=v;endif
    endfor
  endfor
endfunction

function V=empty_spec()
  V=struct('enabled',false,'path','','graph_type','cartesian_2d','variant_id','','title_present',false,'title','','multi_panel',false,'default_style',struct(), ...
    'panel_count',1,'panels',empty_panels(),'axes',struct('x',struct(),'y_left',struct(),'y_right',struct()),'series',empty_series_array(),'annotations',empty_annotations(),'output_extra_format','none');
endfunction

function p=empty_panels(),p=struct('id',{},'title',{},'axes',{},'series_ids',{},'annotations',{});endfunction
function p=empty_panel(),p=struct('id','main','title','','axes',struct('x',struct(),'y_left',struct(),'y_right',struct()),'series_ids',{{}},'annotations',empty_annotations());endfunction
function a=empty_annotations(),a=struct('type',{},'axis',{},'value',{},'min',{},'max',{},'x',{},'y',{},'label',{},'color',{},'line_style',{},'line_width',{},'opacity',{});endfunction
function a=empty_annotation(),a=struct('type','','axis','x','value','','min','','max','','x','','y','','label','','color','','line_style','','line_width','','opacity','');endfunction
function a=empty_series_array(),a=struct('id',{},'panel_id',{},'dataset_id',{},'x_variable_id',{},'y_variable_id',{},'family_variable_id',{},'family_label_prefix',{},'source_row_continuity',{},'axis',{},'label',{},'enabled',{},'kind',{},'order',{},'step_mode',{},'bar_width',{},'bar_baseline',{},'histogram_bins',{},'histogram_normalization',{},'box_whisker_iqr',{},'box_show_outliers',{},'style',{},'x_error',{},'y_error',{},'band',{},'bar_bounds',{});endfunction
function s=empty_series(),s=struct('id','','panel_id','main','dataset_id','','x_variable_id','','y_variable_id','','family_variable_id','','family_label_prefix','','source_row_continuity',false,'axis','left','label','','enabled',true,'kind','auto','order',0,'step_mode','post','bar_width','auto','bar_baseline','auto','histogram_bins','auto','histogram_normalization','count','box_whisker_iqr','1.5','box_show_outliers',true,'style',struct(),'x_error',empty_error(),'y_error',empty_error(),'band',struct(),'bar_bounds',struct());endfunction
function e=empty_error(),e=struct('mode','none','variable_id','','lower_variable_id','','upper_variable_id','');endfunction
function n=parse_count(s,label),n=str2double(s);if(!isfinite(n)||n<0||round(n)!=n),error('plot.dataset: invalid PlotSpec v2 %s',label);endif;n=round(n);endfunction
function tf=is_true(s),tf=any(strcmpi(strtrim(s),{'1','true','yes','on'}));endfunction
function out=read_style(d,sec,prefix)
  out=struct();for f={'color','line_style','line_width','marker','marker_size','marker_fill','opacity'},name=f{1};if(is_true(gxtxt_ini_get(d,[sec '.' prefix '.' name '.present'],'0'))),out.(name)=gxtxt_ini_get(d,[sec '.' prefix '.' name '.value'],'');endif;endfor
endfunction
function out=read_axis(d,sec,prefix)
  out=struct();for f={'label','display_unit','scale','direction','min','max','tick_positions','tick_labels','major_step','minor_grid'},name=f{1};if(is_true(gxtxt_ini_get(d,[sec '.' prefix '.' name '.present'],'0'))),out.(name)=gxtxt_ini_get(d,[sec '.' prefix '.' name '.value'],'');endif;endfor
endfunction
function out=read_error(d,sec,prefix)
  out=empty_error();present=false;for f={'mode','variable_id','lower_variable_id','upper_variable_id'},name=f{1};if(is_true(gxtxt_ini_get(d,[sec '.' prefix '.' name '.present'],'0'))),out.(name)=gxtxt_ini_get(d,[sec '.' prefix '.' name '.value'],'');present=true;endif;endfor;if(!present),out.mode='none';endif
endfunction
function out=read_band(d,sec,prefix)
  out=struct();for f={'lower_variable_id','upper_variable_id','draw_center'},name=f{1};if(is_true(gxtxt_ini_get(d,[sec '.' prefix '.' name '.present'],'0'))),out.(name)=gxtxt_ini_get(d,[sec '.' prefix '.' name '.value'],'');endif;endfor
endfunction
function out=read_bar_bounds(d,sec,prefix)
  out=struct();for f={'lower_variable_id','upper_variable_id'},name=f{1};if(is_true(gxtxt_ini_get(d,[sec '.' prefix '.' name '.present'],'0'))),out.(name)=gxtxt_ini_get(d,[sec '.' prefix '.' name '.value'],'');endif;endfor
endfunction
