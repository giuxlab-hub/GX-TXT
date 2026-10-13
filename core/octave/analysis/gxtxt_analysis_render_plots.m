% SPDX-License-Identifier: GPL-3.0-or-later
% Generic plot renderer for Scientific Analysis Definition API v1.
% v0.9.1 adds dual-Y axes, unit-aware display scaling and basic 3D line/scatter.
function files = gxtxt_analysis_render_plots(def,ctx,outdir,options)
  files={};
  ids=parse_list(gxtxt_ini_get(def,'plots.ids',''));
  if (isempty(ids)), return; endif
  runtime=struct(); if(nargin>=4 && isfield(options,'runtime_cfg')),runtime=options.runtime_cfg;endif
  for i=1:numel(ids)
    id=ids{i}; typ=lower(strtrim(gxtxt_ini_get(def,['plot.' id '.type'],'line')));
    file=strtrim(gxtxt_ini_get(def,['plot.' id '.file'],[regexprep(id,'[^A-Za-z0-9_-]','_') '.png']));
    auto_units=parse_bool_local(gxtxt_ini_get(def,['plot.' id '.auto_units'],'0'),false);
    group_id=strtrim(gxtxt_ini_get(def,['plot.' id '.group'],''));
    domain_id=strtrim(gxtxt_ini_get(def,['plot.' id '.domain'],''));
    [group,domain,group_valid,domain_valid]=plot_masks(ctx,group_id,domain_id,id);

    gxtxt_setup_graphics(); p=gxtxt_plot_config(); fig=gxtxt_plot_new_figure(p);
    handles=[]; legend_labels={};

    if(any(strcmp(typ,{'line3','scatter3'})))
      xid=strtrim(gxtxt_ini_get(def,['plot.' id '.x'],''));
      yid=strtrim(gxtxt_ini_get(def,['plot.' id '.y'],''));
      zid=strtrim(gxtxt_ini_get(def,['plot.' id '.z'],''));
      if(isempty(xid)||isempty(yid)||isempty(zid)),close(fig);error('GXTXT:AnalysisPlot','3D plot %s requires x, y and z',id);endif
      require_series(ctx,xid,id);require_series(ctx,yid,id);require_series(ctx,zid,id);
      x=row_numeric(ctx,xid,id);y=row_numeric(ctx,yid,id);z=row_numeric(ctx,zid,id);
      xu0=series_unit(ctx,xid);yu0=series_unit(ctx,yid);zu0=series_unit(ctx,zid);xu=xu0;yu=yu0;zu=zu0;xf=1;yf=1;zf=1;
      xm=axis_unit_mode(runtime,id,'x_unit');if(strcmp(xm,'inherit')),xm=axis_unit_mode(runtime,id,'time_unit');endif;if(strcmp(xm,'inherit')),if(auto_units),xm='auto';else xm='source';endif;endif
      ym=axis_unit_mode(runtime,id,'y_unit');if(strcmp(ym,'inherit')),if(auto_units),ym='auto';else ym='source';endif;endif
      zm=axis_unit_mode(runtime,id,'z_unit');if(strcmp(zm,'inherit')),if(auto_units),zm='auto';else zm='source';endif;endif
      if(!isempty(xu0)),[x,xu,xf]=gxtxt_plot_display_scale(x,xu0,xm);endif
      if(!isempty(yu0)),[y,yu,yf]=gxtxt_plot_display_scale(y,yu0,ym);endif
      if(!isempty(zu0)),[z,zu,zf]=gxtxt_plot_display_scale(z,zu0,zm);endif
      zlevel=gxtxt_level_scale_config(runtime,id,'z');
      [z,zlevel_label]=gxtxt_level_scale_apply(z,zu,zlevel);
      ax=axes('parent',fig);set(ax,'tag','gxtxt_primary_axis');hold(ax,'on');
      valid=domain & domain_valid & series_valid_mask(ctx,xid,ctx.row_count) & series_valid_mask(ctx,yid,ctx.row_count) & series_valid_mask(ctx,zid,ctx.row_count) & isfinite(x) & isfinite(y) & isfinite(z);
      if(isempty(group_id))
        if(any(valid))
          if(strcmp(typ,'line3')),h=plot3(ax,x(valid),y(valid),z(valid),'-','linewidth',p.line_width);else h=plot3(ax,x(valid),y(valid),z(valid),'o','linestyle','none');endif
          if(!isempty(h)),handles(end+1)=h;legend_labels{end+1}=strtrim(gxtxt_ini_get(def,['plot.' id '.series_label'],''));endif
        endif
      else
        [gvals,gidx]=group_index(group);
        for g=1:numel(gidx)
          idx=false(ctx.row_count,1);idx(gidx{g})=true;idx &= valid & group_valid;
          if(!any(idx)),continue;endif
          if(strcmp(typ,'line3')),h=plot3(ax,x(idx),y(idx),z(idx),'-','linewidth',p.line_width);else h=plot3(ax,x(idx),y(idx),z(idx),'o','linestyle','none');endif
          if(isempty(h)),continue;endif
          handles(end+1)=h;legend_labels{end+1}=group_label(gvals{g}); %#ok<AGROW>
        endfor
      endif
      title(ax,runtime_or_def(runtime,def,id,'title',id));
      xlabel(ax,label_with_unit(runtime_or_def(runtime,def,id,'x_label',xid),xu));
      ylabel(ax,label_with_unit(runtime_or_def(runtime,def,id,'y_label',yid),yu));
      zlabel(ax,level_axis_label(label_with_unit(runtime_or_def(runtime,def,id,'z_label',zid),zu),zlevel_label));
      % Publish canonical metadata before applying presentation overrides.
      set_axis_meta(ax,'x',xid,xu0,xu,xf,ctx,runtime);
      set_axis_meta(ax,'y',yid,yu0,yu,yf,ctx,runtime);
      set_axis_meta(ax,'z',zid,zu0,zu,zf,ctx,runtime);
      gxtxt_level_scale_metadata(ax,zlevel,'z');
      gxtxt_plot_apply_axes3d(ax,p);
      az=str2double(gxtxt_ini_get(def,['plot.' id '.view_azimuth'],''));el=str2double(gxtxt_ini_get(def,['plot.' id '.view_elevation'],''));
      if(isfinite(az)||isfinite(el)),try vv=get(ax,'view');if(!isfinite(az)),az=vv(1);endif;if(!isfinite(el)),el=vv(2);endif;view(ax,az,el);catch;end_try_catch;endif
      gxtxt_plot_axis_overrides(ax,id,{},p,runtime);
      if(!isempty(handles) && (numel(handles)>1 || !isempty(group_id))),gxtxt_plot_legend(handles,legend_labels,p,id,runtime);endif
    else
      x_id=strtrim(gxtxt_ini_get(def,['plot.' id '.x'],''));
      ys=parse_list(gxtxt_ini_get(def,['plot.' id '.series'],''));
      if (isempty(x_id) || isempty(ys)), close(fig);error('GXTXT:AnalysisPlot','Plot %s requires x and series',id); endif
      require_series(ctx,x_id,id); for j=1:numel(ys),require_series(ctx,ys{j},id);endfor
      labels=parse_list(gxtxt_ini_get(def,['plot.' id '.series_labels'],'')); if(numel(labels)!=numel(ys)),labels=ys;endif
      series_axes=parse_list(gxtxt_ini_get(def,['plot.' id '.series_axes'],''));
      if(isempty(series_axes)),series_axes=repmat({'left'},1,numel(ys));endif
      if(numel(series_axes)!=numel(ys)),close(fig);error('GXTXT:AnalysisPlot','Plot %s series_axes must match series count',id);endif
      series_axes=cellfun(@(q)lower(strtrim(q)),series_axes,'UniformOutput',false);
      if(any(!cellfun(@(q)any(strcmp(q,{'left','right'})),series_axes))),close(fig);error('GXTXT:AnalysisPlot','Plot %s supports only left/right series_axes in API v1',id);endif
      dual=any(strcmp(series_axes,'right'));
      if(dual && strcmp(typ,'bar')),close(fig);error('GXTXT:AnalysisPlot','bar does not support right Y axis in Multi-Y Axis API v1');endif
      if(dual),[axL,axR]=gxtxt_plot_dual_y_axes(fig,p);else axL=axes('parent',fig);set(axL,'tag','gxtxt_primary_axis');hold(axL,'on');axR=[];endif
      x=row_series(ctx,x_id,id);xunit=series_unit(ctx,x_id);x_source_unit=xunit;x_factor=1;
      if(isnumeric(x))
        xmode=axis_unit_mode(runtime,id,'x_unit');
        if(strcmp(xmode,'inherit')),xmode=axis_unit_mode(runtime,id,'time_unit');endif
        if(strcmp(xmode,'inherit')),if(auto_units),xmode='auto';else xmode='none';endif;endif
        if(!isempty(xunit)),[x,xunit,x_factor]=gxtxt_plot_display_scale(x,xunit,xmode);endif
      endif
      [plotvals,leftUnit,rightUnit,leftFactor,rightFactor,leftSourceUnit,rightSourceUnit]=prepare_y_values(ctx,ys,series_axes,auto_units,id,runtime);
      leftLevel=gxtxt_level_scale_config(runtime,id,'y');
      rightLevel=gxtxt_level_scale_config(runtime,id,'y2');
      leftLevelLabel='';rightLevelLabel='';
      for j=1:numel(ys)
        if(strcmp(series_axes{j},'left'))
          [plotvals{j},leftLevelLabel]=gxtxt_level_scale_apply(plotvals{j},leftUnit,leftLevel);
        else
          [plotvals{j},rightLevelLabel]=gxtxt_level_scale_apply(plotvals{j},rightUnit,rightLevel);
        endif
      endfor
      switch typ
        case 'bar'
          if(!isempty(group_id)),close(fig);error('GXTXT:AnalysisPlot','bar plots do not support group= in API v1');endif
          M=zeros(ctx.row_count,numel(ys));
          for j=1:numel(ys),q=plotvals{j};q(!domain)=NaN;M(:,j)=q;endfor
          handles=bar(axL,1:ctx.row_count,M,'grouped'); legend_labels=labels;
          set(axL,'xtick',1:ctx.row_count);
          if (iscell(x)),set(axL,'xticklabel',x);else set(axL,'xticklabel',arrayfun(@(q)sprintf('%.6g',q),x,'UniformOutput',false));endif
        case {'line','scatter'}
          xn=numeric_series(x,x_id); x_valid=series_valid_mask(ctx,x_id,ctx.row_count);
          if(isempty(group_id))
            for j=1:numel(ys)
              yn=plotvals{j}; y_valid=series_valid_mask(ctx,ys{j},ctx.row_count);
              idx=domain & domain_valid & x_valid & y_valid & isfinite(xn) & isfinite(yn);
              if(!any(idx)),continue;endif
              ax=axis_for_series(axL,axR,series_axes{j});
              if(strcmp(typ,'line')),h=plot(ax,xn(idx),yn(idx),'-','linewidth',p.line_width);else h=plot(ax,xn(idx),yn(idx),'o','linestyle','none');endif
              if(isempty(h)),continue;endif
              handles(end+1)=h;legend_labels{end+1}=labels{j}; %#ok<AGROW>
            endfor
          else
            [gvals,gidx]=group_index(group);
            for j=1:numel(ys)
              yn=plotvals{j}; y_valid=series_valid_mask(ctx,ys{j},ctx.row_count);ax=axis_for_series(axL,axR,series_axes{j});
              for g=1:numel(gidx)
                idx=false(ctx.row_count,1);idx(gidx{g})=true;
                idx &= domain & domain_valid & group_valid & x_valid & y_valid & isfinite(xn) & isfinite(yn);
                if(!any(idx)),continue;endif
                if(strcmp(typ,'line')),h=plot(ax,xn(idx),yn(idx),'-','linewidth',p.line_width);else h=plot(ax,xn(idx),yn(idx),'o','linestyle','none');endif
                if(isempty(h)),continue;endif
                handles(end+1)=h; %#ok<AGROW>
                if(numel(ys)==1),legend_labels{end+1}=group_label(gvals{g});else legend_labels{end+1}=sprintf('%s — %s',labels{j},group_label(gvals{g}));endif %#ok<AGROW>
              endfor
            endfor
          endif
        otherwise
          close(fig); error('GXTXT:AnalysisPlot','Unsupported plot type: %s',typ);
      endswitch
      title(axL,runtime_or_def(runtime,def,id,'title',id));
      xlabel(axL,label_with_unit(runtime_or_def(runtime,def,id,'x_label',x_id),xunit));
      leftLabel=runtime_or_def(runtime,def,id,'y_label','');if(isempty(strtrim(leftLabel))),leftLabel=axis_default_label(labels,series_axes,'left');endif
      ylabel(axL,level_axis_label(label_with_unit(leftLabel,leftUnit),leftLevelLabel));
      set_axis_meta(axL,'x',x_id,x_source_unit,xunit,x_factor,ctx,runtime);
      set_axis_meta(axL,'y',first_series_for_axis(ys,series_axes,'left'),leftSourceUnit,leftUnit,leftFactor,ctx,runtime);
      gxtxt_level_scale_metadata(axL,leftLevel);
      gxtxt_plot_apply_axes(axL,p);
      gxtxt_plot_axis_overrides(axL,id,{},p,runtime);
      if(dual)
        rightLabel=runtime_or_def(runtime,def,id,'y2_label','');if(isempty(strtrim(rightLabel))),rightLabel=axis_default_label(labels,series_axes,'right');endif
        ylabel(axR,level_axis_label(label_with_unit(rightLabel,rightUnit),rightLevelLabel));
        set_axis_meta(axR,'x',x_id,x_source_unit,xunit,x_factor,ctx,runtime);
        set_axis_meta(axR,'y',first_series_for_axis(ys,series_axes,'right'),rightSourceUnit,rightUnit,rightFactor,ctx,runtime);
        gxtxt_level_scale_metadata(axR,rightLevel);
        try set(axR,'xlim',get(axL,'xlim'));catch;end_try_catch
      endif
      if (!isempty(handles) && (numel(handles)>1 || !isempty(group_id)))
        gxtxt_plot_legend(handles,legend_labels,p,id,runtime);
      endif
    endif
    path=fullfile(outdir,file); gxtxt_print_png_atomic(fig,path,p.dpi); close(fig); files{end+1}=path; %#ok<AGROW>
  endfor
