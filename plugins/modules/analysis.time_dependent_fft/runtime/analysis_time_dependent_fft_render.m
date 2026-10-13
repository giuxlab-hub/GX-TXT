function analysis_time_dependent_fft_render(outdir,cfg,D)
% Publish bounded cache-derived Datasets and persistent public Plot Variants.
% Full-resolution FFT publication and worker results are never read here.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isfield(D,'plot_cache')||!isfield(D,'dataset_id'))
    error('analysis.time_dependent_fft: compatible compact plot cache missing');
  endif
  if(exist('gxtxt_plot_dataset_v2','file')!=2)
    error('analysis.time_dependent_fft: public Plot Dataset bridge missing');
  endif
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('analysis.time_dependent_fft: Session path missing');endif
  numeric_api=tdfft_numeric_api(cfg);
  enabled=split_list(gxtxt_ini_get(cfg,'graph_provider.enabled', ...
    'analysis.time_dependent_fft.time_frequency_2d;analysis.time_dependent_fft.time_frequency_surface'));
  previous=read_manifest(fullfile(outdir,'automatic_graphs.ini'));
  entries={};scope=display_scope(cfg);
  window_graph='analysis.time_dependent_fft.window_spectra';selected=(1:D.window_count)';
  need_selected=any(strcmp(enabled,window_graph)) || ...
    strcmpi(strtrim(gxtxt_ini_get(cfg,'config.split_export','none')),'selected_windows') || ...
    strcmpi(strtrim(gxtxt_ini_get(cfg,'plot.analysis.time_dependent_fft.time_frequency_2d.window_scope','all')),'selected') || ...
    strcmpi(strtrim(gxtxt_ini_get(cfg,'plot.analysis.time_dependent_fft.time_frequency_surface.window_scope','all')),'selected');
  if(need_selected),selected=tdfft_select_windows(cfg,window_graph,D.time_centers,D.member_ids);endif
  index_path=fullfile(outdir,'window_plot_index.txt');
  write_text(index_path,sprintf('Individual window plot export is disabled or the Window spectrum plots graph is disabled.\n'));

  graph='analysis.time_dependent_fft.time_frequency_2d';
  if(any(strcmp(enabled,graph)))
    windows=overview_windows(cfg,graph,D,selected);
    maxw=nonnegative(cfg,graph,'max_windows',256);maxf=nonnegative(cfg,graph,'max_frequency_bins',2048);
    mode=reduction_mode(cfg,graph,'peak');G=tdfft_reduce_grid(D,windows,maxw,maxf,mode,numeric_api);
    dataset=tdfft_publish_display_dataset(session,D,[scope '.heatmap'],G,'grid',[]);
    spec=grid_spec(dataset,graph,cfg,'heatmap','Time-dependent FFT');
    result=provider_plot(session,spec,previous,'heatmap',scope);
    alias='01_time_frequency.png';copy_result(result,outdir,alias,format_choice(cfg,graph,'extra_format','none'));
    entries{end+1}=entry('heatmap',result,alias);
  endif

  graph='analysis.time_dependent_fft.time_frequency_surface';
  if(any(strcmp(enabled,graph)))
    windows=overview_windows(cfg,graph,D,selected);
    maxw=nonnegative(cfg,graph,'max_windows',128);maxf=nonnegative(cfg,graph,'max_frequency_bins',1024);
    mode=reduction_mode(cfg,graph,'mean');G=tdfft_reduce_grid(D,windows,maxw,maxf,mode,numeric_api);
    dataset=tdfft_publish_display_dataset(session,D,[scope '.surface'],G,'grid',[]);
    spec=grid_spec(dataset,graph,cfg,'surface','Time-dependent FFT - 3D surface');
    result=provider_plot(session,spec,previous,'surface',scope);
    alias='02_time_frequency_surface.png';copy_result(result,outdir,alias,format_choice(cfg,graph,'extra_format','none'));
    entries{end+1}=entry('surface',result,alias);
  endif

  if(any(strcmp(enabled,window_graph)))
    [window_entries,index_rows]=window_plots(session,outdir,cfg,D,selected,scope,previous,numeric_api);
    entries=[entries window_entries];
    write_window_index(index_path,index_rows);
  else
    cleanup_dir(fullfile(outdir,'window_plots'));
  endif
  write_manifest(fullfile(outdir,'automatic_graphs.ini'),entries);
