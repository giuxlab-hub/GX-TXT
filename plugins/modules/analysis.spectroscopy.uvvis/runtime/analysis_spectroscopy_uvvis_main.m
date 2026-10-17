function analysis_spectroscopy_uvvis_main(args)
% Dataset-native UV/Vis quantitation using public numerical and plot services.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.spectroscopy.uvvis';module_version='1.2.0';
  config_path=arg_value(args,'--config','');if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime.output_dir and runtime.session are required',module_id);endif;if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  root=framework_root();discover_numeric_api(cfg,module_id);discover_plot_service(root,module_id);
  runner=fullfile(fileparts(mfilename('fullpath')),'uvvis_pipeline.tcl');bridge=fullfile(root,'core','tcl','analysis_tcl_bridge_v1.tcl');
  gxtxt_progress_start('analysis','Running UV/Vis family quantitation and validation','indeterminate');
  try
    cmd=sprintf('tclsh %s %s %s %s',gxtxt_shell_quote_v1(bridge),gxtxt_shell_quote_v1(root),gxtxt_shell_quote_v1(runner),gxtxt_shell_quote_v1(config_path));
    [status,output]=system(cmd);if(status!=0),error('%s pipeline failed: %s',module_id,output);endif
    family_dataset=marker_value(output,'FAMILY_PLOT_DATASET=');cal_dataset=marker_value(output,'CALIBRATION_DATASET=');res_dataset=marker_value(output,'RESIDUALS_DATASET=');
    val_dataset=marker_value(output,'VALIDATION_DATASET=');unknown_dataset=marker_value(output,'UNKNOWN_DATASET=');wl=str2double(marker_value(output,'SELECTED_WAVELENGTH_NM='));spread=str2double(marker_value(output,'RESIDUAL_SPREAD='));
    if(any(cellfun(@isempty,{family_dataset,cal_dataset,res_dataset}))||!isfinite(wl)),error('%s: pipeline returned incomplete graph Dataset markers',module_id);endif
    gxtxt_progress_stage('plot','Creating persistent plot.dataset UV/Vis graphs','indeterminate');
    G=create_graphs(session,family_dataset,cal_dataset,res_dataset,val_dataset,unknown_dataset,wl,spread,module_id);
    copy_graphs(G,outdir,module_id);write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),G);
    gxtxt_progress_complete('done',sprintf('UV/Vis analysis completed; %d persistent plot.dataset variants created',numel(G)));
    fprintf('%s',output);fprintf('[%s] version=%s family_dataset=%s graph_variants=%d validation=PASS\n',module_id,module_version,family_dataset,numel(G));
  catch err
    try gxtxt_progress_fail('failed','UV/Vis analysis failed; see log for details');catch;end_try_catch;rethrow(err);
  end_try_catch
endfunction

