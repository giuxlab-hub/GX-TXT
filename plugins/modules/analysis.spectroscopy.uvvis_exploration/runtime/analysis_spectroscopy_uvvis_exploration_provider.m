function analysis_spectroscopy_uvvis_exploration_provider(mode,unit,outdir,cfg)
% Publish persistent graphs through the public Dataset Plot API.
% SPDX-License-Identifier: GPL-3.0-or-later
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  source=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(session)||isempty(source)),error('UV/Vis provider: Session or primary Dataset missing');endif
  if(exist('gxtxt_plot_dataset_v2','file')!=2),error('UV/Vis provider: public PLOT_DATASET_API_v2 bridge missing');endif
  result={};names={};keys={};
  if(strcmp(mode,'single_spectrum'))
    processed=[source '.uvvis.processed'];original=[source '.uvvis.original_absorbance'];
    norm=lower(strtrim(gxtxt_ini_get(cfg,'config.normalization','none')));
    if(strcmp(norm,'none')),px='spectral_x';py='spectral_y';else px='wavelength_nm';py='relative_response';endif
    axes=struct('x',struct('label','Wavelength [nm]','display_unit','nm','scale','linear'), ...
      'y_left',struct('label','Absorbance / relative response','scale','linear'));
    raw=struct('id','original_absorbance','dataset_id',original,'x_variable_id','wavelength_nm', ...
      'y_variable_id','absorbance','axis','left','kind','line','label','Original absorbance', ...
      'style',struct('color','#777777','line_width','1.2'));
    proc=struct('id','processed_response','dataset_id',processed,'x_variable_id',px, ...
      'y_variable_id',py,'axis','left','kind','line','label','Processed response', ...
      'style',struct('color','#1256b5','line_width','1.7'));
    wave=str2double(gxtxt_ini_get(cfg,'config.selected_wavelength_nm','322'));
    mark=struct('type','reference_line','axis','x','value',wave,'label',sprintf('Selected %.1f nm',wave));
    panel=struct('id','main','title','UV/Vis spectrum','axes',axes,'series',{{raw,proc}},'annotations',{{mark}});
    result{1}=make_plot(session,'UV/Vis source and processed spectrum',panel,outdir,'uvvis_single');
    names{1}='01_uvvis_exploration.png';keys{1}='uvvis_single';
  elseif(strcmp(mode,'time_series'))
    response=[source '.uvvis.time_response'];family=[source '.uvvis.processed_family'];
    axes=struct('x',struct('label',['Elapsed time [' unit ']'],'display_unit',unit,'scale','linear'), ...
      'y_left',struct('label','Response at selected wavelength','scale','linear'));
    s=struct('id','time_response','dataset_id',response,'x_variable_id','elapsed_time', ...
      'y_variable_id','response','axis','left','kind','line_marker','label','Time response');
    panel=struct('id','main','title','UV/Vis elapsed-time response','axes',axes,'series',{{s}});
    result{1}=make_plot(session,'UV/Vis elapsed-time response',panel,outdir,'uvvis_time_response');
    names{1}='01_uvvis_exploration.png';keys{1}='uvvis_time_response';
    axes=struct('x',struct('label','Wavelength [nm]','display_unit','nm','scale','linear'), ...
      'y_left',struct('label','Processed response','scale','linear'));
    s=struct('id','processed_family','dataset_id',family,'x_variable_id','spectral_x', ...
      'y_variable_id','spectral_y','family_variable_id','parameter_value', ...
      'family_label_prefix','Elapsed time','axis','left','kind','line','label','Processed spectra');
    panel=struct('id','main','title','UV/Vis processed spectral family','axes',axes,'series',{{s}});
    result{2}=make_plot(session,'UV/Vis processed spectral family',panel,outdir,'uvvis_family');
    names{2}='02_uvvis_processed_family.png';keys{2}='uvvis_family';
  else
    error('UV/Vis provider: unsupported workflow %s',mode);
  endif
  for i=1:numel(result)
    if(!isfield(result{i},'artifact')||exist(result{i}.artifact,'file')!=2),error('UV/Vis provider: graph artifact missing');endif
    [ok,msg]=copyfile(result{i}.artifact,fullfile(outdir,names{i}),'f');
    if(!ok),error('UV/Vis provider: graph copy failed: %s',msg);endif
  endfor
  fid=fopen(fullfile(outdir,'automatic_graphs.ini'),'w');if(fid<0),error('UV/Vis provider: cannot write graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\nbridge=PLOT_DATASET_OCTAVE_BRIDGE_v1\npersistent_variants=true\n',numel(result));
    for i=1:numel(result)
      fprintf(fid,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n', ...
        i,keys{i},result{i}.graph_id,result{i}.variant_id,names{i},result{i}.artifact);
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function result=make_plot(session,title_text,panel,outdir,key)
  spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy', ...
    'title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct('extra_format','svg'));
  variant='';manifest=fullfile(outdir,'automatic_graphs.ini');
  if(exist(manifest,'file')==2)
    prior=gxtxt_ini_read(manifest);n=str2double(gxtxt_ini_get(prior,'automatic_graphs.count','0'));
    for i=1:n
      section=sprintf('graph.%02d',i);
      if(strcmp(gxtxt_ini_get(prior,[section '.key'],''),key)&& ...
         strcmp(gxtxt_ini_get(prior,[section '.graph_id'],''),'plot.dataset.xy'))
        variant=strtrim(gxtxt_ini_get(prior,[section '.variant_id'],''));break;
      endif
    endfor
  endif
  options=struct('action','ensure','kind','variant','provider_key',['analysis.spectroscopy.uvvis_exploration:' key], ...
    'variant_id',variant,'render',true);
  result=gxtxt_plot_dataset_v2(session,spec,options);
endfunction
