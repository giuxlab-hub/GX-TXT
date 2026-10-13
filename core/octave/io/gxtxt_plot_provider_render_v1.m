function entries=gxtxt_plot_provider_render_v1(session,outdir,module_id,items,scope,append_existing)
% Render module-owned Dataset PlotSpecs through persistent public variants.
% Items are structs with key, spec, png and optional extra_format.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<5||isempty(scope)),scope='base';endif
  if(nargin<6),append_existing=false;endif
  if(!iscell(items)),error('GXTXT:PlotProvider','items must be a cell array');endif
  manifest=fullfile(outdir,'automatic_graphs.ini');prior=struct();
  if(exist(manifest,'file')==2),prior=gxtxt_ini_read(manifest);endif
  entries=cell(1,numel(items));
  for i=1:numel(items)
    item=items{i};key=item.key;spec=item.spec;png=item.png;
    if(isempty(regexp(key,'^[A-Za-z0-9_.-]+$','once'))||isempty(regexp(scope,'^[A-Za-z0-9_.-]+$','once')))
      error('GXTXT:PlotProvider','invalid stable graph key or scope');
    endif
    if(isempty(regexp(png,'^[A-Za-z0-9_.-]+\.png$','once')))
      error('GXTXT:PlotProvider','PNG alias must be a simple filename');
    endif
    graph=spec.graph_id;variant='';n=str2double(gxtxt_ini_get(prior,'automatic_graphs.count','0'));
    if(isfinite(n)&&n>=0&&n<=10000)
      for j=1:n
        section=sprintf('graph.%02d',j);
        prior_scope=gxtxt_ini_get(prior,[section '.scope'],'base');
        if(strcmp(gxtxt_ini_get(prior,[section '.key'],''),key)&& ...
           strcmp(gxtxt_ini_get(prior,[section '.graph_id'],''),graph)&&strcmp(prior_scope,scope))
          variant=strtrim(gxtxt_ini_get(prior,[section '.variant_id'],''));break;
        endif
      endfor
    endif
    options=struct('action','ensure','kind','variant','graph_id',graph, ...
      'variant_id',variant,'provider_key',[module_id ':' scope ':' key],'render',true);
    result=gxtxt_plot_dataset_v2(session,spec,options);
    if(exist(result.artifact,'file')!=2),error('GXTXT:PlotProvider','provider artifact missing: %s',result.artifact);endif
    [ok,msg]=copyfile(result.artifact,fullfile(outdir,png),'f');
    if(!ok),error('GXTXT:PlotProvider','PNG alias copy failed: %s',msg);endif
    if(isfield(item,'extra_format')&&any(strcmp(item.extra_format,{'svg','pdf'})))
      source=[result.artifact(1:end-4) '.' item.extra_format];
      if(exist(source,'file')!=2),error('GXTXT:PlotProvider','provider %s artifact missing',item.extra_format);endif
      [~,base,~]=fileparts(png);
      [ok,msg]=copyfile(source,fullfile(outdir,[base '.' item.extra_format]),'f');
      if(!ok),error('GXTXT:PlotProvider','vector alias copy failed: %s',msg);endif
    endif
    entries{i}=struct('key',key,'scope',scope,'graph_id',result.graph_id,'variant_id',result.variant_id, ...
      'png',png,'artifact',result.artifact);
  endfor
  if(append_existing)
    old={};n=str2double(gxtxt_ini_get(prior,'automatic_graphs.count','0'));
    if(!isfinite(n)||n<0||n>10000),error('GXTXT:PlotProvider','invalid prior graph manifest count');endif
    for j=1:n
      sec=sprintf('graph.%02d',j);key=gxtxt_ini_get(prior,[sec '.key'],'');
      prior_scope=gxtxt_ini_get(prior,[sec '.scope'],'base');
      replaced=false;
      for q=1:numel(entries)
        if(strcmp(key,entries{q}.key)&&strcmp(prior_scope,entries{q}.scope)),replaced=true;break;endif
      endfor
      if(replaced),continue;endif
      e=struct('key',key,'scope',prior_scope, ...
        'graph_id',gxtxt_ini_get(prior,[sec '.graph_id'],''), ...
        'variant_id',gxtxt_ini_get(prior,[sec '.variant_id'],''), ...
        'png',gxtxt_ini_get(prior,[sec '.png'],''), ...
        'artifact',gxtxt_ini_get(prior,[sec '.provider_artifact'],''), ...
        'title',gxtxt_ini_get(prior,[sec '.title'],''), ...
        'group',gxtxt_ini_get(prior,[sec '.group'],''));
      if(!isempty(e.graph_id)&&!isempty(e.variant_id)&&!isempty(e.png)),old{end+1}=e;endif
    endfor
    entries=[old entries];
  endif
  temp=[manifest '.tmp'];fd=fopen(temp,'w');if(fd<0),error('GXTXT:PlotProvider','cannot write graph manifest');endif
  unwind_protect
    fprintf(fd,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n',numel(entries));
    for i=1:numel(entries)
      e=entries{i};fprintf(fd,'\n[graph.%02d]\nkey=%s\nscope=%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n', ...
        i,e.key,e.scope,e.graph_id,e.variant_id,e.png,e.artifact);
      if(isfield(e,'title')&&!isempty(e.title)),fprintf(fd,'title=%s\n',e.title);endif
      if(isfield(e,'group')&&!isempty(e.group)),fprintf(fd,'group=%s\n',e.group);endif
    endfor
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
  [ok,msg]=movefile(temp,manifest,'f');if(!ok),error('GXTXT:PlotProvider','graph manifest replacement failed: %s',msg);endif
endfunction
