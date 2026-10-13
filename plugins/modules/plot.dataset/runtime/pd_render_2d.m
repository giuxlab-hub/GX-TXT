function pd_render_2d(outdir,cfg,P,graph,file_name)
% Render one framework-native 2D graph (single or dual Y).
% Graph Series are the only scientific 2D binding authority. PlotSpec v2
% supplies presentation and auxiliary bindings only.
% SPDX-License-Identifier: GPL-3.0-or-later
  pcfg=gxtxt_plot_config();series=P.series;n=numel(series);
  left=find(strcmp({series.axis},'left'));right=find(strcmp({series.axis},'right'));
  if(isempty(left)),error('plot.dataset: at least one left-axis Graph Series is required');endif
  V=plotspec(P);core_axis_state=core_axis_state_declared(cfg,graph);core_axis_enabled=core_axis_state_enabled(cfg,graph);
  distribution=distribution_kind(series);
  if(!isempty(distribution))
    pd_render_2d_distribution(outdir,cfg,P,graph,file_name,V,distribution,core_axis_state,core_axis_enabled);
    return;
  endif
  if(V.enabled&&isfield(V,'multi_panel')&&V.multi_panel&&isfield(V,'panel_count')&&V.panel_count>1)
    if(strcmp(graph,'plot.dataset.xy_region')),error('plot.dataset: plot.dataset.xy_region remains single-panel');endif
    pd_render_2d_multipanel(outdir,cfg,P,graph,file_name,V,core_axis_state,core_axis_enabled);
    return;
  endif

  xdu=pd_x_display_unit(P,cfg,graph);
  lvals=cell(1,numel(left));lunits=cell(1,numel(left));for j=1:numel(left),lvals{j}=series(left(j)).data.y;lunits{j}=series(left(j)).meta.unit;endfor
  ymode=effective_axis_unit(V,'y_left',axis_mode(cfg,graph,'y'),core_axis_state,core_axis_enabled);[ydu,~]=pd_common_display_unit(lvals,lunits,ymode,'Y Left axis');
  y2du='';if(!isempty(right))
    rvals=cell(1,numel(right));runits=cell(1,numel(right));for j=1:numel(right),rvals{j}=series(right(j)).data.y;runits{j}=series(right(j)).meta.unit;endfor
    y2mode=effective_axis_unit(V,'y_right',axis_mode(cfg,graph,'y2'),core_axis_state,core_axis_enabled);[y2du,~]=pd_common_display_unit(rvals,runits,y2mode,'Y Right axis');
  endif

  ylevel=gxtxt_level_scale_config(cfg,graph,'y');y2level=gxtxt_level_scale_config(cfg,graph,'y2');ylevel_label='';y2level_label='';
  fig=gxtxt_plot_new_figure(pcfg);
  if(isempty(right)),ax1=axes('parent',fig);set(ax1,'tag','gxtxt_primary_axis');hold(ax1,'on');ax2=[];else [ax1,ax2]=gxtxt_plot_dual_y_axes(fig,pcfg);endif
  palette=lines(max(7,n+family_group_total(series)));

  graph_kind=graph_default_kind(cfg,graph);
  order_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.point_order'],'auto')));if(strcmp(order_mode,'auto')),order_mode='dataset_order';endif
  if(isfield(P,'mode')&&strcmp(P.mode,'graph_series')),order_mode='dataset_order';endif
  if(!any(strcmp(order_mode,{'dataset_order','sort_x'}))),order_mode='dataset_order';endif
  graph_lw=parse_line_width(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'inherit'),pcfg.line_width);graph_ms=parse_positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
  legend_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.legend_content'],'auto')));if(strcmp(legend_mode,'auto')),legend_mode='series';endif
  if(!any(strcmp(legend_mode,{'none','series'}))),legend_mode='series';endif

  handles=[];labels={};xfactor_meta=1;yfactor_meta=1;y2factor_meta=1;color_cursor=0;
  for k=1:n
    S=series(k);ax=ax1;target_y=ydu;level=ylevel;if(strcmp(S.axis,'right')),ax=ax2;target_y=y2du;level=y2level;endif
    [xd,~,xf]=pd_convert_display(S.data.x,S.x_meta.unit,xdu,'X');[yraw,~,yf]=pd_convert_display(S.data.y,S.meta.unit,target_y,['Y ' S.axis]);[yd,level_label]=gxtxt_level_scale_apply(yraw,target_y,level);
    if(strcmp(S.axis,'right')),if(!isempty(level_label)),y2level_label=level_label;endif;else if(!isempty(level_label)),ylevel_label=level_label;endif;endif
    if(k==1),xfactor_meta=xf;endif;if(strcmp(S.axis,'left')&&k==left(1)),yfactor_meta=yf;endif;if(!isempty(right)&&strcmp(S.axis,'right')&&k==right(1)),y2factor_meta=yf;endif

    xp=xd;yp=yd;ypr=yraw;idx=(1:numel(xp))';ord=(1:numel(xp))';if(strcmp(order_mode,'sort_x')&&!(isfield(S.data,'ordering_variable_id')&&!isempty(S.data.ordering_variable_id))),[xp,ord]=sort(xp);yp=yp(ord);ypr=ypr(ord);idx=idx(ord);endif
    kind=series_kind(S,graph_kind);
    if(has_family_group(S))
      [fh,fl,color_cursor]=draw_family_series(ax,S,V,xp,yp,idx,kind,graph_lw,graph_ms,palette,color_cursor,legend_mode);
      handles=[handles fh];labels=[labels fl]; %#ok<AGROW>
      continue;
    endif
    color_cursor+=1;auto_color=palette(mod(color_cursor-1,rows(palette))+1,:);st=resolve_style(S,V,kind,graph_lw,graph_ms,auto_color);

    hband=[];if(isfield(S.presentation,'band')&&!isempty(fieldnames(S.presentation.band))),[blo,bhi]=band_values(S,idx,1:numel(idx),target_y,level);hband=draw_band(ax,xp,blo,bhi,st,kind);endif
    hbase=[];
    if(strcmp(kind,'band'))
      draw_center=true;if(isfield(S.presentation.band,'draw_center')),draw_center=parse_bool(S.presentation.band.draw_center,true);endif;if(draw_center),hbase=draw_trace(ax,xp,yp,'line',st);endif
    elseif(strcmp(kind,'bar')),hbase=draw_bar(ax,xp,yp,S.presentation,st,S,idx,1:numel(idx),xdu,target_y,level);
    elseif(strcmp(kind,'step')),smode='post';if(isfield(S.presentation,'step_mode')&&!isempty(strtrim(S.presentation.step_mode))),smode=S.presentation.step_mode;endif;[xs,ys]=step_xy(xp,yp,smode);hbase=draw_trace(ax,xs,ys,'line',st);
    else [tx,ty]=source_trace(S,xp,yp,idx);hbase=draw_trace(ax,tx,ty,kind,st);endif

    if(has_error(S.presentation,'x_error')||has_error(S.presentation,'y_error'))
      [xl,xu]=error_x_endpoints(S,idx,1:numel(idx),xp,xdu);[yl,yu]=error_y_endpoints(S,idx,1:numel(idx),ypr,target_y,level,yp);draw_error_whiskers(ax,xp,yp,xl,xu,yl,yu,st);
    endif
    hleg=[];if(strcmp(kind,'band')&&!isempty(hband)),hleg=hband;elseif(!isempty(hbase)),hleg=hbase;elseif(!isempty(hband)),hleg=hband;endif
    if(!isempty(hleg)&&strcmp(legend_mode,'series')),handles(end+1)=hleg(1);labels{end+1}=series_label(S,target_y);endif %#ok<AGROW>
  endfor

  gxtxt_plot_set_axis_metadata(ax1,'x',P.x_name,P.x_meta.unit,xdu,xfactor_meta,0);gxtxt_plot_set_axis_metadata(ax1,'y',series(left(1)).name,series(left(1)).meta.unit,ydu,yfactor_meta,0);gxtxt_level_scale_metadata(ax1,ylevel);
  if(!isempty(right)),gxtxt_plot_set_axis_metadata(ax2,'y',series(right(1)).name,series(right(1)).meta.unit,y2du,y2factor_meta,0);gxtxt_level_scale_metadata(ax2,y2level);endif

  title_txt=presentation_value(cfg,graph,'title',gxtxt_ini_get(cfg,['plot.' graph '.title'],'auto'));xl=presentation_value(cfg,graph,'x_label',gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'));yl=presentation_value(cfg,graph,'y_label',gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'));y2l=presentation_value(cfg,graph,'y2_label',gxtxt_ini_get(cfg,['plot.' graph '.y2_label'],'auto'));
  xl=v2_axis_label(V,'x',xl);yl=v2_axis_label(V,'y_left',yl);y2l=v2_axis_label(V,'y_right',y2l);
  if(is_auto(title_txt)),if(n==1),title_txt=sprintf('%s vs %s',display_name(series(1).name),display_name(P.x_name));else title_txt=sprintf('Scientific dataset vs %s',display_name(P.x_name));endif;endif
  if(is_auto(xl)),xl=axis_label(display_name(P.x_name),xdu);endif;xl=display_axis_label(xl,P.x_meta.unit,xdu);
  if(is_auto(yl)),if(numel(left)==1),yl=axis_label(display_name(series(left(1)).name),ydu);else yl=axis_label('Y Left',ydu);endif;endif
  yl=display_axis_label(yl,series(left(1)).meta.unit,ydu);if(!isempty(ylevel_label)),yl=[yl ' (' ylevel_label ')'];endif
  axes(ax1);gxtxt_plot_text('xlabel',xl);gxtxt_plot_text('ylabel',yl);gxtxt_plot_text('title',title_txt);
  if(!isempty(right)),if(is_auto(y2l)),if(numel(right)==1),y2l=axis_label(display_name(series(right(1)).name),y2du);else y2l=axis_label('Y Right',y2du);endif;endif;y2l=display_axis_label(y2l,series(right(1)).meta.unit,y2du);if(!isempty(y2level_label)),y2l=[y2l ' (' y2level_label ')'];endif;axes(ax2);gxtxt_plot_text('ylabel',y2l);endif

  gxtxt_plot_apply_graph_axes(ax1,pcfg,graph,{},cfg);apply_v2_axes(V,ax1,ax2,core_axis_state);
  pad_default_marker_x(ax1,series,V,cfg,graph,xdu,graph_kind);
  if(!isempty(right)),try gxtxt_plot_sync_overlay_axes(fig);catch;end_try_catch;endif
  % Single-panel manual margins use the same per-plot layout authority as a
  % stack. Absolute positions are rebuilt from the stored values on every
  % render, so rerender never compounds a previous calculated rectangle.
  apply_single_panel_layout_overrides(ax1,ax2,cfg,graph);

  % Computed annotations from the Standard Module primary source must not make
  % an unrelated compatibility primary scientifically authoritative for 2D.
  annotations={};if(primary_matches_series(cfg,P)),annotations=gxtxt_data_annotations_from_runtime(cfg,'primary');endif
  if(!isempty(annotations)),ctx=struct();ctx.x_variable=P.x_name;ctx.x_display_unit=xdu;ctx.y_left_variables={series(left).name};ctx.y_left_display_unit=ydu;ctx.y_right_variables={};ctx.y_right_display_unit=y2du;if(!isempty(right)),ctx.y_right_variables={series(right).name};endif;gxtxt_plot_data_annotations_2d(ax1,ax2,annotations,ctx);endif
  draw_v2_annotations(V,ax1,ax2);

  legend_handle=[];if(!isempty(labels)&&!strcmp(legend_mode,'none')),axes(ax1);legend_handle=gxtxt_plot_legend(handles,labels,pcfg,graph,cfg);endif
  auto_place_single_labels(ax1,ax2,cfg,graph,pcfg);
  pd_region_selection_surface(ax1,ax2,legend_handle,fig);pd_region_diagnostic_pre(fig,graph,P);
  if(!isempty(right)),try axes(ax2);catch;end_try_catch;if(!isempty(legend_handle)),try if(strcmpi(get(legend_handle,'type'),'axes')),axes(legend_handle);endif;catch;end_try_catch;endif;endif
  target=fullfile(outdir,file_name);gxtxt_print_png_atomic(fig,target,pcfg.dpi);pd_print_extra(fig,target,V);pd_region_diagnostic_post(target,graph);close(fig);
  fprintf('[plot.dataset] rendered 2D graph=%s file=%s series=%d dual_y=%d plotspec_v2=%d core_axis_state=%d xunit=%s yunit=%s y2unit=%s\n',graph,target,n,!isempty(right),V.enabled,core_axis_state,xdu,ydu,y2du);
endfunction


function mode=distribution_kind(series)
% Histogram and box/whisker are whole-panel statistical representations.
% Mixing them with Cartesian traces would make the axes scientifically
% ambiguous, so the public Tcl API and runtime both reject that state.
  mode='';ordinary=false;
  for k=1:numel(series)
    kind=series_kind(series(k),'line');
    if(any(strcmp(kind,{'histogram','box_whisker'})))
      if(!isempty(mode)&&!strcmp(mode,kind)),error('plot.dataset: histogram and box_whisker may not be mixed in one plot');endif
      mode=kind;
    else
      ordinary=true;
    endif
  endfor
  if(!isempty(mode)&&ordinary),error('plot.dataset: distribution kinds may not be mixed with Cartesian trace kinds');endif
endfunction