endfunction

function [group,domain,group_valid,domain_valid]=plot_masks(ctx,group_id,domain_id,plotid)
  group=[];domain=true(ctx.row_count,1);group_valid=true(ctx.row_count,1);domain_valid=true(ctx.row_count,1);
  if(!isempty(group_id)),require_series(ctx,group_id,plotid);group=ctx.series.(group_id);if(numel(group)!=ctx.row_count),error('GXTXT:AnalysisPlot','Group %s is not row-aligned',group_id);endif;group_valid=series_valid_mask(ctx,group_id,ctx.row_count);endif
  if(!isempty(domain_id)),require_series(ctx,domain_id,plotid);domain=ctx.series.(domain_id);if(!islogical(domain)),domain=logical(domain);endif;if(numel(domain)!=ctx.row_count),error('GXTXT:AnalysisPlot','Domain %s is not row-aligned',domain_id);endif;domain=domain(:);domain_valid=series_valid_mask(ctx,domain_id,ctx.row_count);endif
endfunction
function v=row_series(ctx,id,plotid),v=ctx.series.(id);if(!(isscalar(v)||numel(v)==ctx.row_count)),error('GXTXT:AnalysisPlot','Plot %s series %s is not primary-row-aligned; align/resample it first',plotid,id);endif;if(isscalar(v)&&ctx.row_count>1),v=repmat(v,ctx.row_count,1);endif;v=v(:);endfunction
function v=row_numeric(ctx,id,plotid),v=row_series(ctx,id,plotid);v=numeric_series(v,id);endfunction
function [vals,leftUnit,rightUnit,leftFactor,rightFactor,leftSourceUnit,rightSourceUnit]=prepare_y_values(ctx,ys,axesList,autoUnits,plotid,runtime)
  vals=cell(1,numel(ys));for j=1:numel(ys),vals{j}=row_numeric(ctx,ys{j},plotid);endfor
  left=find(strcmp(axesList,'left'));right=find(strcmp(axesList,'right'));
  lm=axis_unit_mode(runtime,plotid,'y_unit');if(strcmp(lm,'inherit')),if(autoUnits),lm='auto';else lm='none';endif;endif
  rm=axis_unit_mode(runtime,plotid,'y2_unit');if(strcmp(rm,'inherit')),if(autoUnits),rm='auto';else rm='none';endif;endif
  [vals,leftUnit,leftFactor,leftSourceUnit]=scale_axis_group(vals,ctx,ys,left,lm);
  [vals,rightUnit,rightFactor,rightSourceUnit]=scale_axis_group(vals,ctx,ys,right,rm);
