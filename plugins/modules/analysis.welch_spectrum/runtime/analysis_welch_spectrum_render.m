function analysis_welch_spectrum_render(outdir,cfg,D)
% Persist Welch presentation through the public Dataset Plot provider.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isfield(D,'statistical_result')),error('Welch: legacy cache has no captured CORE statistical result; recalculate explicitly');endif
  statistics=gxtxt_statistics_v1('validated_result',D.statistical_result);
  fields=gxtxt_statistics_v1('numeric_fields',statistics);
  graph='analysis.welch_spectrum.spectrum';
  enabled=strtrim(gxtxt_ini_get(cfg,'graph_provider.enabled',graph));
  if(isempty(enabled)||isempty(strfind([';' strrep(enabled,',',';') ';'],[';' graph ';']))),return;endif
  if(exist('gxtxt_plot_dataset_v2','file')!=2),error('Welch: public PLOT_DATASET_API_v2 bridge missing');endif
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(session)||!isfield(D,'dataset_id')||isempty(D.dataset_id)),error('Welch: published Dataset identity missing');endif
  quantity=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.quantity'],'psd_db')));
  switch quantity
    case 'psd_linear',variable='psd';unit=D.psd_unit;ylabel='Power spectral density';
    case 'asd',variable='asd';unit=D.asd_unit;ylabel='Amplitude spectral density';
    case 'mean_amplitude',variable='mean_amplitude';unit=D.signal_unit;ylabel='Mean segment amplitude';
    otherwise,variable='psd_db';unit='dB';ylabel='PSD';
  endswitch
  xscale=scale_value(cfg,graph,'x_scale');yscale=scale_value(cfg,graph,'y_scale');
  render=true;reason='';
  if(strcmp(variable,'psd_db')&&fields.zero_level_bins.value==fields.bin_count.value),render=false;reason='Zero PSD has no finite logarithmic level relative to the unit PSD reference';endif
  title_text=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.title'],'Welch averaged spectrum'));
  if(!render),title_text=[title_text ' — unavailable: zero PSD'];endif
  xlabel_text=axis_label(cfg,graph,'x_label','Frequency','Hz');
  ylabel_text=axis_label(cfg,graph,'y_label',ylabel,unit);
  axes=struct('x',struct('label',xlabel_text,'display_unit','Hz','scale',xscale), ...
    'y_left',struct('label',ylabel_text,'display_unit',unit,'scale',yscale));
  series=struct('id','welch_spectrum','dataset_id',D.dataset_id,'x_variable_id','frequency', ...
    'y_variable_id',variable,'axis','left','kind','line','label',ylabel);
  panel=struct('id','main','title',title_text,'axes',axes,'series',{{series}});
  fmt=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.extra_format'],'none')));
  if(!any(strcmp(fmt,{'none','svg','pdf'}))),fmt='none';endif
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy', ...
    'title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct('extra_format',fmt));
  old=fullfile(outdir,'automatic_graphs.ini');variant='';
  if(exist(old,'file')==2)
    prior=gxtxt_ini_read(old);
    if(strcmp(gxtxt_ini_get(prior,'automatic_graphs.provider',''),'plot.dataset') && ...
       strcmp(gxtxt_ini_get(prior,'graph.01.graph_id',''),'plot.dataset.xy'))
      variant=strtrim(gxtxt_ini_get(prior,'graph.01.variant_id',''));
    endif
  endif
  options=struct('action','ensure','kind','variant','provider_key','analysis.welch_spectrum:welch_spectrum', ...
    'variant_id',variant,'render',render);
  result=gxtxt_plot_dataset_v2(session,spec,options);
  destination=fullfile(outdir,'01_welch_spectrum.png');png='';status='unavailable';artifact='';
  if(render)
    if(!isfield(result,'artifact')||exist(result.artifact,'file')!=2),error('Welch: provider graph artifact missing');endif
    [ok,msg]=copyfile(result.artifact,destination,'f');
    if(!ok),error('Welch: graph copy failed: %s',msg);endif
    png='01_welch_spectrum.png';status='rendered';artifact=result.artifact;
  elseif(exist(destination,'file')==2)
    history=fullfile(outdir,'previous_graphs',sprintf('%s_%d',datestr(now(),'yyyymmddTHHMMSSFFF'),getpid()));mkdir(history);
    [ok,msg]=movefile(destination,fullfile(history,'01_welch_spectrum.png'));
    if(!ok),error('Welch: cannot preserve previous graph: %s',msg);endif
  endif
  fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');if(fid<0),error('Welch: graph manifest could not be written');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=1\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n');
    fprintf(fid,'\n[graph.01]\nkey=welch_spectrum\ngraph_id=%s\nvariant_id=%s\nrender_status=%s\nreason=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant when finite data are available\n', ...
      result.graph_id,result.variant_id,status,reason,png,artifact);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function value=scale_value(cfg,graph,key)
  value=lower(strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' key],'linear')));
  if(!any(strcmp(value,{'linear','log'}))),value='linear';endif
endfunction
function value=axis_label(cfg,graph,key,name,unit)
  value=strtrim(gxtxt_ini_get(cfg,['plot.' graph '.' key],'auto'));
  if(isempty(value)||strcmpi(value,'auto'))
    if(isempty(unit)||strcmp(unit,'1')),value=name;else value=sprintf('%s [%s]',name,unit);endif
  endif
endfunction