function pd_render_2d_distribution(outdir,cfg,P,graph,file_name,V,mode,core_axis_state,core_axis_enabled)
% Render public PlotSpec distribution kinds from the complete prepared Y
% samples. X remains the stable row-coordinate binding but is not transformed
% into fake binned Dataset variables.
  if(!strcmp(graph,'plot.dataset.xy')),error('plot.dataset: distribution kinds are supported only by plot.dataset.xy');endif
  if(V.enabled&&isfield(V,'multi_panel')&&V.multi_panel),error('plot.dataset: distribution kinds require one single panel');endif
  series=P.series;n=numel(series);if(any(strcmp({series.axis},'right'))),error('plot.dataset: distribution kinds use only the left axis');endif
  pcfg=gxtxt_plot_config();values=cell(1,n);units=cell(1,n);
  for k=1:n,values{k}=series(k).data.y;units{k}=series(k).meta.unit;endfor
  unit_mode=effective_axis_unit(V,'y_left',axis_mode(cfg,graph,'y'),core_axis_state,core_axis_enabled);
  [value_unit,~]=pd_common_display_unit(values,units,unit_mode,'Distribution value axis');
  fig=gxtxt_plot_new_figure(pcfg);ax=axes('parent',fig);set(ax,'tag','gxtxt_primary_axis');hold(ax,'on');
  palette=get(ax,'colororder');if(isempty(palette)),palette=lines(max(7,n));endif
  graph_lw=parse_line_width(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'inherit'),pcfg.line_width);graph_ms=parse_positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
  handles=[];labels={};box_labels=cell(1,n);normalization='count';factor_meta=1;
  for k=1:n
    S=series(k);[sample,~,factor]=pd_convert_display(S.data.y,S.meta.unit,value_unit,'Distribution value');sample=sample(isfinite(sample));
    if(isempty(sample)),error('plot.dataset: distribution series %s has no finite samples',S.series_id);endif
    if(k==1),factor_meta=factor;endif
    st=resolve_style(S,V,mode,graph_lw,graph_ms,palette(mod(k-1,rows(palette))+1,:));h=[];
    if(strcmp(mode,'histogram'))
      bins=distribution_histogram_bins(S.presentation,numel(sample));normalization=distribution_histogram_normalization(S.presentation);
      [centers,heights]=distribution_histogram(sample,bins,normalization);
      h=bar(ax,centers,heights,1,'facecolor',st.color,'edgecolor',st.color);try set(h,'facealpha',min(0.75,st.opacity));catch;end_try_catch
    else
      multiplier=distribution_box_iqr(S.presentation);show_outliers=distribution_box_outliers(S.presentation);
      h=draw_box_whisker(ax,k,sample,st,multiplier,show_outliers);
      box_labels{k}=series_label(S,value_unit);
    endif
    if(!isempty(h)),handles(end+1)=h(1);labels{end+1}=series_label(S,value_unit);endif %#ok<AGROW>
  endfor

  title_txt=presentation_value(cfg,graph,'title',gxtxt_ini_get(cfg,['plot.' graph '.title'],'auto'));xl=presentation_value(cfg,graph,'x_label',gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'));yl=presentation_value(cfg,graph,'y_label',gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'));
  xl=v2_axis_label(V,'x',xl);yl=v2_axis_label(V,'y_left',yl);
  if(strcmp(mode,'histogram'))
    if(is_auto(title_txt)),title_txt='Histogram';endif
    if(is_auto(xl)),if(n==1),xl=axis_label(display_name(series(1).name),value_unit);else xl=axis_label('Value',value_unit);endif;endif
    if(is_auto(yl)),if(strcmp(normalization,'probability')),yl='Probability';elseif(strcmp(normalization,'density')),yl='Probability density';else yl='Count';endif;endif
    gxtxt_plot_set_axis_metadata(ax,'x',series(1).name,series(1).meta.unit,value_unit,factor_meta,0);gxtxt_plot_set_axis_metadata(ax,'y','histogram_count','','',1,0);
  else
    if(is_auto(title_txt)),title_txt='Box-and-whisker plot';endif
    if(is_auto(xl)),xl='Series';endif
    if(is_auto(yl)),if(n==1),yl=axis_label(display_name(series(1).name),value_unit);else yl=axis_label('Value',value_unit);endif;endif
    set(ax,'xlim',[0.25 n+0.75],'xtick',1:n,'xticklabel',box_labels);
    gxtxt_plot_set_axis_metadata(ax,'x','series','','',1,0);gxtxt_plot_set_axis_metadata(ax,'y',series(1).name,series(1).meta.unit,value_unit,factor_meta,0);
  endif
  axes(ax);gxtxt_plot_text('xlabel',xl);gxtxt_plot_text('ylabel',yl);gxtxt_plot_text('title',title_txt);
  gxtxt_plot_apply_graph_axes(ax,pcfg,graph,{},cfg);apply_v2_axes(V,ax,[],core_axis_state);apply_single_panel_layout_overrides(ax,[],cfg,graph);draw_v2_annotations(V,ax,[]);
  legend_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.legend_content'],'auto')));if(strcmp(legend_mode,'auto')),legend_mode='series';endif
  legend_handle=[];if(!isempty(labels)&&!strcmp(legend_mode,'none')),legend_handle=gxtxt_plot_legend(handles,labels,pcfg,graph,cfg);endif
  target=fullfile(outdir,file_name);gxtxt_print_png_atomic(fig,target,pcfg.dpi);pd_print_extra(fig,target,V);close(fig);
  fprintf('[plot.dataset] rendered distribution graph=%s kind=%s file=%s series=%d full_samples=1\n',graph,mode,target,n);
endfunction

function bins=distribution_histogram_bins(pres,n)
  bins=max(5,min(100,ceil(sqrt(max(1,n)))));
  if(isfield(pres,'histogram_bins'))
    q=strtrim(pres.histogram_bins);v=str2double(q);if(isfinite(v)&&v>=2&&v<=512&&round(v)==v),bins=round(v);endif
  endif
endfunction
function normalization=distribution_histogram_normalization(pres)
  normalization='count';if(isfield(pres,'histogram_normalization')),q=lower(strtrim(pres.histogram_normalization));if(any(strcmp(q,{'count','probability','density'}))),normalization=q;endif;endif
endfunction
function [centers,heights]=distribution_histogram(sample,bins,normalization)
  lo=min(sample);hi=max(sample);if(lo==hi),pad=max(0.5,abs(lo)*0.05);lo-=pad;hi+=pad;endif
  edges=linspace(lo,hi,bins+1);counts=histc(sample,edges);counts(end-1)+=counts(end);counts=counts(1:end-1);centers=(edges(1:end-1)+edges(2:end))/2;heights=counts(:)';
  if(strcmp(normalization,'probability')),heights/=max(1,sum(heights));elseif(strcmp(normalization,'density')),heights/=(max(1,sum(heights))*(edges(2)-edges(1)));endif
endfunction
function multiplier=distribution_box_iqr(pres),multiplier=1.5;if(isfield(pres,'box_whisker_iqr')),v=str2double(pres.box_whisker_iqr);if(isfinite(v)&&v>0),multiplier=v;endif;endif;endfunction
function show=distribution_box_outliers(pres),show=true;if(isfield(pres,'box_show_outliers')),show=parse_bool(pres.box_show_outliers,true);endif;endfunction
function q=distribution_quantile(sorted,p)
  n=numel(sorted);if(n==1),q=sorted(1);return;endif;pos=1+(n-1)*p;lo=floor(pos);hi=ceil(pos);if(lo==hi),q=sorted(lo);else q=sorted(lo)+(pos-lo)*(sorted(hi)-sorted(lo));endif
endfunction
function h=draw_box_whisker(ax,position,sample,st,multiplier,show_outliers)
  sample=sort(sample(:));q1=distribution_quantile(sample,0.25);med=distribution_quantile(sample,0.5);q3=distribution_quantile(sample,0.75);iqr=q3-q1;
  inside=sample(sample>=q1-multiplier*iqr&sample<=q3+multiplier*iqr);if(isempty(inside)),inside=sample;endif;wlo=min(inside);whi=max(inside);width=0.56;
  % Headless gnuplot may omit a patch entirely; draw the full box outline as
  % ordinary line data so the interquartile range remains visible in PNG/PDF.
  h=plot(ax,[position-width/2 position+width/2 position+width/2 position-width/2 position-width/2],[q1 q1 q3 q3 q1],'-','color',st.color,'linewidth',st.line_width);
  plot(ax,[position-width/2 position+width/2],[med med],'-','color',st.color,'linewidth',max(1.2,st.line_width));plot(ax,[position position],[wlo q1],'-','color',st.color,'linewidth',st.line_width);plot(ax,[position position],[q3 whi],'-','color',st.color,'linewidth',st.line_width);plot(ax,[position-width/4 position+width/4],[wlo wlo],'-','color',st.color,'linewidth',st.line_width);plot(ax,[position-width/4 position+width/4],[whi whi],'-','color',st.color,'linewidth',st.line_width);
  if(show_outliers),out=sample(sample<wlo|sample>whi);if(!isempty(out)),plot(ax,position*ones(size(out)),out,'linestyle','none','marker','o','markersize',max(2,st.marker_size),'color',st.color);endif;endif
endfunction