endfunction
function [vals,dispUnit,factor,sourceUnit]=scale_axis_group(vals,ctx,ys,idx,mode)
  dispUnit='';sourceUnit='';factor=1;if(isempty(idx)),return;endif
  units=cellfun(@(q)series_unit(ctx,q),ys(idx),'UniformOutput',false);nonempty=find(!cellfun(@isempty,units));
  if(isempty(nonempty)),return;endif
  first=units{nonempty(1)};sourceUnit=first;compatible=true;
  for k=1:numel(nonempty),try if(!gxtxt_unit_compatible(first,units{nonempty(k)})),compatible=false;break;endif;catch,compatible=false;break;end_try_catch;endfor
  if(!compatible),if(all(strcmp(units,first))),dispUnit=first;endif;return;endif
  if(strcmp(mode,'none')),dispUnit=first;return;endif
  allv=[];for k=idx,allv=[allv;vals{k}(:)];endfor %#ok<AGROW>
  [~,dispUnit,factor]=gxtxt_plot_display_scale(allv,first,mode);
  for k=idx
    u=series_unit(ctx,ys{k});if(isempty(u)),continue;endif
    [vals{k},~]=gxtxt_plot_display_scale(vals{k},u,dispUnit);
  endfor
endfunction
function ax=axis_for_series(left,right,which),if(strcmp(which,'right')),ax=right;else ax=left;endif;endfunction
function u=series_unit(ctx,id),u='';if(isfield(ctx,'units')&&isfield(ctx.units,id)),u=strtrim(ctx.units.(id));endif;endfunction
function s=label_with_unit(s,u),s=strtrim(s);u=strtrim(u);if(isempty(u)),return;endif;if(isempty(s)),s=['[' u ']'];elseif(isempty(strfind(s,'['))),s=[s ' [' u ']'];endif;endfunction
function s=axis_default_label(labels,axesList,side),idx=find(strcmp(axesList,side));if(isempty(idx)),s='';elseif(numel(idx)==1),s=labels{idx(1)};else s=strjoin(labels(idx),', ');endif;endfunction
function mask=series_valid_mask(ctx,id,n)
  mask=true(n,1);
  if(isempty(id)||!isfield(ctx,'status')||!isfield(ctx.status,id)),return;endif
  st=ctx.status.(id);if(ischar(st)),st={st};endif;if(isscalar(st)&&n>1),st=repmat(st,n,1);endif;if(numel(st)!=n),return;endif;st=st(:);
  for k=1:n,q=lower(strtrim(st{k}));if(any(strcmp(q,{'unavailable','failed'}))),mask(k)=false;endif;endfor