endfunction

function [entries,index_rows]=window_plots(session,outdir,cfg,D,selected,scope,previous,numeric_api)
  graph='analysis.time_dependent_fft.window_spectra';entries={};index_rows={};
  maxf=nonnegative(cfg,graph,'max_frequency_bins',8192);
  G=tdfft_reduce_grid(D,selected,0,maxf,'peak',numeric_api);
  preview=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.preview_mode'],'first_selected')));
  if(!any(strcmp(preview,{'first_selected','overlay_selected'}))),preview='first_selected';endif
  labels=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.legend_label_mode'],'none')));
  datasets=cell(numel(selected),1);
  export_individual=bool_value(gxtxt_ini_get(cfg,['plot.' graph '.export_individual'],'1'));
  if(strcmp(preview,'overlay_selected')&&numel(selected)>256)
    error('TDFFT provider: overlay of %d windows exceeds the 256-series display limit; narrow the window selection or use first_selected',numel(selected));
  endif
  if(export_individual&&numel(selected)>4096)
    error('TDFFT provider: %d individual files exceed the 4096-file export limit; narrow the window selection',numel(selected));
  endif
  if(strcmp(preview,'first_selected')),preview_rows=1;else preview_rows=1:numel(selected);endif
  for q=preview_rows
    wi=selected(q);small=G;small.Z=G.Z(q,:);
    datasets{q}=tdfft_publish_display_dataset(session,D,sprintf('%s.window_%06d',scope,wi),small,'curve',wi);
  endfor
  series=cell(1,numel(preview_rows));
  for k=1:numel(preview_rows)
    q=preview_rows(k);wi=selected(q);
    series{k}=curve_series(datasets{q},wi,D,labels);
  endfor
  if(strcmp(preview,'first_selected'))
    wi=selected(1);title_text=expand_title(gxtxt_ini_get(cfg,['plot.' graph '.individual_title_template'],'FFT window {index} - t={time}'),wi,D.member_ids{wi},D.time_centers(wi));
  else
    title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Selected FFT windows'));
  endif
  spec=curve_spec(title_text,graph,cfg,series,format_choice(cfg,graph,'extra_format','none'));
  result=provider_plot(session,spec,previous,'window_preview',scope);
  alias='03_selected_window_spectra.png';copy_result(result,outdir,alias,format_choice(cfg,graph,'extra_format','none'));
  entries{end+1}=entry('window_preview',result,alias);

  if(export_individual)
    dirp=fullfile(outdir,'window_plots');cleanup_dir(dirp);mkdir(dirp);
    fmt=format_choice(cfg,graph,'individual_format','png');
    base=sanitize(gxtxt_ini_get(cfg,['plot.' graph '.individual_basename'],'fft_window'));
    template=gxtxt_ini_get(cfg,['plot.' graph '.individual_title_template'],'FFT window {index} - t={time}');
    for q=1:numel(selected)
      wi=selected(q);key=sprintf('window_%06d',wi);
      if(isempty(datasets{q}))
        small=G;small.Z=G.Z(q,:);
        datasets{q}=tdfft_publish_display_dataset(session,D,sprintf('%s.window_%06d',scope,wi),small,'curve',wi);
      endif
      title_text=expand_title(template,wi,D.member_ids{wi},D.time_centers(wi));
      extra='none';if(!strcmp(fmt,'png')),extra=fmt;endif
      spec=curve_spec(title_text,graph,cfg,{curve_series(datasets{q},wi,D,labels)},extra);
      result=provider_plot(session,spec,previous,key,scope);
      filename=sprintf('%s_%04d.%s',base,wi,fmt);
      source=result.artifact;if(!strcmp(fmt,'png')),source=[source(1:end-4) '.' fmt];endif
      if(exist(source,'file')!=2),error('TDFFT provider: individual %s export missing',fmt);endif
      [ok,msg]=copyfile(source,fullfile(dirp,filename),'f');if(!ok),error('TDFFT provider: individual copy failed: %s',msg);endif
      if(strcmp(fmt,'png')),entries{end+1}=entry(key,result,fullfile('window_plots',filename));endif
      index_rows{end+1}=struct('window',wi,'member',D.member_ids{wi},'time',D.time_centers(wi),'file',fullfile('window_plots',filename));
    endfor
  else
    cleanup_dir(fullfile(outdir,'window_plots'));
  endif