function pd_render_2d_multipanel(outdir,cfg,P,graph,file_name,V,core_axis_state,core_axis_enabled)
% Render vertically stacked PlotSpec v2 panels with one synchronized X domain.
% Graph Series identity remains dataset_id + x_variable_id + y_variable_id;
% panel membership is presentation state keyed by series_id.
  pcfg=gxtxt_plot_config();series=P.series;n=numel(series);np=V.panel_count;
  % Pristine defaults. Every stacked geometry pass is computed from these,
  % never from the previous pass' output, so repeated passes converge on the
  % same layout instead of accumulating margins.
  pcfg0=pcfg;
  xdu=pd_x_display_unit(P,cfg,graph);
  graph_kind=graph_default_kind(cfg,graph);
  order_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.point_order'],'auto')));if(strcmp(order_mode,'auto')),order_mode='dataset_order';endif
  if(isfield(P,'mode')&&strcmp(P.mode,'graph_series')),order_mode='dataset_order';endif
  if(!any(strcmp(order_mode,{'dataset_order','sort_x'}))),order_mode='dataset_order';endif
  graph_lw=parse_line_width(gxtxt_ini_get(cfg,['plot.' graph '.line_width'],'inherit'),pcfg.line_width);graph_ms=parse_positive(gxtxt_ini_get(cfg,['plot.' graph '.marker_size'],'4'),4);
  legend_mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.legend_content'],'auto')));if(strcmp(legend_mode,'auto')),legend_mode='series';endif
  if(!any(strcmp(legend_mode,{'none','series'}))),legend_mode='series';endif

  fig=gxtxt_plot_new_figure(pcfg);
  primary=zeros(1,np);right_axes=cell(1,np);panel_names=cell(1,np);legend_handles=cell(1,np);legend_series_handles=cell(1,np);legend_series_labels=cell(1,np);
  palette=lines(max(7,n));xmeta_factor=1;
  % Multi-panel X uses the same merged PlotSpec X authority as single-panel.
  % pd_plotspec_v2() already validates/merges the shared-X declaration into
  % V.axes.x; do not maintain a second renderer-local X configuration path.
  shared_x=V.axes.x;

  for pi=1:np
    panel=V.panels(pi);panel_names{pi}=panel.id;
    idxs=panel_series_indices(series,panel.series_ids);
    ridx=idxs(strcmp({series(idxs).axis},'right'));lidx=idxs(strcmp({series(idxs).axis},'left'));
    % Build a dual-Y panel with the exact same CORE primitive used by the
    % working single-panel renderer.  Retag only after CORE has established
    % the synchronized inner data rectangle.
    ax2=[];
    if(!isempty(ridx))
      [primary(pi),ax2]=gxtxt_plot_dual_y_axes(fig,pcfg);
    else
      primary(pi)=axes('parent',fig);hold(primary(pi),'on');
      try gxtxt_plot_apply_axes(primary(pi),pcfg);catch;end_try_catch
    endif
    set(primary(pi),'tag',sprintf('gxtxt_panel_%d',pi));
    if(!isempty(ax2)),set(ax2,'tag',sprintf('gxtxt_panel_%d_overlay_yaxis',pi));endif
    right_axes{pi}=ax2;

    ydu='';y2du='';ylevel=gxtxt_level_scale_config(cfg,graph,'y');y2level=gxtxt_level_scale_config(cfg,graph,'y2');ylevel_label='';y2level_label='';
    if(!isempty(lidx))
      vals=cell(1,numel(lidx));units=cell(1,numel(lidx));for j=1:numel(lidx),vals{j}=series(lidx(j)).data.y;units{j}=series(lidx(j)).meta.unit;endfor
      ymode=effective_panel_axis_unit(panel,'y_left',axis_mode(cfg,graph,'y'),core_axis_state,core_axis_enabled);[ydu,~]=pd_common_display_unit(vals,units,ymode,sprintf('Panel %s Y Left axis',panel.id));
    endif
    if(!isempty(ridx))
      vals=cell(1,numel(ridx));units=cell(1,numel(ridx));for j=1:numel(ridx),vals{j}=series(ridx(j)).data.y;units{j}=series(ridx(j)).meta.unit;endfor
      y2mode=effective_panel_axis_unit(panel,'y_right',axis_mode(cfg,graph,'y2'),core_axis_state,core_axis_enabled);[y2du,~]=pd_common_display_unit(vals,units,y2mode,sprintf('Panel %s Y Right axis',panel.id));
    endif

    handles=[];labels={};yfactor_meta=1;y2factor_meta=1;
    for jj=1:numel(idxs)
      k=idxs(jj);S=series(k);ax=primary(pi);target_y=ydu;level=ylevel;if(strcmp(S.axis,'right')),ax=ax2;target_y=y2du;level=y2level;endif
      [xd,~,xf]=pd_convert_display(S.data.x,S.x_meta.unit,xdu,'X');[yraw,~,yf]=pd_convert_display(S.data.y,S.meta.unit,target_y,['Y ' S.axis]);[yd,level_label]=gxtxt_level_scale_apply(yraw,target_y,level);
      if(pi==1&&jj==1),xmeta_factor=xf;endif
      if(strcmp(S.axis,'right')),if(!isempty(level_label)),y2level_label=level_label;endif;if(k==ridx(1)),y2factor_meta=yf;endif;else if(!isempty(level_label)),ylevel_label=level_label;endif;if(!isempty(lidx)&&k==lidx(1)),yfactor_meta=yf;endif;endif
      xp=xd;yp=yd;ypr=yraw;rowidx=(1:numel(xp))';ord=(1:numel(xp))';if(strcmp(order_mode,'sort_x')&&!(isfield(S.data,'ordering_variable_id')&&!isempty(S.data.ordering_variable_id))),[xp,ord]=sort(xp);yp=yp(ord);ypr=ypr(ord);rowidx=rowidx(ord);endif
      kind=series_kind(S,graph_kind);auto_color=palette(mod(k-1,rows(palette))+1,:);st=resolve_style(S,V,kind,graph_lw,graph_ms,auto_color);
      hband=[];if(isfield(S.presentation,'band')&&!isempty(fieldnames(S.presentation.band))),[blo,bhi]=band_values(S,rowidx,1:numel(rowidx),target_y,level);hband=draw_band(ax,xp,blo,bhi,st,kind);endif
      hbase=[];
      if(strcmp(kind,'band'))
        draw_center=true;if(isfield(S.presentation.band,'draw_center')),draw_center=parse_bool(S.presentation.band.draw_center,true);endif;if(draw_center),hbase=draw_trace(ax,xp,yp,'line',st);endif
      elseif(strcmp(kind,'bar')),hbase=draw_bar(ax,xp,yp,S.presentation,st,S,rowidx,1:numel(rowidx),xdu,target_y,level);
      elseif(strcmp(kind,'step')),smode='post';if(isfield(S.presentation,'step_mode')&&!isempty(strtrim(S.presentation.step_mode))),smode=S.presentation.step_mode;endif;[xs,ys]=step_xy(xp,yp,smode);hbase=draw_trace(ax,xs,ys,'line',st);
      else [tx,ty]=source_trace(S,xp,yp,rowidx);hbase=draw_trace(ax,tx,ty,kind,st);endif
      if(has_error(S.presentation,'x_error')||has_error(S.presentation,'y_error'))
        [xl0,xu0]=error_x_endpoints(S,rowidx,1:numel(rowidx),xp,xdu);[yl0,yu0]=error_y_endpoints(S,rowidx,1:numel(rowidx),ypr,target_y,level,yp);draw_error_whiskers(ax,xp,yp,xl0,xu0,yl0,yu0,st);
      endif
      hleg=[];if(strcmp(kind,'band')&&!isempty(hband)),hleg=hband;elseif(!isempty(hbase)),hleg=hbase;elseif(!isempty(hband)),hleg=hband;endif
      if(!isempty(hleg)&&strcmp(legend_mode,'series')),handles(end+1)=hleg(1);labels{end+1}=series_label(S,target_y);endif %#ok<AGROW>
    endfor

    gxtxt_plot_set_axis_metadata(primary(pi),'x',P.x_name,P.x_meta.unit,xdu,xmeta_factor,0);
    if(!isempty(lidx)),gxtxt_plot_set_axis_metadata(primary(pi),'y',series(lidx(1)).name,series(lidx(1)).meta.unit,ydu,yfactor_meta,0);gxtxt_level_scale_metadata(primary(pi),ylevel);endif
    if(!isempty(ridx)),gxtxt_plot_set_axis_metadata(ax2,'y',series(ridx(1)).name,series(ridx(1)).meta.unit,y2du,y2factor_meta,0);gxtxt_level_scale_metadata(ax2,y2level);endif

    yl='auto';y2l='auto';if(pi==1),yl=presentation_value(cfg,graph,'y_label',gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'));y2l=presentation_value(cfg,graph,'y2_label',gxtxt_ini_get(cfg,['plot.' graph '.y2_label'],'auto'));endif
    yl=panel_axis_label(panel,'y_left',yl);y2l=panel_axis_label(panel,'y_right',y2l);
    if(is_auto(yl)),if(numel(lidx)==1),yl=axis_label(display_name(series(lidx(1)).name),ydu);else yl=axis_label('Y Left',ydu);endif;endif
    if(!isempty(lidx)),yl=display_axis_label(yl,series(lidx(1)).meta.unit,ydu);endif
    if(!isempty(ylevel_label)),yl=[yl ' (' ylevel_label ')'];endif
    axes(primary(pi));if(!isempty(lidx)),gxtxt_plot_text('ylabel',yl);endif
    if(!isempty(ridx)),if(is_auto(y2l)),if(numel(ridx)==1),y2l=axis_label(display_name(series(ridx(1)).name),y2du);else y2l=axis_label('Y Right',y2du);endif;endif;y2l=display_axis_label(y2l,series(ridx(1)).meta.unit,y2du);if(!isempty(y2level_label)),y2l=[y2l ' (' y2level_label ')'];endif;axes(ax2);gxtxt_plot_text('ylabel',y2l);endif
    ptitle=panel_title_text(panel);if(!isempty(ptitle)),axes(primary(pi));gxtxt_plot_text('title',ptitle);endif

    legend_series_handles{pi}=handles;legend_series_labels{pi}=labels;
    PV=V;PV.axes=panel.axes;PV.annotations=panel.annotations;draw_v2_annotations(PV,primary(pi),ax2);
  endfor
  try set(primary(1),'tag','gxtxt_primary_axis');catch;end_try_catch

  % Establish the one graph-wide visible X domain before applying explicit
  % graph/PlotSpec overrides.  The native single-panel right-Y label is now
  % present, so use its real tight inset (plus panel titles/X label) to reserve
  % enough stacked geometry before synchronizing overlays.
  pcfg=multipanel_layout_from_single_panel(primary,right_axes,pcfg0);
  pcfg=apply_plot_layout_overrides(pcfg,cfg,graph);
  gxtxt_plot_finalize_stacked(primary,pcfg);
  link_shared_x_axes(primary,right_axes)
  apply_core_panel_axes(primary,right_axes,pcfg,graph,panel_names,cfg);

  for pi=1:np
    panel=V.panels(pi);apply_panel_axes(panel,shared_x,primary(pi),right_axes{pi},core_axis_state,cfg,graph);
  endfor
  try gxtxt_plot_sync_overlay_axes(fig);catch;end_try_catch

  % Graph title is global; the X label appears only on the bottom panel.
  title_txt=presentation_value(cfg,graph,'title',gxtxt_ini_get(cfg,['plot.' graph '.title'],'auto'));xl=presentation_value(cfg,graph,'x_label',gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'));
  if(is_auto(title_txt)),title_txt=sprintf('Scientific dataset vs %s',display_name(P.x_name));endif
  if(V.title_present&&!is_auto(V.title)),title_txt=V.title;endif
  % Same label resolution as the working single-panel path.
  xl=v2_axis_label(V,'x',xl);if(is_auto(xl)),xl=axis_label(display_name(P.x_name),xdu);endif;xl=display_axis_label(xl,P.x_meta.unit,xdu);
  axes(primary(end));gxtxt_plot_text('xlabel',xl);
  % The bottom xlabel participates in the native axes inset only after it is
  % created.  One final geometry pass reserves that room without changing X.
  pcfg=multipanel_layout_from_single_panel(primary,right_axes,pcfg0);
  pcfg=apply_plot_layout_overrides(pcfg,cfg,graph);
  gxtxt_plot_finalize_stacked(primary,pcfg);
  link_shared_x_axes(primary,right_axes)
  try gxtxt_plot_sync_overlay_axes(fig);catch;end_try_catch
  % The global title is created only after external legend bands have their
  % final size. Creating it here would make an above-panel legend compete for
  % the same provisional band.

  % Computed annotations are graph data overlays; apply them independently to
  % each panel without changing panel membership or series identity.
  annotations={};if(primary_matches_series(cfg,P)),annotations=gxtxt_data_annotations_from_runtime(cfg,'primary');endif
  if(!isempty(annotations))
    for pi=1:np
      idxs=panel_series_indices(series,V.panels(pi).series_ids);lidx=idxs(strcmp({series(idxs).axis},'left'));ridx=idxs(strcmp({series(idxs).axis},'right'));
      if(isempty(idxs)),continue;endif
      ctx=struct();ctx.x_variable=P.x_name;ctx.x_display_unit=xdu;ctx.y_left_variables={};ctx.y_left_display_unit='';ctx.y_right_variables={};ctx.y_right_display_unit='';
      if(!isempty(lidx)),ctx.y_left_variables={series(lidx).name};endif;if(!isempty(ridx)),ctx.y_right_variables={series(ridx).name};endif
      gxtxt_plot_data_annotations_2d(primary(pi),right_axes{pi},annotations,ctx);
    endfor
  endif

  % Measure legends only after the content layout exists. The common GNUplot
  % legend helper may temporarily shrink one axes for an external placement;
  % that provisional mutation is discarded below by rebuilding every panel
  % from layout_base, which is immutable for this render.
  layout_base=pcfg;
  [legend_placement,legend_alignment,legend_margin_px]=effective_legend_layout(cfg,graph,pcfg);
  if(!strcmp(legend_mode,'none'))
    for pi=1:np
      labels=legend_series_labels{pi};handles=legend_series_handles{pi};
      if(isempty(labels)),continue;endif
      axes(primary(pi));cfg_legend=panel_legend_runtime_cfg(cfg,graph,primary(pi));
      legend_handles{pi}=gxtxt_plot_legend(handles,labels,pcfg,graph,cfg_legend);
    endfor
  endif

  % External legends own a real layout band. Reserve that band from the
  % immutable content geometry, restore all panel rectangles, then place each
  % legend against its owning panel. Inside/manual legends never consume an
  % external band and are defensively clamped only when they fit.
  pcfg=reserve_external_legend_layout(layout_base,legend_handles,legend_placement,legend_margin_px);
  gxtxt_plot_finalize_stacked(primary,pcfg);
  link_shared_x_axes(primary,right_axes)
  try gxtxt_plot_sync_overlay_axes(fig);catch;end_try_catch
  apply_panel_ylabel_spacing(primary,right_axes,pcfg,cfg,graph);
  position_panel_legends(legend_handles,primary,legend_placement,legend_alignment,legend_margin_px,layout_base,pcfg);
  draw_global_title(fig,title_txt,primary(1),pcfg,legend_handles,legend_placement);

  % Same pre-export contract as the single-panel renderer, applied per panel.
  % Every axes() call above (panel titles, labels, legends) raises its opaque
  % primary over the transparent right-Y overlay, so GNUplot then draws the
  % primary background on top and hides the overlay series. Raise each overlay
  % back, then restore that panel's legend above it. gxtxt_plot_sync_overlay_axes()
  % and gxtxt_plot_finalize_output() only set properties and never reorder, so
  % this ordering survives until print().
  for pi=1:np
    if(isempty(right_axes{pi})),continue;endif
    try axes(right_axes{pi});catch;end_try_catch
    lh=legend_handles{pi};
    if(!isempty(lh))
      try if(strcmpi(get(lh,'type'),'axes')),axes(lh);endif;catch;end_try_catch
    endif
  endfor

  create_shared_x_selection_frame(fig,primary);
  target=fullfile(outdir,file_name);gxtxt_print_png_atomic(fig,target,pcfg.dpi);pd_print_extra(fig,target,V);
  write_shared_x_region_metadata(target,primary(end),P,xdu,xmeta_factor);
  pd_region_diagnostic_post(target,graph);close(fig);
  fprintf('[plot.dataset] rendered multi-panel 2D graph=%s file=%s panels=%d series=%d plotspec_v2=1 shared_x=1\n',graph,target,np,n);
endfunction

function s=panel_title_text(panel)
  s='';if(!isfield(panel,'title')),return;endif
  q=strtrim(panel.title);if(isempty(q)),return;endif
  if(strcmpi(q,'auto')),s=panel.id;else s=panel.title;endif
endfunction

function draw_global_title(fig,s,topax,pcfg,legend_handles,legend_placement)
% Use axes-normalized text because GNUplot anchors annotation text boxes at
% their left edge even when horizontalalignment is center. The offset is
% measured from the finalized top-panel rectangle and moves above an external
% top-panel legend when one exists.
  if(isempty(strtrim(s))),return;endif
  try
    old=findobj(topax,'tag','GXTXT_GLOBAL_TITLE');if(!isempty(old)),delete(old);endif
    ap=axis_position_norm(topax);if(isempty(ap)),return;endif
    ti=axis_tight_inset_norm(topax);clear=title_band_norm(pcfg);if(!isempty(ti)),clear=max(clear,ti(4));endif
    pady=max(0.006,8/max(240,pcfg.height_px));yf=ap(2)+ap(4)+clear+pady;
    if(strcmp(legend_placement,'above')&&!isempty(legend_handles)&&!isempty(legend_handles{1}))
      lp=object_position_norm(legend_handles{1});
      if(!isempty(lp)),yf=max(yf,lp(2)+lp(4)+pady);endif
    endif
    yn=(yf-ap(2))/max(0.01,ap(4));
    fs=pcfg.title_font_size;if(!isfinite(fs)||fs<=0),fs=max(8,pcfg.font_size*1.10);endif
    h=text(topax,0.5,yn,s);
    set(h,'units','normalized','position',[0.5 yn 0],'rotation',0, ...
      'horizontalalignment','center','verticalalignment','bottom','clipping','off', ...
      'fontweight','bold','fontunits','points','fontsize',fs,'interpreter','none', ...
      'tag','GXTXT_GLOBAL_TITLE');
  catch
    axes(topax);old='';try old=get(get(topax,'title'),'string');catch;end_try_catch
    if(iscell(old)),old=strjoin(old,' ');endif
    if(isempty(old)),gxtxt_plot_text('title',s);else gxtxt_plot_text('title',sprintf('%s\n%s',s,old));endif
  end_try_catch
endfunction

function out=panel_legend_runtime_cfg(cfg,graph,ax)
  out=cfg;
  if(isempty(cfg)||!isstruct(cfg)||isempty(strtrim(graph))),return;endif
  prefix=regexprep(['legend.' graph '.'],'[^A-Za-z0-9_]','_');
  ek=[prefix 'enabled'];pk=[prefix 'placement'];mk=[prefix 'mode'];xk=[prefix 'manual_x'];yk=[prefix 'manual_y'];
  if(!isfield(out,ek)),return;endif
  enabled=lower(strtrim(out.(ek)));if(!any(strcmp(enabled,{'1','true','yes','on'}))),return;endif
  placement='';if(isfield(out,pk)),placement=lower(strtrim(out.(pk)));elseif(isfield(out,mk)),placement=lower(strtrim(out.(mk)));endif
  if(!strcmp(placement,'manual')),return;endif
  mx=0.75;my=0.85;if(isfield(out,xk)),v=str2double(out.(xk));if(isfinite(v)),mx=min(1,max(0,v));endif;endif
  if(isfield(out,yk)),v=str2double(out.(yk));if(isfinite(v)),my=min(1,max(0,v));endif;endif
  try
    ap=get(ax,'position');
    % CORE manual legend coordinates are figure-normalized.  Multi-panel
    % rendering interprets the same pair as a panel-local normalized position.
    out.(xk)=num2str(ap(1)+mx*ap(3),17);
    out.(yk)=num2str(ap(2)+my*ap(4),17);
  catch
  end_try_catch
endfunction

function idxs=panel_series_indices(series,ids)
  idxs=[];for i=1:numel(ids),j=find(strcmp({series.series_id},ids{i}),1);if(!isempty(j)),idxs(end+1)=j;endif;endfor
endfunction

function p=multipanel_layout_from_single_panel(primary,right_axes,p)
% Derive the stacked geometry from what the panels actually need.
% p must be the pristine gxtxt_plot_config() values: the result is recomputed
% from them on every pass, so successive passes converge on one layout.
%
% The configured stacked margins are the FALLBACK used when a band cannot be
% measured, not a lower bound. Used as a floor they simply reproduced the
% 10/4/10/10/2.5 defaults on every plot, because the measured content is
% normally smaller: the layout looked automatic but was static.
% Single-panel rendering and CORE defaults are untouched.
  if(numel(primary)<2),return;endif
  try drawnow();catch;end_try_catch
  base_left=p.stacked_margin_left_pct/100;base_right=p.stacked_margin_right_pct/100;
  base_top=p.stacked_margin_top_pct/100;base_bottom=p.stacked_margin_bottom_pct/100;base_gap=p.stacked_gap_pct/100;
  padx=max(0.004,8/max(320,p.width_px));pady=max(0.006,8/max(240,p.height_px));
  n=numel(primary);

  % Measured content, with an explicit "was it measurable" flag per band.
  tick_left=0;have_left=false;
  right_inset=0;have_right=false;
  bottom_inset=0;have_bottom=false;
  top_inset=0;have_top=false;
  gap_inset=0;have_gap=false;
  for k=1:n
    ti=axis_tight_inset_norm(primary(k));
    if(!isempty(ti))
      tick_left=max(tick_left,ti(1));have_left=true;
      if(k==1),top_inset=ti(4);have_top=true;else gap_inset=max(gap_inset,ti(4));have_gap=true;endif
      if(k==n),bottom_inset=ti(2);have_bottom=true;endif
    endif
    if(k<=numel(right_axes)&&!isempty(right_axes{k}))
      tr=axis_tight_inset_norm(right_axes{k});
      if(!isempty(tr)),right_inset=max(right_inset,tr(3));have_right=true;endif
    endif
  endfor

  % gxtxt_plot_align_ylabel() replaces the native Y label with a free text
  % object, which never appears in tightinset, so reserve its band explicitly.
  % With alignment off the native label is still in place and already counted
  % in tightinset, and reserving it again would double-count it.
  aligned=isfield(p,'stacked_align_ylabels')&&p.stacked_align_ylabels;
  lw=0;if(aligned),lw=label_band_norm(p);endif
  % Right labels are also converted to deterministic free text after the final
  % geometry pass. Reserve their physical band explicitly because GNUplot does
  % not reliably include an overlay ylabel in tightinset.
  rw=0;if(aligned&&have_right),rw=label_band_norm(p);endif

  % Hugging the measured content exactly is as wrong as the old fixed 10%:
  % it left the X label touching the page edge. Take part of the way back
  % towards the configured margin, which therefore acts as the generosity
  % anchor rather than as a floor, and stays meaningful in Graphics.
  tb=title_band_norm(p);
  % Reserve the tick column, the rotated label and a clear gap on both sides
  % of it, so the label can never be drawn on top of the tick numbers.
  left_need=base_left;if(have_left),left_need=soften(tick_left+lw+2*padx,base_left);endif
  right_need=base_right;if(have_right),right_need=soften(right_inset+rw+2*padx,base_right);endif
  % Deterministic minima, independent of tightinset: the bottom band must hold
  % a tick line plus the X label line, the top band a panel title plus the
  % global title line, and the gap one title line with air above and below.
  % These hold even when a band cannot be measured at all.
  bottom_need=base_bottom;if(have_bottom),bottom_need=soften(bottom_inset+pady,base_bottom);endif
  bottom_need=max(bottom_need,2*tb+pady);
  top_need=base_top;if(have_top),top_need=soften(top_inset+tb+pady,base_top);endif
  top_need=max(top_need,2*tb+pady);
  gap_need=base_gap;if(have_gap),gap_need=max(base_gap,gap_inset+2*pady);endif
  gap_need=max(gap_need,tb+2*pady);

  p.stacked_margin_left_pct=100*min(0.30,max(0.012,left_need));
  p.stacked_margin_right_pct=100*min(0.30,max(0.012,right_need));
  p.stacked_margin_top_pct=100*min(0.30,max(0.012,top_need));
  p.stacked_margin_bottom_pct=100*min(0.30,max(0.012,bottom_need));
  p.stacked_gap_pct=100*min(0.30,max(0.012,gap_need));

  % Place every panel Y label just outside the widest tick column rather than
  % at a fixed fraction of the axes width: panels stay aligned with each other,
  % but the distance is measured instead of constant.
  w=1-p.stacked_margin_left_pct/100-p.stacked_margin_right_pct/100;
  if(aligned&&w>0.20)
    p.stacked_ylabel_x=-min(0.30,(tick_left+padx+lw/2)/w);
    p.stacked_ylabel_right_x=1+min(0.30,(right_inset+padx+rw/2)/w);
  endif
endfunction

function p=apply_plot_layout_overrides(p,cfg,graph)
% Per-plot manual layout from the Plots tab. The automatic layout above stays
% the default; when the user turns Automatic off for this plot, the stored
% percentages win. Deliberately bypasses axis.<graph>.enabled, which governs
% the Axes dialog and not the layout controls.
  prefix=['axis.' graph '.'];
  if(!cfg_has_key(cfg,[prefix 'layout_auto'])),return;endif
  a=str2double(gxtxt_ini_get(cfg,[prefix 'layout_auto'],'1'));
  if(!isfinite(a)||a~=0),return;endif
  p=layout_pct(p,'stacked_margin_left_pct',cfg,[prefix 'layout_margin_left']);
  p=layout_pct(p,'stacked_margin_right_pct',cfg,[prefix 'layout_margin_right']);
  p=layout_pct(p,'stacked_margin_top_pct',cfg,[prefix 'layout_margin_top']);
  p=layout_pct(p,'stacked_margin_bottom_pct',cfg,[prefix 'layout_margin_bottom']);
  p=layout_pct(p,'stacked_gap_pct',cfg,[prefix 'layout_gap']);
  d=str2double(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_dist'],''));
  allow_negative=strcmp(strtrim(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_allow_negative'],'0')),'1');
  if(isfinite(d)&&d<=30&&(d>=0||(allow_negative&&d>=-30)))
    p.stacked_ylabel_x=-d/100;
    p.stacked_ylabel_right_x=1+d/100;
  endif
endfunction

function p=layout_pct(p,field,cfg,key)
  v=str2double(gxtxt_ini_get(cfg,key,''));
  if(isfinite(v)&&v>=0&&v<=30),p.(field)=v;endif
endfunction

function v=soften(need,configured)
% Measured need, moved part of the way towards the configured margin when the
% configured one is larger. 0 would hug the content, 1 would restore the old
% static default.
  v=need;if(isfinite(configured)&&configured>need),v=need+0.15*(configured-need);endif
endfunction

function v=label_band_norm(p)
% Horizontal room a rotated axis label needs, as a figure fraction.
  fs=p.axis_label_font_size;if(!isfinite(fs)||fs<=0),fs=p.font_size;endif
  if(!isfinite(fs)||fs<=0),fs=10;endif
  dpi=p.dpi;if(!isfinite(dpi)||dpi<=0),dpi=200;endif
  v=min(0.08,max(0.008,1.35*(fs*dpi/72)/max(320,p.width_px)));
endfunction

function v=title_band_norm(p)
% Vertical room one title line needs, as a figure fraction.
  fs=p.title_font_size;if(!isfinite(fs)||fs<=0),fs=p.font_size*1.10;endif
  if(!isfinite(fs)||fs<=0),fs=12;endif
  dpi=p.dpi;if(!isfinite(dpi)||dpi<=0),dpi=200;endif
  v=min(0.09,max(0.028,1.7*(fs*dpi/72)/max(240,p.height_px)));
endfunction

function apply_single_panel_layout_overrides(ax1,ax2,cfg,graph)
% Manual layout is an absolute rectangle derived only from persisted values.
% Automatic single-panel geometry stays on the established CORE path.
  prefix=['axis.' graph '.'];
  if(!cfg_has_key(cfg,[prefix 'layout_auto'])),return;endif
  a=str2double(gxtxt_ini_get(cfg,[prefix 'layout_auto'],'1'));if(!isfinite(a)||a~=0),return;endif
  vals=zeros(1,4);keys={'layout_margin_left','layout_margin_bottom','layout_margin_right','layout_margin_top'};
  defaults=[13 11 9.5 7.5];
  for k=1:4
    vals(k)=str2double(gxtxt_ini_get(cfg,[prefix keys{k}],num2str(defaults(k))));
    if(!isfinite(vals(k))),vals(k)=defaults(k);endif
    vals(k)=min(30,max(0,vals(k)))/100;
  endfor
  pos=[vals(1) vals(2) 1-vals(1)-vals(3) 1-vals(2)-vals(4)];
  if(pos(3)>0.20&&pos(4)>0.10)
    try set(ax1,'units','normalized','position',pos);catch;end_try_catch
    if(!isempty(ax2)),try set(ax2,'units','normalized','position',pos);catch;end_try_catch;endif
  endif
  d=str2double(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_dist'],''));
  allow_negative=strcmp(strtrim(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_allow_negative'],'0')),'1');
  if(isfinite(d)&&d<=30&&(d>=0||(allow_negative&&d>=-30)))
    align_ylabel_side(ax1,-d/100,'GXTXT_PD_LEFT_YLABEL');
    if(!isempty(ax2)),align_ylabel_side(ax2,1+d/100,'GXTXT_PD_RIGHT_YLABEL');endif
  endif
endfunction

function auto_place_single_labels(ax1,ax2,cfg,graph,p)
% Work from the effective plot box after aspect and external legend layout.
% Saved Y-label offsets and manual layout retain their own authority.
  prefix=['axis.' graph '.'];
  manual=str2double(gxtxt_ini_get(cfg,[prefix 'ylabel_x'],''));
  layout_manual=strcmp(strtrim(gxtxt_ini_get(cfg,[prefix 'layout_auto'],'1')),'0');
  distance=str2double(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_dist'],''));
  if(isfinite(manual)||(layout_manual&&isfinite(distance))),return;endif
  try
    mode=get(ax1,'plotboxaspectratiomode');
    if(!strcmpi(mode,'manual')),return;endif
    ratio=get(ax1,'plotboxaspectratio');ap=axis_position_norm(ax1);
    if(isempty(ap)||numel(ratio)<2||any(!isfinite(ratio(1:2)))||any(ratio(1:2)<=0)),return;endif
    width=max(1,p.width_px*ap(3));height=max(1,p.height_px*ap(4));
    wanted=ratio(1)/ratio(2);available=width/height;
    if(available>wanted),boxw=height*wanted;boxh=height;else boxw=width;boxh=width/wanted;endif
    left=(width-boxw)/(2*width);right=1-left;bottom=(height-boxh)/(2*height);
    fs=max(8,p.axis_label_font_size);dpi=max(72,p.dpi);fontpx=fs*dpi/72;
    lefttick=largest_tick_label(ax1,'y');
    leftx=left-(max(8,lefttick*0.55*fontpx)+1.1*fontpx)/width;
    leftx=max(-0.30,leftx);
    align_ylabel_side(ax1,leftx,'GXTXT_PD_LEFT_YLABEL');
    if(!isempty(ax2))
      righttick=largest_tick_label(ax2,'y');
      rightx=right+(max(8,righttick*0.55*fontpx)+1.1*fontpx)/width;
      align_ylabel_side(ax2,min(1.30,rightx),'GXTXT_PD_RIGHT_YLABEL');
    endif
    % Leave the native X label attached to the effective bottom axis.  GNUplot
    % recalculates its baseline during print; forcing a normalized position
    % here can make it disappear from an equal-aspect export.
  catch err
    warning('GXTXT:AutomaticLabels','Automatic plot-box label placement failed: %s',err.message);
  end_try_catch
endfunction

function n=largest_tick_label(ax,which)
  n=0;
  try
    labels=get(ax,[which 'ticklabel']);
    if(ischar(labels)),n=columns(labels);
    elseif(iscell(labels)),n=max(cellfun(@numel,labels));endif
  catch
  end_try_catch
endfunction

function [placement,alignment,margin_px]=effective_legend_layout(cfg,graph,p)
% Mirror the public legend override inputs needed only for panel geometry.
  placement=lower(strtrim(p.legend_mode));alignment=lower(strtrim(p.legend_alignment));margin_px=p.legend_external_margin_px;
  prefix=regexprep(['legend.' graph '.'],'[^A-Za-z0-9_]','_');
  ek=[prefix 'enabled'];enabled=false;
  if(isstruct(cfg)&&isfield(cfg,ek)),enabled=any(strcmp(lower(strtrim(cfg.(ek))),{'1','true','yes','on'}));endif
  if(enabled)
    pk=[prefix 'placement'];mk=[prefix 'mode'];ak=[prefix 'alignment'];xk=[prefix 'external_margin_px'];
    if(isfield(cfg,pk)&&!isempty(strtrim(cfg.(pk)))),placement=lower(strtrim(cfg.(pk)));
    elseif(isfield(cfg,mk)&&!isempty(strtrim(cfg.(mk)))),placement=lower(strtrim(cfg.(mk)));endif
    if(isfield(cfg,ak)&&!isempty(strtrim(cfg.(ak)))),alignment=lower(strtrim(cfg.(ak)));endif
    if(isfield(cfg,xk)),v=str2double(cfg.(xk));if(isfinite(v)&&v>=0),margin_px=v;endif;endif
  endif
  if(strcmp(placement,'top')),placement='above';elseif(strcmp(placement,'bottom')),placement='below';endif
  if(!any(strcmp(placement,{'inside','above','below','left','right','manual','none'}))),placement='inside';endif
  if(!any(strcmp(alignment,{'start','center','end'}))),alignment='center';endif
  if(!isfinite(margin_px)||margin_px<0),margin_px=12;endif
endfunction

function p=reserve_external_legend_layout(base,handles,placement,margin_px)
% External placement consumes a distinct band. Values are added to the current
% automatic/manual content margins; they never reuse a previously calculated
% axes position, so full render and rerender are idempotent.
  p=base;if(!any(strcmp(placement,{'above','below','left','right'}))),return;endif
  maxw=0;maxh=0;topw=0;toph=0;bottomw=0;bottomh=0;have=false;n=numel(handles);
  for k=1:n
    q=object_position_norm(handles{k});if(isempty(q)),continue;endif
    have=true;maxw=max(maxw,q(3));maxh=max(maxh,q(4));
    if(k==1),topw=q(3);toph=q(4);endif
    if(k==n),bottomw=q(3);bottomh=q(4);endif
  endfor
  if(!have),return;endif
  mx=max(0,margin_px)/max(320,base.width_px);my=max(0,margin_px)/max(240,base.height_px);
  if(strcmp(placement,'above'))
    if(toph>0),p.stacked_margin_top_pct=min(45,base.stacked_margin_top_pct+100*(toph+my));endif
    if(n>1&&maxh>0),p.stacked_gap_pct=min(45,base.stacked_gap_pct+100*(maxh+my));endif
  elseif(strcmp(placement,'below'))
    if(bottomh>0),p.stacked_margin_bottom_pct=min(45,base.stacked_margin_bottom_pct+100*(bottomh+my));endif
    if(n>1&&maxh>0),p.stacked_gap_pct=min(45,base.stacked_gap_pct+100*(maxh+my));endif
  elseif(strcmp(placement,'left'))
    p.stacked_margin_left_pct=min(45,base.stacked_margin_left_pct+100*(maxw+mx));
  elseif(strcmp(placement,'right'))
    p.stacked_margin_right_pct=min(45,base.stacked_margin_right_pct+100*(maxw+mx));
  endif
endfunction

function position_panel_legends(handles,axs,placement,alignment,margin_px,base,p)
% External legends are positioned in their reserved band. Inside/manual
% legends retain the common renderer position and receive only an ownership
% guard, never an external-to-inside fallback.
  if(isempty(handles)),return;endif
  mx=max(0,margin_px)/max(320,p.width_px);my=max(0,margin_px)/max(240,p.height_px);
  for k=1:numel(handles)
    lh=handles{k};if(isempty(lh)||k>numel(axs)),continue;endif
    if(!any(strcmp(placement,{'above','below','left','right'})))
      clamp_legend_to_panel(lh,axs(k));
      continue;
    endif
    lp=object_position_norm(lh);ap=axis_position_norm(axs(k));if(isempty(lp)||isempty(ap)),continue;endif
    if(strcmp(placement,'above'))
      ti=axis_tight_inset_norm(axs(k));clear=title_band_norm(p);if(!isempty(ti)),clear=max(clear,ti(4));endif
      x=aligned_start(ap(1),ap(3),lp(3),alignment);y=ap(2)+ap(4)+clear+my;
    elseif(strcmp(placement,'below'))
      ti=axis_tight_inset_norm(axs(k));clear=title_band_norm(p);if(!isempty(ti)),clear=max(clear,ti(2));endif
      x=aligned_start(ap(1),ap(3),lp(3),alignment);y=ap(2)-clear-my-lp(4);
    elseif(strcmp(placement,'left'))
      x=ap(1)-base.stacked_margin_left_pct/100-lp(3);y=aligned_start(ap(2),ap(4),lp(4),alignment);
    else
      x=ap(1)+ap(3)+base.stacked_margin_right_pct/100;y=aligned_start(ap(2),ap(4),lp(4),alignment);
    endif
    x=min(max(0.004,x),0.996-lp(3));y=min(max(0.004,y),0.996-lp(4));
    set_object_position_norm(lh,[x y lp(3) lp(4)]);
  endfor
endfunction

function v=aligned_start(start,span,item,alignment)
  if(strcmp(alignment,'start')),v=start;elseif(strcmp(alignment,'end')),v=start+span-item;else v=start+(span-item)/2;endif
endfunction

function apply_panel_ylabel_spacing(primary,right_axes,p,cfg,graph)
% Freeze both Left and Right labels as normalized free text after the final
% panel rectangles exist. This avoids toolkit autoposition drift and makes the
% one spacing control symmetric across both scientific Y sides.
  lx=p.stacked_ylabel_x;rx=1-lx;
  if(isfield(p,'stacked_ylabel_right_x')),rx=p.stacked_ylabel_right_x;endif
  prefix=['axis.' graph '.'];
  explicit=str2double(gxtxt_ini_get(cfg,[prefix 'ylabel_x'],''));
  distance=str2double(gxtxt_ini_get(cfg,[prefix 'layout_ylabel_dist'],''));
  manual_layout=strcmp(strtrim(gxtxt_ini_get(cfg,[prefix 'layout_auto'],'1')),'0')&&isfinite(distance);
  if(!manual_layout&&!isfinite(explicit)&&!isempty(primary))
    ap=axis_position_norm(primary(1));
    if(!isempty(ap)&&ap(3)>0)
      width=max(1,ap(3)*p.width_px);
      fs=max(8,p.axis_label_font_size);fontpx=fs*max(72,p.dpi)/72;
      ticks=0;rightticks=0;
      for k=1:numel(primary)
        ticks=max(ticks,largest_tick_label(primary(k),'y'));
        if(k<=numel(right_axes)&&!isempty(right_axes{k})),rightticks=max(rightticks,largest_tick_label(right_axes{k},'y'));endif
      endfor
      gap=max(2.2*fontpx,14);
      lx=-max(0.03,(max(8,0.6*ticks*fontpx)+gap)/width);
      lx=max(lx,(0.009-ap(1))/ap(3));
      if(rightticks>0)
        rx=1+max(0.03,(max(8,0.6*rightticks*fontpx)+gap)/width);
        rx=min(rx,(0.991-ap(1))/ap(3));
      endif
    endif
  endif
  for k=1:numel(primary)
    if(!isfinite(explicit)),align_ylabel_side(primary(k),lx,'GXTXT_PD_LEFT_YLABEL');endif
    if(k<=numel(right_axes)&&!isempty(right_axes{k})),align_ylabel_side(right_axes{k},rx,'GXTXT_PD_RIGHT_YLABEL');endif
  endfor
endfunction

function align_ylabel_side(ax,x,tag)
  if(isempty(ax)||!isfinite(x)),return;endif
  try
    yh=get(ax,'ylabel');txt=get(yh,'string');old=findobj(ax,'tag',tag);
    if(isempty(txt)&&!isempty(old)),txt=get(old(1),'string');endif
    core=findobj(ax,'tag','GXTXT_ALIGNED_YLABEL');
    if(isempty(txt)&&!isempty(core)),txt=get(core(1),'string');endif
    if(isempty(txt)),return;endif
    fs=get(yh,'fontsize');fn=get(yh,'fontname');fw=get(yh,'fontweight');fa=get(yh,'fontangle');c=get(yh,'color');
    try interp=get(yh,'interpreter');catch;interp='none';end_try_catch
    if(!isempty(old)),delete(old);endif;if(!isempty(core)),delete(core);endif;set(yh,'string','');
    h=text(ax,0,0,txt);set(h,'units','normalized','position',[x 0.5 0],'rotation',90, ...
      'horizontalalignment','center','verticalalignment','middle','clipping','off', ...
      'fontsize',fs,'fontname',fn,'fontweight',fw,'fontangle',fa,'color',c, ...
      'interpreter',interp,'tag',tag);
  catch err
    warning('plot.dataset: Y-label spacing was not applied: %s',err.message);
  end_try_catch
endfunction

function clamp_legend_to_panel(lh,ax)
% Inside/manual ownership guard. External placement is handled by a reserved
% band and never reaches this function.
  if(isempty(lh)||isempty(ax)),return;endif
  try
    lp=object_position_norm(lh);ap=axis_position_norm(ax);if(isempty(lp)||isempty(ap)),return;endif
    pad=0.004;
    if(lp(3)<ap(3)-2*pad&&lp(4)<ap(4)-2*pad)
      x=min(max(lp(1),ap(1)+pad),ap(1)+ap(3)-lp(3)-pad);
      y=min(max(lp(2),ap(2)+pad),ap(2)+ap(4)-lp(4)-pad);
      set_object_position_norm(lh,[x y lp(3) lp(4)]);
    endif
  catch
  end_try_catch
endfunction

function p=axis_position_norm(ax)
  p=[];if(isempty(ax)),return;endif
  oldu='';try oldu=get(ax,'units');set(ax,'units','normalized');p=get(ax,'position');set(ax,'units',oldu);catch;if(!isempty(oldu)),try set(ax,'units',oldu);catch;end_try_catch;endif;end_try_catch
endfunction

function p=object_position_norm(h)
  p=[];if(isempty(h)),return;endif
  oldu='';try oldu=get(h,'units');set(h,'units','normalized');p=get(h,'position');set(h,'units',oldu);p=p(:)';if(numel(p)~=4||!all(isfinite(p))),p=[];endif;catch;if(!isempty(oldu)),try set(h,'units',oldu);catch;end_try_catch;endif;end_try_catch
endfunction

function set_object_position_norm(h,p)
  oldu='';try oldu=get(h,'units');set(h,'units','normalized');set(h,'position',p);set(h,'units',oldu);catch;if(!isempty(oldu)),try set(h,'units',oldu);catch;end_try_catch;endif;end_try_catch
endfunction

function ti=axis_tight_inset_norm(ax)
  ti=[];if(isempty(ax)),return;endif
  oldu='';
  try
    oldu=get(ax,'units');set(ax,'units','normalized');q=get(ax,'tightinset');set(ax,'units',oldu);
    q=q(:)';if(numel(q)==4&&all(isfinite(q))&&all(q>=0)),ti=q;endif
  catch
    if(!isempty(oldu)),try set(ax,'units',oldu);catch;end_try_catch;endif
  end_try_catch
endfunction

function link_shared_x_axes(primary,right_axes)
% Single-panel dual-Y keeps Left/Right in one linked-X group.  A shared-X stack
% must do the same for every panel: linking only the primary axes would replace
% the per-panel links and leave right overlays with stale X limits.
  axs=primary(:)';
  for k=1:numel(right_axes),if(!isempty(right_axes{k})),axs(end+1)=right_axes{k};endif;endfor
  if(numel(axs)>1),try linkaxes(axs,'x');catch;end_try_catch;endif
endfunction

function apply_core_panel_axes(primary,right_axes,pcfg,graph,panel_names,cfg)
% Reuse the existing CORE per-panel axis surface, including panel-specific Y2.
% Since GX-TXT 0.9.7.50 gxtxt_plot_axis_overrides() resolves
% gxtxt_panel_<n>_overlay_yaxis directly, so the historical workaround that
% exposed one panel overlay at a time under the single-overlay tag is removed:
% keeping it would hide every panel from the new resolver.
  for pi=1:numel(primary)
    try gxtxt_plot_apply_graph_axes(primary(pi),pcfg,graph,panel_names(pi),cfg);catch err;warning('plot.dataset: panel axis override failed for %s: %s',panel_names{pi},err.message);end_try_catch
  endfor
endfunction

function m=effective_panel_axis_unit(panel,name,fallback,core_declared,core_enabled)
  if(core_declared&&strcmp(name,'y_left'))
    if(core_enabled),m=fallback;else m='auto';endif
    return;
  endif
  m=fallback;if(isfield(panel.axes,name)),a=panel.axes.(name);if(isfield(a,'display_unit')),q=strtrim(a.display_unit);if(!isempty(q)),m=q;endif;endif;endif
endfunction

function s=panel_axis_label(panel,name,fallback)
  s=fallback;
  if(isfield(panel.axes,name))
    a=panel.axes.(name);
    if(isfield(a,'label')&&!is_auto(a.label)),s=a.label;endif
  endif
endfunction

function apply_panel_axes(panel,shared_x,ax1,ax2,core_declared,cfg,graph)
% Shared X keeps the historical whole-axis authority. Panel Y Left/Y Right
% resolve authority per bound: apply_core_panel_axes() has already applied
% every bound the CORE Axes dialog declares for this panel, so PlotSpec fills
% only what CORE left automatic. Suppressing the whole axis instead left a
% panel autoscaled whenever CORE declared any unrelated axis field.
  apply_axis_one(ax1,shared_x,'x',core_declared);
  if(isfield(panel.axes,'y_left'))
    [skip_min,skip_max]=core_axis_bounds_present(cfg,graph,panel.id,'y');
    apply_axis_one_fill(ax1,panel.axes.y_left,'y',skip_min,skip_max);
  endif
  if(!isempty(ax2))
    apply_axis_one(ax2,shared_x,'x',core_declared);
    if(isfield(panel.axes,'y_right'))
      [skip_min,skip_max]=core_axis_bounds_present(cfg,graph,panel.id,'y2');
      apply_axis_one_fill(ax2,panel.axes.y_right,'y',skip_min,skip_max);
    endif
  endif
endfunction

function create_shared_x_selection_frame(fig,axs)
  if(numel(axs)<2),return;endif
  try
    left=Inf;bottom=Inf;right=-Inf;top=-Inf;
    for k=1:numel(axs)
      old=get(axs(k),'units');set(axs(k),'units','normalized');p=get(axs(k),'position');set(axs(k),'units',old);
      left=min(left,p(1));bottom=min(bottom,p(2));right=max(right,p(1)+p(3));top=max(top,p(2)+p(4));
    endfor
    h=axes('parent',fig,'units','normalized','position',[left bottom right-left top-bottom],'color','none','xlim',[0 1],'ylim',[0 1], ...
      'xtick',[],'ytick',[],'box','off','visible','off','tag','gxtxt_shared_x_selection_frame','handlevisibility','off');
    try set(h,'linewidth',0.5);catch;end_try_catch
  catch
  end_try_catch
endfunction

function write_shared_x_region_metadata(target,ax,P,xdu,xfactor)
% Keep the real multi-panel topology in the primary metadata sidecar. The
% established shared-X selection uses a separate synthetic X-only geometry.
  try
    sf=figure('visible','off');sa=axes('parent',sf);set(sa,'tag','gxtxt_primary_axis','box','on');
    set(sa,'xlim',get(ax,'xlim'),'xscale',get(ax,'xscale'),'xdir',get(ax,'xdir'),'ylim',[0 1]);
    gxtxt_plot_set_axis_metadata(sa,'x',P.x_name,P.x_meta.unit,xdu,xfactor,0);
    [d,n,e]=fileparts(target);
    gxtxt_plot_write_metadata(sf,fullfile(d,[n '.xrange' e]),target);close(sf);
  catch err
    try close(sf);catch;end_try_catch
    warning('plot.dataset: shared-X Region Selection metadata was not written: %s',err.message);
  end_try_catch
endfunction

function pd_region_selection_surface(ax1,ax2,legend_handle,fig)
  % Use only the existing CORE topology contract: one primary data axes and
  % an optional tagged Y-right overlay. The legend helper is never data axes.
  try set(ax1,'tag','gxtxt_primary_axis','box','on');catch;end_try_catch
  if(!isempty(ax2)),try set(ax2,'tag','gxtxt_overlay_yaxis','box','off');catch;end_try_catch;try gxtxt_plot_sync_overlay_axes(fig);catch;end_try_catch;endif
  if(!isempty(legend_handle)),try if(strcmpi(get(legend_handle,'type'),'axes')),set(legend_handle,'tag','gxtxt_legend_helper');endif;catch;end_try_catch;endif
endfunction

function tf=primary_matches_series(cfg,P)
  tf=false;pid=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));if(isempty(pid)),return;endif
  for k=1:numel(P.series),if(strcmp(P.series(k).dataset_id,pid)),tf=true;return;endif;endfor
endfunction

function tf=pd_region_diag_enabled(),q=lower(strtrim(getenv('GXTXT_PLOT_DATASET_REGION_DIAGNOSTIC')));tf=any(strcmp(q,{'1','true','yes','on'}));endfunction
function pd_region_diagnostic_pre(fig,graph,P)
  if(!pd_region_diag_enabled()),return;endif
  fprintf('[plot.dataset][region-diagnostic] phase=pre_export graph_id=%s variant_id=%s series=%d\n',graph,P.variant_id,numel(P.series));
  axs=[];try axs=findall(fig,'type','axes');catch;end_try_catch
  fprintf('[plot.dataset][region-diagnostic] candidate_axes=%d\n',numel(axs));
  for k=1:numel(axs)
    tag='';pos=[NaN NaN NaN NaN];xl=[NaN NaN];yl=[NaN NaN];view=[NaN NaN];box='';xt=[];yt=[];
    try tag=get(axs(k),'tag');catch;end_try_catch;try old=get(axs(k),'units');set(axs(k),'units','normalized');pos=get(axs(k),'position');set(axs(k),'units',old);catch;end_try_catch
    try xl=get(axs(k),'xlim');catch;end_try_catch;try yl=get(axs(k),'ylim');catch;end_try_catch;try view=get(axs(k),'view');catch;end_try_catch;try box=get(axs(k),'box');catch;end_try_catch;try xt=get(axs(k),'xtick');yt=get(axs(k),'ytick');catch;end_try_catch
    helper=isempty(xt)&&isempty(yt)&&numel(xl)==2&&numel(yl)==2&&abs(xl(1))<1e-12&&abs(xl(2)-1)<1e-12&&abs(yl(1))<1e-12&&abs(yl(2)-1)<1e-12;
    cls='primary_candidate';lt=lower(strtrim(tag));if(!isempty(strfind(lt,'legend'))||helper),cls='helper';elseif(strcmp(lt,'gxtxt_overlay_yaxis')),cls='overlay';endif
    fprintf('[plot.dataset][region-diagnostic] axis=%d class=%s tag=%s box=%s position=%.9g;%.9g;%.9g;%.9g xlim=%.17g;%.17g ylim=%.17g;%.17g view=%.9g;%.9g\n',k,cls,tag,box,pos(1),pos(2),pos(3),pos(4),xl(1),xl(2),yl(1),yl(2),view(1),view(2));
  endfor
endfunction
function pd_region_diagnostic_post(target,graph)
  if(!pd_region_diag_enabled()),return;endif
  [d,n,~]=fileparts(target);md=fullfile(d,'.gxtxt_plotmeta',[n '.ini']);fprintf('[plot.dataset][region-diagnostic] phase=post_export graph_id=%s png=%s metadata=%s\n',graph,target,md);
  try info=imfinfo(target);fprintf('[plot.dataset][region-diagnostic] png_width=%d png_height=%d\n',info.Width,info.Height);catch err;fprintf('[plot.dataset][region-diagnostic] png_info_error=%s\n',err.message);end_try_catch
  if(exist(md,'file')==2),fid=fopen(md,'r');if(fid>=0),c=onCleanup(@() fclose(fid));while(true),line=fgetl(fid);if(!ischar(line)),break;endif;if(!isempty(regexp(line,'^(selection_supported|primary_axes_count|overlay_axes_count|image_width|image_height|pixel_rect|tag|position|xlim|xscale)=','once'))),fprintf('[plot.dataset][region-diagnostic] metadata %s\n',line);endif;endwhile;endif;else fprintf('[plot.dataset][region-diagnostic] metadata_missing=1\n');endif
endfunction

function V=plotspec(P),if(isfield(P,'plotspec_v2')),V=P.plotspec_v2;else V=struct('enabled',false,'multi_panel',false,'panel_count',1,'default_style',struct(),'axes',struct('x',struct(),'y_left',struct(),'y_right',struct()),'annotations',struct([]),'title_present',false,'title','');endif;endfunction
function value=presentation_value(cfg,graph,field,inherited)
  value=strtrim(inherited);override=strtrim(gxtxt_ini_get(cfg,['axis.' graph '.' field],''));
  if(!isempty(override)&&!strcmpi(override,'inherit')),value=override;endif
endfunction
function m=axis_mode(cfg,graph,axis_name),m=gxtxt_plot_axis_unit_mode(cfg,graph,axis_name,'auto');if(isempty(m)||strcmpi(m,'inherit')),m='auto';endif;endfunction
function m=effective_axis_unit(V,name,fallback,core_declared,core_enabled)
  if(core_declared)
    if(core_enabled),m=fallback;else m='auto';endif
    return;
  endif
  m=v2_axis_unit(V,name,fallback);
endfunction
function m=v2_axis_unit(V,name,fallback),m=fallback;if(V.enabled&&isfield(V.axes,name)),a=V.axes.(name);if(isfield(a,'display_unit')),m=strtrim(a.display_unit);if(isempty(m)),m=fallback;endif;endif;endif;endfunction
function s=v2_axis_label(V,name,fallback)
  s=fallback;if(!is_auto(fallback)),return;endif
  if(V.enabled&&isfield(V.axes,name)),a=V.axes.(name);if(isfield(a,'label')),s=a.label;endif;endif
endfunction
function tf=core_axis_state_enabled(cfg,graph)
  tf=false;q=str2double(gxtxt_ini_get(cfg,['axis.' graph '.enabled'],'0'));if(isfinite(q)&&q!=0),tf=true;endif
endfunction
function tf=core_axis_state_declared(cfg,graph)
  tf=false;prefix=['axis.' graph '.'];
  if(!cfg_has_key(cfg,[prefix 'enabled'])),return;endif
  % A variant runtime may synthesize only enabled=0 when no axis state exists.
  % The Axes dialog also seeds in-memory defaults on open; those defaults use
  % literal 'inherit' and must not override PlotSpec if the dialog is canceled.
  token_fields={'x_unit','y_unit','y2_unit','x_format','y_format','y2_format','xgrid','ygrid','align_ylabels'};
  for i=1:numel(token_fields)
    key=[prefix token_fields{i}];if(!cfg_has_key(cfg,key)),continue;endif
    v=strtrim(gxtxt_ini_get(cfg,key,'inherit'));
    if(isempty(v)||!strcmpi(v,'inherit')),tf=true;return;endif
  endfor
  value_fields={'x_min','x_max','x_step','y_min','y_max','y_step','y2_min','y2_max','y2_step','grid_color','ylabel_x'};
  for i=1:numel(value_fields)
    key=[prefix value_fields{i}];if(cfg_has_key(cfg,key)&&!isempty(strtrim(gxtxt_ini_get(cfg,key,'')))),tf=true;return;endif
  endfor
endfunction

function tf=core_axis_value_present(cfg,key)
  tf=cfg_has_key(cfg,key)&&!isempty(strtrim(gxtxt_ini_get(cfg,key,'')));
endfunction

function [has_min,has_max]=core_axis_bounds_present(cfg,graph,panel_id,side)
% Which bounds the CORE Axes dialog actually supplies for one axis side of one
% stacked panel ('y' = Y Left, 'y2' = Y Right). A graph-level value applies to
% every panel; a panel value refines it. Used to keep CORE authoritative per
% field instead of suppressing the whole PlotSpec axis, so the provider Graph
% configuration panel bounds still reach the axes CORE leaves automatic.
  has_min=false;has_max=false;
  prefix=['axis.' graph '.'];
  if(!cfg_has_key(cfg,[prefix 'enabled'])),return;endif
  en=str2double(gxtxt_ini_get(cfg,[prefix 'enabled'],'0'));
  if(isfinite(en)&&en==0),return;endif
  has_min=core_axis_value_present(cfg,[prefix side '_min']);
  has_max=core_axis_value_present(cfg,[prefix side '_max']);
  if(isempty(strtrim(panel_id))),return;endif
  panel_count=str2double(gxtxt_ini_get(cfg,[prefix 'panel_count'],'0'));
  if(!isfinite(panel_count)||panel_count<1),return;endif
  for j=1:round(panel_count)
    if(!strcmp(strtrim(gxtxt_ini_get(cfg,sprintf('%spanel%d_name',prefix,j),'')),strtrim(panel_id))),continue;endif
    ppfx=sprintf('%spanel%d_',prefix,j);
    if(core_axis_value_present(cfg,[ppfx side '_min'])),has_min=true;endif
    if(core_axis_value_present(cfg,[ppfx side '_max'])),has_max=true;endif
    return;
  endfor
endfunction

function apply_axis_one_fill(ax,a,which,skip_min,skip_max)
% Per-field companion of apply_axis_one(). CORE Axes stays authoritative for
% the bounds it actually declares; PlotSpec supplies only the bounds CORE
% leaves empty, rather than being suppressed as a whole. Scale keeps the
% PlotSpec ownership documented in apply_axis_one().
  if(isempty(a)||isempty(fieldnames(a))),return;endif
  apply_axis_ticks(ax,a,which);
  if(isfield(a,'scale')),q=lower(strtrim(a.scale));if(any(strcmp(q,{'linear','log'}))),set(ax,[which 'scale'],q);endif;endif
  lim=get(ax,[which 'lim']);changed=false;
  if(!skip_min&&isfield(a,'min')),v=str2double(strtrim(a.min));if(isfinite(v)),lim(1)=v;changed=true;endif;endif
  if(!skip_max&&isfield(a,'max')),v=str2double(strtrim(a.max));if(isfinite(v)),lim(2)=v;changed=true;endif;endif
  if(changed&&lim(1)<lim(2)),set(ax,[which 'lim'],lim);endif
  apply_log_x_grid(ax,a,which);
endfunction
function tf=cfg_has_key(cfg,key)
  k=regexprep(key,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;tf=isstruct(cfg)&&isfield(cfg,k);
endfunction

function kind=graph_default_kind(cfg,graph)
  q=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.plot_style'],'auto')));if(strcmp(q,'line_markers')),q='line_marker';endif
  if(strcmp(q,'auto')),q='line';endif;if(!any(strcmp(q,{'line','scatter','line_marker'}))),q='line';endif;kind=q;
endfunction
function kind=series_kind(S,fallback)
  kind=fallback;if(isfield(S,'presentation')&&isfield(S.presentation,'kind')),q=lower(strtrim(S.presentation.kind));if(!isempty(q)&&!strcmp(q,'auto')),kind=q;endif;endif
endfunction

function st=resolve_style(S,V,kind,graph_lw,graph_ms,auto_color)
  auto=struct('color',auto_color,'line_style','solid','line_width',graph_lw,'marker','none','marker_size',graph_ms,'marker_fill','none','opacity',1);
  if(any(strcmp(kind,{'scatter','line_marker','errorbar'}))),auto.marker='circle';endif
  if(any(strcmp(kind,{'scatter','errorbar'}))),auto.line_style='none';endif
  if(any(strcmp(kind,{'bar','histogram'}))),auto.line_style='none';auto.marker='none';endif
  if(strcmp(kind,'box_whisker')),auto.marker='circle';endif
  st=auto;
  if(V.enabled&&isfield(V,'default_style')),st=apply_style_layer(st,auto,V.default_style);endif
  if(isfield(S,'presentation')&&isfield(S.presentation,'style')),st=apply_style_layer(st,auto,S.presentation.style);endif
endfunction
function st=apply_style_layer(st,auto,layer)
  if(isempty(layer)||isempty(fieldnames(layer))),return;endif
  f=fieldnames(layer);for i=1:numel(f),name=f{i};v=layer.(name);if(ischar(v)),q=lower(strtrim(v));else q='';endif
    if(strcmp(q,'inherit')||isempty(q)),continue;elseif(strcmp(q,'auto')),st.(name)=auto.(name);else
      if(any(strcmp(name,{'line_width','marker_size','opacity'}))),n=str2double(v);if(isfinite(n)),st.(name)=n;endif;elseif(strcmp(name,'color')),st.color=parse_color(v,auto.color);else st.(name)=q;endif
    endif
  endfor
endfunction
function c=parse_color(v,def),c=def;q=strtrim(v);if(length(q)==7&&q(1)=='#'),r=hex2dec(q(2:3));g=hex2dec(q(4:5));b=hex2dec(q(6:7));if(all(isfinite([r g b]))),c=[r g b]/255;endif;endif;endfunction
function ls=line_style_value(s),switch lower(strtrim(s)),case 'dashed',ls='--';case 'dotted',ls=':';case 'dashdot',ls='-.';case 'none',ls='none';otherwise ls='-';endswitch;endfunction
function mk=marker_value(s),switch lower(strtrim(s)),case 'circle',mk='o';case 'square',mk='s';case 'diamond',mk='d';case 'triangle_up',mk='^';case 'triangle_down',mk='v';case 'plus',mk='+';case 'x',mk='x';case 'star',mk='*';otherwise mk='none';endswitch;endfunction

function h=draw_trace(ax,x,y,kind,st)
  if(isempty(x)),h=[];return;endif
  ls=line_style_value(st.line_style);mk=marker_value(st.marker);
  if(strcmp(kind,'scatter')),ls='none';if(strcmp(mk,'none')),mk='o';endif;elseif(strcmp(kind,'line_marker')),if(strcmp(mk,'none')),mk='o';endif;elseif(strcmp(kind,'errorbar')),ls='none';if(strcmp(mk,'none')),mk='o';endif;endif
  h=plot(ax,x,y,'linestyle',ls,'marker',mk,'markersize',st.marker_size,'linewidth',st.line_width,'color',st.color);
  try if(strcmpi(st.marker_fill,'full')&&!strcmp(mk,'none')),set(h,'markerfacecolor',st.color);elseif(strcmpi(st.marker_fill,'none')&&!strcmp(mk,'none')),set(h,'markerfacecolor','none');endif;catch;end_try_catch
endfunction
function h=draw_bar(ax,x,y,pres,st,S,idx,ord,target_x,target_y,level)
  if(isfield(pres,'bar_bounds')&&!isempty(fieldnames(pres.bar_bounds)))
    [lo,hi]=bar_bounds_values(S,idx,ord,target_x);
    if(numel(lo)!=numel(y)||numel(hi)!=numel(y)),error('plot.dataset: bar X bounds length mismatch for series %s',S.series_id);endif
    if(any(!isfinite(lo))||any(!isfinite(hi))||any(hi<=lo)),error('plot.dataset: bar X bounds must be finite with lower < upper for series %s',S.series_id);endif
    if(strcmp(get(ax,'xscale'),'log')&&any(lo<=0)),error('plot.dataset: logarithmic X interval bars require positive lower bounds for series %s',S.series_id);endif
    raw_baseline=0;if(isfield(pres,'bar_baseline')),q=strtrim(pres.bar_baseline);v=str2double(q);if(isfinite(v)),raw_baseline=v;endif;endif
    [bd,~,~]=pd_convert_display(raw_baseline,S.meta.unit,target_y,'Bar baseline');[baseline,~]=gxtxt_level_scale_apply(bd,target_y,level);baseline=baseline(1);
    if(strcmp(get(ax,'yscale'),'log')&&baseline<=0),pos=y(isfinite(y)&y>0);if(isempty(pos)),error('plot.dataset: logarithmic bar plot has no positive values');endif;baseline=min(pos)/2;endif
    h=[];hold_state=ishold(ax);hold(ax,'on');
    for bi=1:numel(y)
      if(!isfinite(y(bi))),continue;endif
      % Use line rectangles rather than filled patch polygons.  This stays
      % visible on the supported headless GNUplot backend while preserving
      % the exact Dataset-bound interval geometry.
      xx=[lo(bi) lo(bi) hi(bi) hi(bi) lo(bi)];yy=[baseline y(bi) y(bi) baseline baseline];
      hb=plot(ax,xx,yy,'-','color',st.color,'linewidth',max(0.5,st.line_width));
      if(isempty(h)),h=hb;else h(end+1)=hb;endif %#ok<AGROW>
    endfor
    if(!hold_state),hold(ax,'off');endif
    return;
  endif
  w=0.8;if(isfield(pres,'bar_width')),q=strtrim(pres.bar_width);v=str2double(q);if(isfinite(v)&&v>0),w=v;endif;endif
  h=bar(ax,x,y,w,'facecolor',st.color,'edgecolor',st.color);try set(h,'facealpha',st.opacity);catch;end_try_catch
endfunction
function [lo,hi]=bar_bounds_values(S,idx,ord,target)
  b=S.presentation.bar_bounds;[lv,lm]=aux_data(S,b.lower_variable_id,idx,ord);[uv,um]=aux_data(S,b.upper_variable_id,idx,ord);lu='';uu='';if(isfield(lm,'unit')),lu=lm.unit;endif;if(isfield(um,'unit')),uu=um.unit;endif
  [lo,~,~]=pd_convert_display(lv,lu,target,'Bar X lower');[hi,~,~]=pd_convert_display(uv,uu,target,'Bar X upper');
endfunction
function h=draw_band(ax,x,lo,hi,st,kind)
  if(isempty(x)),h=[];return;endif
  good=isfinite(x)&isfinite(lo)&isfinite(hi);x=x(good);lo=lo(good);hi=hi(good);if(isempty(x)),h=[];return;endif
  xx=[x(:);flipud(x(:))];yy=[lo(:);flipud(hi(:))];alpha=0.18;if(isfinite(st.opacity)&&st.opacity<1),alpha=st.opacity;endif
  h=patch('parent',ax,'xdata',xx,'ydata',yy,'facecolor',st.color,'edgecolor','none');try set(h,'facealpha',alpha);catch;end_try_catch
endfunction

function tf=has_error(pres,name),tf=false;if(isfield(pres,name)),e=pres.(name);if(isfield(e,'mode')),tf=!strcmpi(strtrim(e.mode),'none');endif;endif;endfunction
function [lo,hi]=error_x_endpoints(S,idx,ord,xp,target)
  lo=[];hi=[];if(!has_error(S.presentation,'x_error')),return;endif
  [dl,du]=error_delta_values(S,S.presentation.x_error,idx,ord,target,'X error');lo=xp-dl;hi=xp+du;
endfunction
function [lo,hi]=error_y_endpoints(S,idx,ord,yraw,target,level,ytrans)
  lo=[];hi=[];if(!has_error(S.presentation,'y_error')),return;endif
  [dl,du]=error_delta_values(S,S.presentation.y_error,idx,ord,target,'Y error');lowraw=yraw-dl;highraw=yraw+du;[lo,~]=gxtxt_level_scale_apply(lowraw,target,level);[hi,~]=gxtxt_level_scale_apply(highraw,target,level);
  % Keep invalid transformed endpoints out of the whisker vectors.
  bad=!isfinite(lo)|!isfinite(hi)|!isfinite(ytrans);lo(bad)=NaN;hi(bad)=NaN;
endfunction
function [dl,du]=error_delta_values(S,E,idx,ord,target,label)
  mode=lower(strtrim(E.mode));if(strcmp(mode,'symmetric')),a=aux_display_delta(S,E.variable_id,idx,ord,target,label);dl=a;du=a;elseif(strcmp(mode,'asymmetric')),dl=aux_display_delta(S,E.lower_variable_id,idx,ord,target,[label ' lower']);du=aux_display_delta(S,E.upper_variable_id,idx,ord,target,[label ' upper']);else dl=[];du=[];endif
endfunction
function d=aux_display_delta(S,id,idx,ord,target,label)
  [v,m]=aux_data(S,id,idx,ord);u='';if(isfield(m,'unit')),u=m.unit;endif
  if(isempty(strtrim(u))&&isempty(strtrim(target))),d=abs(v);return;endif
  if(isempty(strtrim(u))),error('plot.dataset: %s variable %s has no unit metadata',label,id);endif
  try z=gxtxt_unit_convert(zeros(size(v)),u,target);q=gxtxt_unit_convert(v,u,target);catch err,error('plot.dataset: cannot convert %s variable %s from %s to %s: %s',label,id,u,target,err.message);end_try_catch
  d=abs(q-z);
endfunction
function [lo,hi]=band_values(S,idx,ord,target,level)
  b=S.presentation.band;[lv,lm]=aux_data(S,b.lower_variable_id,idx,ord);[uv,um]=aux_data(S,b.upper_variable_id,idx,ord);lu='';uu='';if(isfield(lm,'unit')),lu=lm.unit;endif;if(isfield(um,'unit')),uu=um.unit;endif
  [lr,~,~]=pd_convert_display(lv,lu,target,'Band lower');[ur,~,~]=pd_convert_display(uv,uu,target,'Band upper');[lo,~]=gxtxt_level_scale_apply(lr,target,level);[hi,~]=gxtxt_level_scale_apply(ur,target,level);
endfunction
function [v,m]=aux_data(S,id,idx,ord)
  j=find(strcmp(S.data.aux_ids,id),1);if(isempty(j)),error('plot.dataset: PlotSpec auxiliary variable %s is not present in prepared cache for series %s',id,S.series_id);endif
  v=S.data.aux_values{j}(idx);v=v(ord);m=S.data.aux_meta{j};
  % Table streams may retain auxiliary CSV numbers as text cells. Numeric
  % bounds and uncertainties must be converted before unit/display scaling.
  if(iscell(v))
    if(all(cellfun(@ischar,v))),v=str2double(v);
    elseif(all(cellfun(@(x) isnumeric(x)&&isscalar(x),v))),v=cell2mat(v);
    else,error('plot.dataset: auxiliary variable %s has nonnumeric values',id);endif
  endif
endfunction
function draw_error_whiskers(ax,x,y,xlo,xhi,ylo,yhi,st)
  lw=max(0.5,0.8*st.line_width);c=st.color;
  if(!isempty(ylo)),n=numel(x);xx=reshape([x(:)';x(:)';nan(1,n)],[],1);yy=reshape([ylo(:)';yhi(:)';nan(1,n)],[],1);h=plot(ax,xx,yy,'-','color',c,'linewidth',lw);try set(h,'handlevisibility','off');catch;end_try_catch;endif
  if(!isempty(xlo)),n=numel(y);xx=reshape([xlo(:)';xhi(:)';nan(1,n)],[],1);yy=reshape([y(:)';y(:)';nan(1,n)],[],1);h=plot(ax,xx,yy,'-','color',c,'linewidth',lw);try set(h,'handlevisibility','off');catch;end_try_catch;endif
endfunction

function [xs,ys]=step_xy(x,y,mode)
  x=x(:);y=y(:);n=numel(x);if(n<=1),xs=x;ys=y;return;endif
  mode=lower(strtrim(mode));if(strcmp(mode,'pre'))
    xs=zeros(2*n-1,1);ys=zeros(2*n-1,1);xs(1)=x(1);ys(1)=y(1);p=2;for i=2:n,xs(p)=x(i-1);ys(p)=y(i);xs(p+1)=x(i);ys(p+1)=y(i);p+=2;endfor
  elseif(strcmp(mode,'mid'))
    m=(x(1:end-1)+x(2:end))/2;xs=zeros(2*n,1);ys=zeros(2*n,1);xs(1)=x(1);ys(1)=y(1);p=2;for i=1:n-1,xs(p)=m(i);ys(p)=y(i);xs(p+1)=m(i);ys(p+1)=y(i+1);p+=2;endfor;xs(end)=x(end);ys(end)=y(end);
  else
    xs=zeros(2*n-1,1);ys=zeros(2*n-1,1);xs(1)=x(1);ys(1)=y(1);p=2;for i=2:n,xs(p)=x(i);ys(p)=y(i-1);xs(p+1)=x(i);ys(p+1)=y(i);p+=2;endfor
  endif
endfunction

function apply_v2_axes(V,ax1,ax2,core_declared)
  if(!V.enabled),return;endif
  apply_axis_one(ax1,V.axes.x,'x',core_declared);apply_axis_one(ax1,V.axes.y_left,'y',core_declared);
  if(!isempty(ax2)),apply_axis_one(ax2,V.axes.x,'x',core_declared);apply_axis_one(ax2,V.axes.y_right,'y',core_declared);endif
endfunction
function pad_default_marker_x(ax,series,V,cfg,graph,display_unit,default_kind)
% Automatic limits can land exactly on the outer marker centers. Give visible
% points room without changing any explicit CORE, graph or PlotSpec bound.
  if(!strcmp(get(ax,'xscale'),'linear')),return;endif
  [core_min,core_max]=core_axis_bounds_present(cfg,graph,'','x');
  if(core_min||core_max),return;endif
  if(core_axis_value_present(cfg,['plot.' graph '.x_min'])||core_axis_value_present(cfg,['plot.' graph '.x_max'])),return;endif
  if(V.enabled&&isfield(V.axes,'x'))
    a=V.axes.x;
    if(isfield(a,'min')&&isfinite(str2double(strtrim(a.min)))),return;endif
    if(isfield(a,'max')&&isfinite(str2double(strtrim(a.max)))),return;endif
  endif
  marked=false;lo=Inf;hi=-Inf;
  for k=1:numel(series)
    kind=series_kind(series(k),default_kind);
    marked=marked||any(strcmp(kind,{'scatter','line_marker','errorbar','bar'}));
    if(isempty(series(k).data.x)),continue;endif
    xv=pd_convert_display(series(k).data.x,series(k).x_meta.unit,display_unit,'X');
    xv=xv(isfinite(xv));if(isempty(xv)),continue;endif
    lo=min(lo,min(xv));hi=max(hi,max(xv));
  endfor
  if(!marked||!isfinite(lo)||!isfinite(hi)||hi<=lo),return;endif
  lim=get(ax,'xlim');span=diff(lim);if(!isfinite(span)||span<=0),return;endif
  tolerance=1e-10*max(1,max(abs([lo hi lim])));
  if(abs(lo-lim(1))<=tolerance),lim(1)-=0.025*span;endif
  if(abs(hi-lim(2))<=tolerance),lim(2)+=0.025*span;endif
  set(ax,'xlim',lim);
endfunction
function apply_axis_one(ax,a,which,core_declared)
  if(isempty(a)||isempty(fieldnames(a))),return;endif
  apply_axis_ticks(ax,a,which);
  % CORE Axes owns display units and bounds once plot-specific axis state has
  % been declared. PlotSpec retains 2D linear/log scale because CORE 0.9.7.21
  % has no overlapping X/Y scale control.
  if(isfield(a,'scale')),q=lower(strtrim(a.scale));if(any(strcmp(q,{'linear','log'}))),set(ax,[which 'scale'],q);endif;endif
  if(isfield(a,'direction')),q=lower(strtrim(a.direction));if(any(strcmp(q,{'normal','reverse'}))),set(ax,[which 'dir'],q);endif;endif
  if(core_declared),apply_log_x_grid(ax,a,which);return;endif
  lim=get(ax,[which 'lim']);if(isfield(a,'min')),q=strtrim(a.min);v=str2double(q);if(isfinite(v)),lim(1)=v;endif;endif;if(isfield(a,'max')),q=strtrim(a.max);v=str2double(q);if(isfinite(v)),lim(2)=v;endif;endif
  if(lim(1)<lim(2)),set(ax,[which 'lim'],lim);endif
  apply_log_x_grid(ax,a,which);
endfunction
function apply_log_x_grid(ax,a,which)
% PlotSpec owns the major X step for both scales and log subdivisions.
  if(!strcmp(which,'x')),return;endif
  if(!strcmp(get(ax,'xscale'),'log'))
    step=NaN;if(isfield(a,'major_step')),step=str2double(a.major_step);endif
    if(isfinite(step)&&step>0)
      lim=get(ax,'xlim');first=ceil((lim(1)-step*1e-10)/step)*step;
      last=floor((lim(2)+step*1e-10)/step)*step;
      ticks=first:step:last;if(!isempty(ticks)),set(ax,'xtick',ticks);endif
    endif
    return;
  endif
  lim=get(ax,'xlim');if(any(!isfinite(lim))||lim(1)<=0||lim(2)<=lim(1)),return;endif
  step=NaN;if(isfield(a,'major_step')),step=str2double(a.major_step);endif
  [major,minor]=pd_log_x_grid_positions(lim,step);
  if(!isempty(major)),set(ax,'xtick',major);endif
  if(!isfield(a,'minor_grid')||!strcmpi(strtrim(a.minor_grid),'auto')),return;endif
  tag='';try tag=lower(strtrim(get(ax,'tag')));catch;end_try_catch
  if(!isempty(strfind(tag,'overlay_yaxis'))),return;endif
  yl=get(ax,'ylim');
  for value=minor
    line('parent',ax,'xdata',[value value],'ydata',yl,'linestyle',':', ...
         'linewidth',0.45,'color',[0.78 0.78 0.78], ...
         'handlevisibility','off','tag','gxtxt_log_x_minor_grid');
  endfor
  set(ax,'xlim',lim,'ylim',yl);
endfunction
function apply_axis_ticks(ax,a,which)
  if(!strcmp(which,'x')||!isfield(a,'tick_positions')||!isfield(a,'tick_labels')),return;endif
  positions=cellfun(@str2double,strsplit(a.tick_positions,';'));
  labels=strsplit(a.tick_labels,';');labels=cellfun(@strtrim,labels,'UniformOutput',false);
  if(isempty(positions)||numel(positions)!=numel(labels)||any(!isfinite(positions))),error('plot.dataset: invalid persistent X tick labels');endif
  set(ax,'xtick',positions,'xticklabel',labels);
endfunction

function draw_v2_annotations(V,ax1,ax2)
  if(!V.enabled||isempty(V.annotations)),return;endif
  for i=1:numel(V.annotations),a=V.annotations(i);if(!isfield(a,'type')),continue;endif;axis_name='x';if(isfield(a,'axis')),axis_name=lower(strtrim(a.axis));endif
    ax=ax1;if(strcmp(axis_name,'right')&&!isempty(ax2)),ax=ax2;endif
    c=[0.35 0.35 0.35];if(isfield(a,'color')),c=parse_color(a.color,c);endif;ls='--';if(isfield(a,'line_style')&&!isempty(strtrim(a.line_style))),ls=line_style_value(a.line_style);endif;lw=1;if(isfield(a,'line_width')),q=str2double(a.line_width);if(isfinite(q)&&q>0),lw=q;endif;endif;alpha=0.12;if(isfield(a,'opacity')),q=str2double(a.opacity);if(isfinite(q)&&q>=0&&q<=1),alpha=q;endif;endif
    t=lower(strtrim(a.type));
    if(strcmp(t,'reference_line')&&isfield(a,'value'))
      v=str2double(a.value);if(strcmp(axis_name,'x')),yl=get(ax,'ylim');h=plot(ax,[v v],yl,ls,'color',c,'linewidth',lw);label_reference(ax,a,v,yl(2),'x');else xl=get(ax,'xlim');h=plot(ax,xl,[v v],ls,'color',c,'linewidth',lw);label_reference(ax,a,xl(2),v,'y');endif;try set(h,'handlevisibility','off');catch;end_try_catch
    elseif(strcmp(t,'reference_region')&&isfield(a,'min')&&isfield(a,'max'))
      lo=str2double(a.min);hi=str2double(a.max);if(strcmp(axis_name,'x')),yl=get(ax,'ylim');xx=[lo hi hi lo];yy=[yl(1) yl(1) yl(2) yl(2)];else xl=get(ax,'xlim');xx=[xl(1) xl(2) xl(2) xl(1)];yy=[lo lo hi hi];endif
      h=patch('parent',ax,'xdata',xx,'ydata',yy,'facecolor',c,'edgecolor','none');try set(h,'facealpha',alpha,'handlevisibility','off');catch;end_try_catch
    elseif(strcmp(t,'text')&&isfield(a,'x')&&isfield(a,'y')&&isfield(a,'label'))
      xv=str2double(a.x);yv=str2double(a.y);
      if(isfinite(xv)&&isfinite(yv)&&!isempty(strtrim(a.label)))
        text(ax,xv,yv,a.label,'color',c,'fontsize',8,'horizontalalignment','center', ...
          'verticalalignment','bottom','interpreter','none','clipping','on');
      endif
    endif
  endfor
endfunction
function label_reference(ax,a,x,y,which)
  if(!isfield(a,'label')||isempty(strtrim(a.label))),return;endif
  try
    xl=get(ax,'xlim');yl=get(ax,'ylim');
    if(strcmp(which,'x'))
      x+=0.006*diff(xl);y-=0.035*diff(yl);align='left';
    else
      x-=0.012*diff(xl);y+=0.012*diff(yl);align='right';
    endif
    fs=max(6,min(7,get(ax,'fontsize')*0.55));
    text(ax,x,y,a.label,'color',get(ax,'xcolor'),'fontsize',fs, ...
      'horizontalalignment',align,'verticalalignment','top','clipping','on','interpreter','none');
  catch
  end_try_catch
endfunction

function pd_print_extra(fig,png_path,V)
  if(!isfield(V,'output_extra_format')),return;endif
  fmt=lower(strtrim(V.output_extra_format));if(isempty(fmt)||strcmp(fmt,'none')),return;endif
  [folder,base,~]=fileparts(png_path);target=fullfile(folder,[base '.' fmt]);
  switch fmt
    case 'svg',print(fig,target,'-dsvg');
    case 'pdf',print(fig,target,'-dpdf','-color');
    otherwise,error('plot.dataset: unsupported extra graph format %s',fmt);
  endswitch
endfunction


function tf=has_family_group(S)
  tf=isfield(S,'presentation')&&isfield(S.presentation,'family_variable_id')&&!isempty(strtrim(S.presentation.family_variable_id));
endfunction

function n=family_group_total(series)
  n=0;
  for k=1:numel(series)
    if(!has_family_group(series(k))),continue;endif
    [vals,~]=family_values_meta(series(k));
    if(!isempty(vals))
      if(iscell(vals)),n+=numel(unique(vals,'stable'));
      else,n+=numel(unique(vals(isfinite(vals)),'stable'));endif
    endif
  endfor
endfunction

function [vals,meta]=family_values_meta(S)
  vals=[];meta=struct('name','Family','unit','');
  if(!has_family_group(S)),return;endif
  id=strtrim(S.presentation.family_variable_id);
  j=find(strcmp(S.data.aux_ids,id),1);
  if(isempty(j)),error('plot.dataset: family variable %s was not prepared for series %s',id,S.series_id);endif
  vals=S.data.aux_values{j};
  if(j<=numel(S.data.aux_meta)),meta=S.data.aux_meta{j};endif
endfunction

function [handles,labels,color_cursor]=draw_family_series(ax,S,V,xp,yp,idx,kind,graph_lw,graph_ms,palette,color_cursor,legend_mode)
  [raw,meta]=family_values_meta(S);raw=raw(idx);
  if(iscell(raw)),finite=true(size(raw));keys=unique(raw,'stable');
  else,finite=isfinite(raw);keys=num2cell(unique(raw(finite),'stable'));endif
  handles=[];labels={};
  if(isempty(keys)),error('plot.dataset: family series %s has no finite family values',S.series_id);endif
  prefix=strtrim(S.presentation.family_label_prefix);
  if(isempty(prefix)),if(isfield(meta,'name')&&!isempty(strtrim(meta.name))),prefix=display_name(meta.name);else prefix='Family';endif;endif
  unit='';if(isfield(meta,'unit')),unit=strtrim(meta.unit);endif
  for gi=1:numel(keys)
    key=keys{gi};
    if(iscell(raw)),take=find(strcmp(raw,key));else,take=find(finite & raw==key);endif
    if(isempty(take)),continue;endif
    color_cursor+=1;auto_color=palette(mod(color_cursor-1,rows(palette))+1,:);st=resolve_style(S,V,kind,graph_lw,graph_ms,auto_color);
    gx=xp(take);gy=yp(take);
    if(strcmp(kind,'step'))
      smode='post';if(isfield(S.presentation,'step_mode')&&!isempty(strtrim(S.presentation.step_mode))),smode=S.presentation.step_mode;endif
      [gx,gy]=step_xy(gx,gy,smode);h=draw_trace(ax,gx,gy,'line',st);
    else
      h=draw_trace(ax,gx,gy,kind,st);
    endif
    if(!isempty(h)&&strcmp(legend_mode,'series'))
      handles(end+1)=h(1);
      if(ischar(key)),lab=sprintf('%s=%s',prefix,key);else,lab=sprintf('%s=%g',prefix,key);endif
      if(!isempty(unit)),lab=[lab ' ' unit];endif;labels{end+1}=lab;
    endif
  endfor
endfunction

function s=series_label(S,unit),if(!isempty(strtrim(S.label))),s=S.label;else s=display_name(S.name);endif;if(!isempty(unit)),s=[s ' [' unit ']'];endif;endfunction
function s=axis_label(name,unit),s=name;if(!isempty(unit)),s=[s ' [' unit ']'];endif;endfunction
function label=display_axis_label(label,source_unit,display_unit)
  source_unit=strtrim(source_unit);display_unit=strtrim(display_unit);
  if(isempty(source_unit)||strcmp(source_unit,display_unit)),return;endif
  suffix=[' [' source_unit ']'];
  if(numel(label)<numel(suffix)||!strcmp(label(end-numel(suffix)+1:end),suffix)),return;endif
  label=label(1:end-numel(suffix));
  if(!isempty(display_unit)),label=[label ' [' display_unit ']'];endif
endfunction
function s=display_name(s),s=strrep(s,'_',' ');endfunction
function tf=is_auto(s),tf=isempty(strtrim(s))||strcmpi(strtrim(s),'auto');endfunction
function tf=parse_bool(s,d),if(islogical(s)),tf=s;return;endif;q=lower(strtrim(s));if(any(strcmp(q,{'1','true','yes','on'}))),tf=true;elseif(any(strcmp(q,{'0','false','no','off'}))),tf=false;else tf=d;endif;endfunction
function v=parse_positive(s,d),v=str2double(s);if(!isfinite(v)||v<=0),v=d;endif;endfunction
function v=parse_line_width(s,d),if(isempty(strtrim(s))||strcmpi(strtrim(s),'inherit')),v=d;else v=parse_positive(s,d);endif;endfunction

function [x,y]=source_trace(S,x,y,idx)
  if(!isfield(S.presentation,'source_row_continuity')||!S.presentation.source_row_continuity||numel(x)<2),return;endif
  ordinals=S.data.source_row_indices(idx);
  gaps=find(diff(ordinals)!=1);
  for k=numel(gaps):-1:1
    j=gaps(k);x=[x(1:j);NaN;x(j+1:end)];y=[y(1:j);NaN;y(j+1:end)];
  endfor
endfunction