function discover_numeric_api(cfg,module_id)
  sec='public_api.NUMERIC_API_v1';provider=strtrim(gxtxt_ini_get(cfg,[sec '.module_id'],''));if(!strcmp(provider,'math.numeric')),error('%s: runtime NUMERIC_API_v1 provider discovery failed',module_id);endif
  caps=split_list(gxtxt_ini_get(cfg,[sec '.capabilities'],''));required={'interpolation','resampling','linear_regression','peak_detection'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: NUMERIC_API_v1 capability missing: %s',module_id,required{k});endif;endfor
endfunction

function discover_plot_service(root,module_id)
  pd=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(pd,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif
  d=gxtxt_ini_read(pd);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.PLOT_DATASET_API_v2.capabilities',''));required={'series_kind_line','series_kind_scatter','series_family_grouping','multi_dataset','annotations_reference_line'};for k=1:numel(required),if(!any(strcmp(caps,required{k}))),error('%s: PLOT_DATASET_API_v2 capability missing: %s',module_id,required{k});endif;endfor
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable',module_id);endif;addpath(fileparts(bridge));
endfunction

function G=create_graphs(session,family_id,cal_id,res_id,val_id,unknown_id,wavelength,spread,module_id)
  G=struct([]);
  ax=struct('x',struct('label','Wavelength [nm]','display_unit','nm','scale','linear'),'y_left',struct('label','Absorbance [1]','display_unit','1','scale','linear'));
  fam=struct('id','uvvis_family','dataset_id',family_id,'x_variable_id','spectral_x','y_variable_id','spectral_y','family_variable_id','parameter_value','family_label_prefix','Concentration','axis','left','kind','line','label','Measured family','style',struct('line_width','1.4'));
  ann=struct('type','reference_line','axis','x','value',num2str(wavelength,17),'label',sprintf('Selected %.6g nm',wavelength),'line_style','dotted','line_width','1.2');
  panel=struct('id','main','title','Measured UV/Vis concentration family','axes',ax,'series',{{fam}},'annotations',{{ann}});spec=spec1('Measured UV/Vis concentration family',panel);
  r=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));r.key='family';G(end+1)=r;

  ax=struct('x',struct('label','Concentration [wt%]','display_unit','%','scale','linear'),'y_left',struct('label','Absorbance [1]','display_unit','1','scale','linear'));
  meas=struct('id','standards','dataset_id',cal_id,'x_variable_id','concentration','y_variable_id','response','axis','left','kind','scatter','label','Measured standards','style',struct('marker','circle','marker_fill','full','marker_size','7'));
  fit=struct('id','fit','dataset_id',cal_id,'x_variable_id','concentration','y_variable_id','fitted_response','axis','left','kind','line','label','Public linear regression','style',struct('line_width','2'));
  series={meas,fit};
  if(!isempty(val_id)),series{end+1}=struct('id','heldout','dataset_id',val_id,'x_variable_id','known_concentration','y_variable_id','response','axis','left','kind','scatter','label','Held-out validation','style',struct('marker','square','marker_fill','full','marker_size','8'));endif
  if(!isempty(unknown_id)),series{end+1}=struct('id','unknown','dataset_id',unknown_id,'x_variable_id','estimated_concentration','y_variable_id','response','axis','left','kind','scatter','label','Independent unknown','style',struct('marker','diamond','marker_fill','full','marker_size','8'));endif
  panel=struct('id','main','title','UV/Vis calibration with held-out validation','axes',ax,'series',{series});spec=spec1('UV/Vis calibration with held-out validation',panel);
  r=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));r.key='calibration';G(end+1)=r;

  ylim=max(0.005,1.2*spread);ax=struct('x',struct('label','Concentration [wt%]','display_unit','%','scale','linear'),'y_left',struct('label','Residual absorbance [1]','display_unit','1','scale','linear','min',num2str(-ylim,17),'max',num2str(ylim,17)));
  resid=struct('id','residuals','dataset_id',res_id,'x_variable_id','concentration','y_variable_id','residual','axis','left','kind','scatter','label','Individual standard residual','style',struct('marker','circle','marker_fill','full','marker_size','7'));
  zero=struct('type','reference_line','axis','left','value','0','label','Zero reference','line_style','dashed','line_width','1.2');
  panel=struct('id','main','title','Calibration residuals at selected wavelength','axes',ax,'series',{{resid}},'annotations',{{zero}});spec=spec1('Calibration residuals at selected wavelength',panel);
  r=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));r.key='residuals';G(end+1)=r;
  for i=1:numel(G),if(!isfield(G(i),'artifact')||isempty(strtrim(G(i).artifact))),error('%s: plot.dataset returned no artifact for %s',module_id,G(i).key);endif;endfor
endfunction

function spec=spec1(title_text,panel),spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());endfunction
function copy_graphs(G,outdir,module_id),names={'01_family_overlay.png','02_calibration.png','03_residuals.png'};for i=1:numel(G),src=strtrim(G(i).artifact);if(exist(src,'file')!=2),error('%s: plot.dataset artifact missing for %s',module_id,G(i).key);endif;[ok,msg]=copyfile(src,fullfile(outdir,names{i}),'f');if(!ok),error('%s: cannot copy graph %s: %s',module_id,G(i).key,msg);endif;endfor;endfunction
function write_graph_manifest(path,G),fid=fopen(path,'w');if(fid<0),error('analysis.spectroscopy.uvvis: cannot write automatic graph manifest');endif;unwind_protect fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(G));for i=1:numel(G),fprintf(fid,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',i,ini_escape(G(i).key),ini_escape(G(i).graph_id),ini_escape(G(i).variant_id),ini_escape(G(i).artifact));endfor;unwind_protect_cleanup fclose(fid);end_unwind_protect;endfunction
function value=marker_value(output,marker),pos=strfind(output,marker);value='';if(isempty(pos)),return;endif;tail=output(pos(end)+length(marker):end);stop=find(tail==sprintf('\n'),1);if(!isempty(stop)),tail=tail(1:stop-1);endif;value=strtrim(tail);endfunction
function root=framework_root(),runtime_dir=fileparts(mfilename('fullpath'));module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);root=fileparts(plugins_dir);endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
function s=ini_escape(s),s=strrep(char(s),sprintf('\n'),' ');s=strrep(s,sprintf('\r'),' ');endfunction
function value=arg_value(args,key,def),value=def;for i=1:(numel(args)-1),if(strcmp(args{i},key)),value=args{i+1};return;endif;endfor;endfunction
