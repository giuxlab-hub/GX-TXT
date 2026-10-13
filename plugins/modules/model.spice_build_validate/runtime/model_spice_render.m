function model_spice_render(outdir,cfg,c)
% SPICE verification graphs through canonical derived Datasets and Plot.dataset.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_spice_ini_get(cfg,'runtime.session',''));
  if(isempty(session)||exist(fullfile(session,'metadata','manifest.ini'),'file')!=2),return;endif
  D=spice_publish(session,c);
  enabled=spice_list(gxtxt_spice_ini_get(cfg,'graph_provider.enabled', ...
    'model.spice.overlay;model.spice.residuals;model.spice.parity'));
  items={};
  if(spice_has(enabled,'model.spice.overlay'))
    graph='model.spice.overlay';profile=lower(strtrim(gxtxt_spice_ini_get(cfg,['plot.' graph '.profile'],'x_sweep')));
    if(strcmp(profile,'validation')&&!D.has_validation),profile='x_sweep';endif
    if(!isfield(D.profiles,profile)),error('model.spice.overlay: profile %s unavailable',profile);endif
    P=D.profiles.(profile);axes=spice_axes(cfg,graph,P.hname,spice_y_label(c));
    series=spice_overlay_series(cfg,graph,P.id,false,P.roles,P.has_measured);
    items{end+1}=spice_item('overlay',graph,cfg,axes,series,{},'01_spice_overlay.png');
  endif
  if(spice_has(enabled,'model.spice.residuals'))
    graph='model.spice.residuals';profile=lower(strtrim(gxtxt_spice_ini_get(cfg,['plot.' graph '.profile'],'x_sweep')));
    if(strcmp(profile,'validation')&&!D.has_validation),profile='x_sweep';endif
    if(!isfield(D.profiles,profile)),error('model.spice.residuals: profile %s unavailable',profile);endif
    P=D.profiles.(profile);axes=spice_axes(cfg,graph,P.hname,['Residual ' spice_y_label(c)]);
    series={spice_family('sa',P.id,'horizontal','residual_sa','SPICE - analytical','line_marker',struct('marker','circle'))};
    if(P.has_measured&&spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_spice_measured'],'1'),true))
      series{end+1}=spice_series('sm',P.id,'horizontal','residual_sm','SPICE - measured','scatter',struct('marker','square','color','#555555'));
    endif
    ann=spice_zero(cfg,graph);items{end+1}=spice_item('residuals',graph,cfg,axes,series,ann,'02_spice_residuals.png');
  endif
  if(spice_has(enabled,'model.spice.parity'))
    graph='model.spice.parity';axes=spice_axes(cfg,graph,'Analytical prediction','SPICE prediction');
    if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.same_axis_range'],'1'),true))
      axes.x.min=D.parity_min;axes.x.max=D.parity_max;
      axes.y_left.min=D.parity_min;axes.y_left.max=D.parity_max;
    endif
    series={spice_series('parity',D.parity,'analytical','spice','SPICE vs analytical','scatter',struct('marker','circle')), ...
      spice_series('identity',D.identity,'analytical','identity','Identity','line',struct('line_style','dashed'))};
    items{end+1}=spice_item('parity',graph,cfg,axes,series,{},'03_spice_parity.png');
  endif
  optional={'validation_overlay','04_spice_validation_overlay.png'; ...
    'validation_residuals','05_spice_validation_residuals.png'; ...
    'validation_domain','06_spice_validation_domain.png'};
  for j=1:rows(optional)
    key=optional{j,1};graph=['model.spice.' key];if(!spice_has(enabled,graph)),continue;endif
    if(!D.has_validation)
      axes=struct('x',struct('label',''),'y_left',struct('label',''));
      series={spice_series('empty',D.empty,'x','y','No data','scatter',struct())};
      note={struct('type','text','axis','left','x',0.5,'y',0.5, ...
        'label','No measured validation Dataset selected for this run.')};
      items{end+1}=spice_item(key,graph,cfg,axes,series,note,optional{j,2});continue;
    endif
    P=D.profiles.validation;
    if(strcmp(key,'validation_overlay'))
      axes=spice_axes(cfg,graph,P.hname,spice_y_label(c));
      series=spice_overlay_series(cfg,graph,P.id,true,P.roles,P.has_measured);
      title_override=spice_validation_title(cfg,graph,c,'Measured validation vs SPICE');
      items{end+1}=spice_item(key,graph,cfg,axes,series,{},optional{j,2},title_override);
    elseif(strcmp(key,'validation_residuals'))
      mode=lower(strtrim(gxtxt_spice_ini_get(cfg,['plot.' graph '.residual_mode'],'absolute')));
      if(strcmp(mode,'relative_percent')&&P.has_relative),yid='relative_sm';yl='SPICE - measured [%]';roles=P.relative_roles;
      else yid='residual_sm';yl=['SPICE - measured ' spice_y_label(c)];roles=P.roles;endif
      axes=spice_axes(cfg,graph,P.hname,yl);
      series={spice_family('residual',P.id,'horizontal',yid,'Validation residual','line',struct())};
      if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_domain_classification'],'1'),true))
        series=[series,spice_role_series(P.id,'horizontal',yid,roles)];
      else series{end+1}=spice_series('observations',P.id,'horizontal',yid,'Measured validation','scatter',struct('color','#555555'));endif
      ann=spice_zero(cfg,graph);title_override=spice_validation_title(cfg,graph,c,'SPICE - measured validation residuals');
      items{end+1}=spice_item(key,graph,cfg,axes,series,ann,optional{j,2},title_override);
    else
      axes=spice_axes(cfg,graph,P.xname,P.fname);series={};
      if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_domain_boundary'],'1'),true)&&D.has_boundary)
        series{end+1}=spice_series('boundary',D.boundary,'model_x','model_family','Training-domain boundary','line',struct('line_width',1.5));
      endif
      series=[series,spice_role_series(P.id,'model_x','model_family',P.roles)];
      title_override=spice_validation_title(cfg,graph,c,'Validation points in mathematical-model input domain');
      items{end+1}=spice_item(key,graph,cfg,axes,series,{},optional{j,2},title_override);
    endif
  endfor
  gxtxt_plot_provider_render_v1(session,outdir,'model.spice_build_validate',items,'base');
endfunction

function D=spice_publish(session,c)
  D=struct('profiles',struct(),'has_validation',false,'has_boundary',false);
  profiles={'x_sweep','family_sweep','validation'};
  for p=1:numel(profiles)
    key=profiles{p};if(strcmp(key,'validation')),idx=find(strcmp(c.comparison,'measured_validation'));else idx=find(strcmp(c.profile,key));endif
    if(isempty(idx)),continue;endif
    [h,g,hname,xname,fname]=spice_presentation(c,idx,key);
    [~,ord]=sortrows([g(:),h(:)],[1,2]);idx=idx(ord);h=h(ord);g=g(ord);
    n=numel(idx);roles=c.domain_role(idx);role_ids={'in_domain','out_of_domain','unknown'};
    measured=c.measured_y(idx);rsm=c.residual_spice_measured(idx);
    rel=NaN(n,1);if(isfield(c,'relative_residual_spice_measured_percent')),rel=c.relative_residual_spice_measured_percent(idx);endif
    cols={'horizontal',h(:),'independent';'group',g(:),'family'; ...
      'model_x',c.input_x(idx),'independent';'model_family',c.input_family(idx),'derived'; ...
      'measured',measured,'measured';'analytical',c.analytical_y(idx),'derived'; ...
      'spice',c.spice_y(idx),'derived';'residual_sa',c.residual_spice_analytical(idx),'residual'; ...
      'residual_sm',rsm,'residual';'relative_sm',rel,'residual'};
    for r=1:3
      v=NaN(n,1);v(strcmp(roles,role_ids{r}))=measured(strcmp(roles,role_ids{r}));
      cols(end+1,:)={['measured_' role_ids{r}],v,'measured'};
      v=NaN(n,1);v(strcmp(roles,role_ids{r}))=rsm(strcmp(roles,role_ids{r}));
      cols(end+1,:)={['residual_' role_ids{r}],v,'residual'};
      v=NaN(n,1);v(strcmp(roles,role_ids{r}))=rel(strcmp(roles,role_ids{r}));
      cols(end+1,:)={['relative_' role_ids{r}],v,'residual'};
      v=NaN(n,1);v(strcmp(roles,role_ids{r}))=c.input_family(idx(strcmp(roles,role_ids{r})));
      cols(end+1,:)={['family_' role_ids{r}],v,'derived'};
    endfor
    id=['spice.plot.' key];spice_table(session,id,cols);
    present={};relative_roles={};for r=1:3
      mask=strcmp(roles,role_ids{r});
      if(any(mask)),present{end+1}=role_ids{r};endif
      if(any(mask&isfinite(rel))),relative_roles{end+1}=role_ids{r};endif
    endfor
    D.profiles.(key)=struct('id',id,'hname',hname,'gname',xname,'xname',spice_name(c,key,'x'),'fname',spice_name(c,key,'family'),'roles',{present},'relative_roles',{relative_roles},'has_relative',any(isfinite(rel)),'has_measured',any(isfinite(measured)));
    if(strcmp(key,'validation')),D.has_validation=true;endif
  endfor
  idx=find(strcmp(c.comparison,'verification'));
  if(isempty(idx)),error('model.spice_build_validate: no verification rows for parity');endif
  a=c.analytical_y(idx);s=c.spice_y(idx);D.parity_min=min([a(:);s(:)]);D.parity_max=max([a(:);s(:)]);
  if(D.parity_max<=D.parity_min),D.parity_min-=1;D.parity_max+=1;endif
  D.parity='spice.plot.parity';spice_table(session,D.parity,{'analytical',a(:),'independent';'spice',s(:),'derived'});
  D.identity='spice.plot.identity';spice_table(session,D.identity,{'analytical',[D.parity_min;D.parity_max],'independent';'identity',[D.parity_min;D.parity_max],'reference'});
  D.empty='spice.plot.empty';spice_table(session,D.empty,{'x',[0;1],'independent';'y',[0;1],'reference'});
  if(isfield(c,'domain_vertices')&&isnumeric(c.domain_vertices)&&rows(c.domain_vertices)>=3&&columns(c.domain_vertices)>=2)
    v=c.domain_vertices(:,1:2);D.boundary='spice.plot.boundary';
    spice_table(session,D.boundary,{'model_x',[v(:,1);v(1,1)],'independent';'model_family',[v(:,2);v(1,2)],'derived'});
    D.has_boundary=true;
  endif
endfunction

function [h,g,hname,gname,fname]=spice_presentation(c,idx,profile)
  x=c.input_x(idx);f=c.input_family(idx);fname=c.model_family_name;
  if(strcmp(profile,'family_sweep')),h=f;g=x;hname=c.model_family_name;gname=c.model_x_name;
  elseif(strcmp(profile,'validation')&&numel(unique(f))>numel(unique(x)))
    h=f;g=x;hname=spice_name(c,profile,'family');gname=spice_name(c,profile,'x');
  else h=x;g=f;hname=spice_name(c,profile,'x');gname=spice_name(c,profile,'family');endif
endfunction
function s=spice_name(c,profile,which)
  field=['model_' which '_name'];if(strcmp(profile,'validation')),vfield=['validation_' which '_name'];
    if(isfield(c,vfield)&&!isempty(strtrim(c.(vfield)))),s=c.(vfield);return;endif
  endif
  s=c.(field);
endfunction
function spice_table(session,id,cols)
  opts=struct('storage','auto','replace_owned',true,'producer_version','3', ...
    'provenance','SPICE verification graph display data');
  P=struct();opened=false;finalized=false;
  try
    P=gxtxt_publication_v2_open(session,'model.spice_build_validate',id,'table.generic',opts);opened=true;
    P=gxtxt_publication_v2_declare_dimension(P,'row',0,true);
    for j=1:rows(cols)
      name=cols{j,1};spec=struct('dtype','float64','dimension_ids','row', ...
        'name',name,'unit','','semantic_role',cols{j,3},'axis_kind','explicit');
      if(j==1),spec.coordinate_role='coordinate';else spec.coordinate_role='data';spec.coordinate_variable_ids=cols{1,1};endif
      P=gxtxt_publication_v2_declare_variable(P,name,spec);
    endfor
    n=numel(cols{1,2});for first=1:50000:n
      last=min(n,first+49999);items=cell(rows(cols),2);
      for j=1:rows(cols),items{j,1}=cols{j,1};v=cols{j,2};items{j,2}=v(first:last);endfor
      P=gxtxt_publication_v2_append(P,'row',items);
    endfor
    [P,~]=gxtxt_publication_v2_finalize(P);opened=false;finalized=true;
  catch err
    if(opened&&!finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    rethrow(err);
  end_try_catch
endfunction

function series=spice_overlay_series(cfg,graph,id,validation,roles,has_measured)
  series={};
  if(has_measured&&spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_measured'],'1'),true))
    if(validation&&spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_domain_classification'],'1'),true))
      series=[series,spice_role_series(id,'horizontal','measured',roles)];
    else series{end+1}=spice_series('measured',id,'horizontal','measured','Measured','scatter',struct('color','#555555','marker','circle'));endif
  endif
  if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_analytical'],'1'),true))
    series{end+1}=spice_family('analytical',id,'horizontal','analytical','Analytical','line',struct('line_style','dashed','color','#777777'));
  endif
  if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_spice'],'1'),true))
    series{end+1}=spice_family('spice',id,'horizontal','spice','SPICE','line',struct());
  endif
endfunction
function out=spice_role_series(id,x,y,allowed)
  roles={'in_domain','out_of_domain','unknown'};labels={'In-domain','Out-of-domain','Domain unknown'};
  colors={'#555555','#d62728','#888888'};markers={'circle','x','square'};out={};
  for k=1:3
    role=roles{k};if(!any(strcmp(allowed,role))),continue;endif
    yid=[y '_' role];if(strcmp(y,'model_family')),yid=['family_' role];endif
    if(strcmp(y,'residual_sm')),yid=['residual_' role];endif
    if(strcmp(y,'relative_sm')),yid=['relative_' role];endif
    out{end+1}=spice_series(role,id,x,yid,labels{k},'scatter',struct('color',colors{k},'marker',markers{k}));
  endfor
endfunction
function s=spice_family(id,dataset,x,y,label,kind,style)
  s=spice_series(id,dataset,x,y,label,kind,style);s.family_variable_id='group';s.family_label_prefix=label;
endfunction
function s=spice_series(id,dataset,x,y,label,kind,style)
  s=struct('id',id,'dataset_id',dataset,'x_variable_id',x,'y_variable_id',y, ...
    'axis','left','kind',kind,'label',label,'style',style);
endfunction
function out=spice_item(key,graph,cfg,axes,series,annotations,png,varargin)
  title_text=gxtxt_spice_ini_get(cfg,['plot.' graph '.title'],spice_title(graph));
  if(!isempty(varargin)),title_text=varargin{1};endif
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series},'annotations',{annotations});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format','none'));
  out=struct('key',key,'spec',spec,'png',png);
endfunction
function axes=spice_axes(cfg,graph,xdefault,ydefault)
  xl=gxtxt_spice_ini_get(cfg,['plot.' graph '.x_label'],'auto');
  yl=gxtxt_spice_ini_get(cfg,['plot.' graph '.y_label'],'auto');
  if(strcmpi(strtrim(xl),'auto')),xl=strrep(xdefault,'_',' ');endif
  if(strcmpi(strtrim(yl),'auto')),yl=strrep(ydefault,'_',' ');endif
  axes=struct('x',struct('label',xl),'y_left',struct('label',yl));
  fields={'x','x_min','x_max';'y_left','y_min','y_max'};
  for j=1:rows(fields)
    a=fields{j,1};lo=str2double(gxtxt_spice_ini_get(cfg,['plot.' graph '.' fields{j,2}],''));
    hi=str2double(gxtxt_spice_ini_get(cfg,['plot.' graph '.' fields{j,3}],''));
    if(isfinite(lo)&&isfinite(hi)&&hi>lo),axes.(a).min=lo;axes.(a).max=hi;endif
  endfor
endfunction
function out=spice_zero(cfg,graph)
  out={};if(spice_bool(gxtxt_spice_ini_get(cfg,['plot.' graph '.show_zero_line'],'1'),true))
    out={struct('type','reference_line','axis','left','value',0,'line_style','dashed')};endif
endfunction
function s=spice_validation_title(cfg,graph,c,def)
  s=gxtxt_spice_ini_get(cfg,['plot.' graph '.title'],def);
  if(isfield(c,'validation_dataset_role')&&!isempty(c.validation_dataset_role))
    s=[s ' (' strrep(c.validation_dataset_role,'_',' ') ')'];endif
endfunction
function s=spice_y_label(c)
  s=strrep(c.model_y_name,'_',' ');if(isfield(c,'model_y_unit')&&!isempty(c.model_y_unit)),s=[s ' [' c.model_y_unit ']'];endif
endfunction
function s=spice_title(graph)
  names=struct('overlay','SPICE model validation - overlay','residuals','SPICE model residuals', ...
    'parity','Analytical vs SPICE parity','validation_overlay','Measured validation vs SPICE', ...
    'validation_residuals','SPICE measured validation residuals', ...
    'validation_domain','Validation points in model domain');
  key=strrep(graph,'model.spice.','');if(isfield(names,key)),s=names.(key);else s=graph;endif
endfunction
function a=spice_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif,endfunction
function b=spice_bool(s,def),s=lower(strtrim(s));if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif,endfunction
function b=spice_has(a,s),b=any(strcmp(a,s));endfunction