endfunction

function spec=grid_spec(dataset,graph,cfg,plot_type,default_title)
  title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],default_title));
  config=struct('plot_type',plot_type,'reduction_mode','none', ...
    'extra_format',format_choice(cfg,graph,'extra_format','none'));
  for key={'x_label','y_label','z_label'}
    name=key{1};raw=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' name],'auto'));
    if(!isempty(raw)&&!strcmpi(raw,'auto')),config.(name)=raw;endif
  endfor
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_3d', ...
    'graph_id','plot.dataset.xyz','dataset_id',dataset,'x_variable_id','time', ...
    'y_variable_id','frequency','z_variable_id','spectral_value', ...
    'title',title_text,'config',config);
endfunction

function spec=curve_spec(title_text,graph,cfg,series,extra)
  xlabel_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.x_label'],'auto'));
  ylabel_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.y_label'],'auto'));
  x=struct();y=struct();if(!isempty(xlabel_text)&&!strcmpi(xlabel_text,'auto')),x.label=xlabel_text;endif
  if(!isempty(ylabel_text)&&!strcmpi(ylabel_text,'auto')),y.label=ylabel_text;endif
  axes=struct('x',x,'y_left',y);
  panel=struct('id','main','title',title_text,'axes',axes,'series',{series});
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d', ...
    'graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()), ...
    'panels',{{panel}},'output',struct('extra_format',extra));
endfunction

function s=curve_series(dataset,wi,D,mode)
  label=window_label(mode,wi,D.time_centers(wi),D.time_unit);
  if(isempty(label)),label=sprintf('Window %d',wi);endif
  s=struct('id',sprintf('window_%06d',wi),'dataset_id',dataset, ...
    'x_variable_id','frequency','y_variable_id','spectral_value', ...
    'axis','left','kind','line','label',label);
endfunction

function result=provider_plot(session,spec,previous,key,scope)
  graph=spec.graph_id;variant='';
  for i=1:numel(previous)
    if(strcmp(previous{i}.key,key)&&strcmp(previous{i}.graph_id,graph))
      variant=previous{i}.variant_id;break;
    endif
  endfor
  options=struct('action','ensure','kind','variant', ...
    'provider_key',['analysis.time_dependent_fft:' scope ':' key], ...
    'graph_id',graph,'variant_id',variant,'render',true);
  result=gxtxt_plot_dataset_v2(session,spec,options);
  if(!isfield(result,'artifact')||exist(result.artifact,'file')!=2),error('TDFFT provider: graph artifact missing');endif
endfunction

function copy_result(result,outdir,name,extra)
  [ok,msg]=copyfile(result.artifact,fullfile(outdir,name),'f');
  if(!ok),error('TDFFT provider: graph copy failed: %s',msg);endif
  if(any(strcmp(extra,{'svg','pdf'})))
    source=[result.artifact(1:end-4) '.' extra];
    if(exist(source,'file')==2)
      [~,base,~]=fileparts(name);
      [ok,msg]=copyfile(source,fullfile(outdir,[base '.' extra]),'f');
      if(!ok),error('TDFFT provider: extra export copy failed: %s',msg);endif
    endif
  endif
endfunction

function e=entry(key,result,png)
  e=struct('key',key,'graph_id',result.graph_id,'variant_id',result.variant_id, ...
    'png',png,'artifact',result.artifact);