endfunction
function q=runtime_or_def(runtime,def,id,key,default),q=gxtxt_ini_get(runtime,['plot.' id '.' key],'');if(isempty(strtrim(q))),q=gxtxt_ini_get(def,['plot.' id '.' key],default);endif;endfunction
function v=numeric_series(v,id),if(!isnumeric(v)),error('GXTXT:AnalysisPlot','Plot series %s must be numeric',id);endif;v=v(:);endfunction
function require_series(ctx,id,plotid),if(!isfield(ctx.series,id)),error('GXTXT:AnalysisPlot','Plot %s references missing series %s',plotid,id);endif;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif;endfunction
function tf=parse_bool_local(v,d),if(nargin<2),d=false;endif;if(islogical(v)),tf=v;return;endif;s=lower(strtrim(num2str(v)));if(any(strcmp(s,{'1','true','yes','on'}))),tf=true;elseif(any(strcmp(s,{'0','false','no','off'}))),tf=false;else tf=d;endif;endfunction
function mode=axis_unit_mode(runtime,plotid,key)
  mode=lower(strtrim(gxtxt_ini_get(runtime,['axis.' plotid '.' key],'inherit')));
  if(isempty(mode)),mode='inherit';endif
endfunction
function id=first_series_for_axis(ys,axesList,side)
  id='';idx=find(strcmp(axesList,side),1);if(!isempty(idx)),id=ys{idx};endif