endfunction
function prior=read_manifest(path)
  prior={};if(exist(path,'file')!=2),return;endif
  data=gxtxt_ini_read(path);if(!strcmp(gxtxt_ini_get(data,'automatic_graphs.provider',''),'plot.dataset')),return;endif
  n=str2double(gxtxt_ini_get(data,'automatic_graphs.count','0'));
  if(!isfinite(n)||n<0||n>10000),return;endif
  for i=1:n
    section=sprintf('graph.%02d',i);
    prior{end+1}=struct('key',gxtxt_ini_get(data,[section '.key'],''), ...
      'graph_id',gxtxt_ini_get(data,[section '.graph_id'],''), ...
      'variant_id',gxtxt_ini_get(data,[section '.variant_id'],''));
  endfor
endfunction
function write_manifest(path,entries)
  fd=fopen(path,'w');if(fd<0),error('TDFFT provider: cannot write graph manifest');endif
  unwind_protect
    fprintf(fd,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n',numel(entries));
    for i=1:numel(entries)
      e=entries{i};fprintf(fd,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n', ...
        i,e.key,e.graph_id,e.variant_id,e.png,e.artifact);
    endfor
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
endfunction
function write_window_index(path,rows)
  fd=fopen(path,'w');if(fd<0),error('TDFFT provider: cannot write window index');endif
  unwind_protect
    if(isempty(rows)),fprintf(fd,'Individual window plot export is disabled.\n');else
      fprintf(fd,'window_index\tmember_id\ttime\tfile\n');
      for i=1:numel(rows)
        r=rows{i};fprintf(fd,'%d\t%s\t%.17g\t%s\n',r.window,r.member,r.time,r.file);
      endfor
    endif
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
endfunction
function value=display_scope(cfg)
  value=strtrim(gxtxt_ini_get(cfg,'plot_variant.variant_id',''));
  if(isempty(value)),value='base';endif
  value=sanitize(value);
endfunction
function idx=overview_windows(cfg,graph,D,selected)
  scope=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.window_scope'],'all')));
  if(strcmp(scope,'selected')),idx=selected;else idx=(1:D.window_count)';endif
endfunction
function n=nonnegative(cfg,graph,key,def)
  n=str2double(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' key],num2str(def))));
  if(!isfinite(n)||n<0||n!=fix(n)),n=def;endif
endfunction
function mode=reduction_mode(cfg,graph,def)
  mode=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.reduction'],def)));
  if(!any(strcmp(mode,{'peak','mean'}))),mode=def;endif
endfunction
function fmt=format_choice(cfg,graph,key,def)
  fmt=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' key],def)));
  if(!any(strcmp(fmt,{'none','png','svg','pdf'}))),fmt=def;endif
endfunction
function tf=bool_value(raw),tf=any(strcmpi(strtrim(raw),{'1','true','yes','on'}));endfunction
function s=window_label(mode,idx,t,unit)
  switch mode
    case 'index',s=sprintf('#%d',idx);
    case 'time',s=sprintf('t=%.6g %s',t,unit);
    case 'index_time',s=sprintf('#%d, t=%.6g %s',idx,t,unit);
    otherwise,s='';
  endswitch
endfunction
function s=expand_title(tpl,idx,member_id,t)
  s=strrep(tpl,'{index}',num2str(idx));s=strrep(s,'{member_id}',member_id);s=strrep(s,'{time}',sprintf('%.9g',t));
endfunction
function s=sanitize(s),s=regexprep(strtrim(s),'[^A-Za-z0-9_.-]','_');if(isempty(s)),s='plot';endif;endfunction
function cleanup_dir(path),if(exist(path,'dir')==7),rmdir(path,'s');endif;endfunction
function write_text(path,value)
  fd=fopen(path,'w');if(fd<0),error('TDFFT provider: cannot write %s',path);endif
  unwind_protect fputs(fd,value);unwind_protect_cleanup fclose(fd);end_unwind_protect
endfunction
function out=split_list(value)
  value=strrep(value,',',';');if(isempty(strtrim(value))),out={};return;endif
  out=strsplit(value,';');out=cellfun(@strtrim,out,'UniformOutput',false);out=out(!cellfun(@isempty,out));
endfunction