endfunction
function set_axis_meta(ax,which,varid,sourceUnit,displayUnit,factor,ctx,runtime)
  if(isempty(ax)),return;endif
  sourceVar=varid; canonicalUnit=sourceUnit;
  % For a directly bound Analysis variable, publish the canonical dataset
  % column/unit rather than the Analysis Definition's logical variable ID.
  try
    if(!isempty(varid) && isfield(ctx,'bindings') && isfield(ctx.bindings,varid))
      b=ctx.bindings.(varid);sourceVar=b.column;
      [cu,~]=gxtxt_analysis_source_variable_meta(runtime,b.source,b.column);
      if(!isempty(strtrim(cu))),canonicalUnit=strtrim(cu);endif
    endif
  catch
  end_try_catch
  scale=NaN;offset=0;
  try
    if(!isempty(strtrim(displayUnit)) && !isempty(strtrim(canonicalUnit)) && gxtxt_unit_compatible(displayUnit,canonicalUnit))
      offset=gxtxt_unit_convert(0,displayUnit,canonicalUnit);
      scale=gxtxt_unit_convert(1,displayUnit,canonicalUnit)-offset;
    endif
  catch
  end_try_catch
  if(!isfinite(scale)||scale==0)
    if(!isfinite(factor)||factor==0),factor=1;endif
    scale=1/factor;offset=0;
  endif
  try setappdata(ax,['gxtxt_' which '_source_variable'],sourceVar);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_source_unit'],canonicalUnit);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_display_unit'],displayUnit);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_display_to_source_scale'],scale);catch;end_try_catch
  try setappdata(ax,['gxtxt_' which '_display_to_source_offset'],offset);catch;end_try_catch
endfunction
function [vals,idx]=group_index(group)
  if(iscell(group)),vals=unique(group,'stable');idx=cell(numel(vals),1);for i=1:numel(vals),idx{i}=find(strcmp(group,vals{i}));endfor
  elseif(isnumeric(group)||islogical(group)),q=unique(group(isfinite(group)),'stable');vals=num2cell(q(:));idx=cell(numel(vals),1);for i=1:numel(vals),idx{i}=find(group(:)==vals{i});endfor
  else,error('GXTXT:AnalysisPlot','group must be numeric/logical/string');endif
endfunction
function s=group_label(v),if(isnumeric(v)||islogical(v)),s=sprintf('%.6g',v);else s=char(v);endif;endfunction

function s=level_axis_label(base,level)
  s=base;if(!isempty(level)),s=[base ' (' level ')'];endif
endfunction
