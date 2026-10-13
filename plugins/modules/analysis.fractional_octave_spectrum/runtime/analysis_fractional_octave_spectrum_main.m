function analysis_fractional_octave_spectrum_main(args)
% Fractional-Octave Band Analysis - scientific stage.
% SPDX-License-Identifier: GPL-3.0-or-later
  module_id='analysis.fractional_octave_spectrum';
  module_version='1.1.0';
  chunk_rows=65536;
  publication_chunk_rows=4096;
  this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);package_root=fileparts(plugins_dir);
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('%s: --config is required',module_id);endif
  cfg=gxtxt_ini_read(config_path);
  outdir=strtrim(gxtxt_ini_get(cfg,'runtime.output_dir',''));
  session=strtrim(gxtxt_ini_get(cfg,'runtime.session',''));
  if(isempty(outdir)||isempty(session)),error('%s: runtime output/session information is missing',module_id);endif
  if(exist(outdir,'dir')!=7),mkdir(outdir);endif
  P=struct();publication_open=false;publication_finalized=false;
  gxtxt_progress_start('prepare','Preparing fractional-octave analysis','indeterminate');
  try
    source_dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
    if(isempty(source_dataset_id)),source_dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
    if(isempty(source_dataset_id)),error('%s: primary source Dataset ID is missing',module_id);endif

    frequency_binding=binding_name(gxtxt_ini_get(cfg,'bindings.frequency',''));
    psd_binding=binding_name(gxtxt_ini_get(cfg,'bindings.psd',''));
    if(isempty(frequency_binding)||isempty(psd_binding)),error('%s: frequency and PSD bindings are required',module_id);endif
    [frequency_unit,~,frequency_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',frequency_binding);
    [psd_unit,~,psd_meta]=gxtxt_analysis_source_variable_meta(cfg,'primary',psd_binding);
    require_meta(frequency_meta,'frequency',module_id);require_meta(psd_meta,'PSD',module_id);
    frequency_id=strtrim(frequency_meta.variable_id);psd_id=strtrim(psd_meta.variable_id);
    psd_name=strtrim(psd_meta.name);if(isempty(psd_name)),psd_name=psd_id;endif
    if(isempty(strtrim(frequency_unit))),frequency_unit='Hz';endif
    try compatible=gxtxt_unit_compatible(frequency_unit,'Hz');catch compatible=false;end_try_catch
    if(!compatible),error('%s: frequency variable unit must be compatible with Hz (got %s)',module_id,frequency_unit);endif

    bands_per_octave=parse_choice_int(gxtxt_ini_get(cfg,'config.bands_per_octave','3'),[1 3 6],'bands per octave');
    range_mode=lower(strtrim(gxtxt_ini_get(cfg,'config.range_mode','auto')));
    if(!any(strcmp(range_mode,{'auto','explicit'}))),error('%s: invalid range mode',module_id);endif
    min_hz=str2double(strtrim(gxtxt_ini_get(cfg,'config.minimum_frequency_hz','20')));
    max_hz=str2double(strtrim(gxtxt_ini_get(cfg,'config.maximum_frequency_hz','20000')));
    reference_rms=str2double(strtrim(gxtxt_ini_get(cfg,'config.reference_rms','1')));
    if(!(isfinite(reference_rms)&&reference_rms>0)),error('%s: RMS reference must be positive',module_id);endif
    discover_plot_service(package_root,module_id);

    gxtxt_progress_stage('scan','Scanning source frequency axis','indeterminate');
    S=scan_frequency_axis(cfg,frequency_id,frequency_unit,chunk_rows);
    B=fractional_octave_band_definitions(S.source_lower_hz,S.source_upper_hz,S.min_positive_hz,bands_per_octave,range_mode,min_hz,max_hz);
    gxtxt_progress_stage('integrate',sprintf('Integrating PSD into %d fractional-octave bands',numel(B.center_hz)),'indeterminate');
    [band_power,covered_width,source_provider]=integrate_psd_stream(cfg,frequency_id,frequency_unit,psd_id,B,chunk_rows);
    coverage_fraction=covered_width./B.bandwidth_hz;
    if(any(coverage_fraction<1-1e-9)),error('%s: complete-band integration unexpectedly produced incomplete source coverage',module_id);endif
    band_rms=sqrt(max(band_power,0));
    band_level_db=20*log10(max(band_rms,realmin)./reference_rms);
    [power_unit,rms_unit]=derive_band_units(psd_unit);
    [~,peak_i]=max(band_power);peak_center=B.center_hz(peak_i);peak_power=band_power(peak_i);total_band_power=sum(band_power);

    pub_id=[safe_id(source_dataset_id) '.frac_oct.' safe_id(psd_id) '.n' num2str(bands_per_octave)];
    provenance=sprintf('source_dataset=%s;frequency=%s;psd=%s;bands_per_octave=%d;definition=base10_G_10^(3/10);range_mode=%s;reference_rms=%.17g;module=%s@%s',source_dataset_id,frequency_id,psd_id,bands_per_octave,range_mode,reference_rms,module_id,module_version);
    options=struct('storage','auto','capabilities_required',{{'typed_numeric','range_write'}},'capabilities_preferred',{{'sequential_chunks'}},'replace_owned',true,'producer_version',module_version,'source_dataset_ids',{{source_dataset_id}},'source_variable_ids',{{frequency_id,psd_id}},'source',source_dataset_id,'provenance',provenance,'notes','Exact base-10 fractional-octave integration of a linear PSD. This is spectral band integration, not IEC 61260 instrument-class compliance.');
    nb=numel(B.center_hz);
    gxtxt_progress_stage('publish','Publishing fractional-octave Dataset','determinate',nb);
    P=gxtxt_publication_v2_open(session,module_id,pub_id,'spectrum.table',options);publication_open=true;
    P=gxtxt_publication_v2_declare_dimension(P,'band',nb,false);chunks=min(publication_chunk_rows,nb);
    P=gxtxt_publication_v2_declare_variable(P,'center_frequency',struct('dtype','float64','dimension_ids','band','name','center_frequency','unit','Hz','semantic_role','independent','chunks',chunks));
    vars={'band_number',double(B.band_number),'1';'lower_frequency',B.lower_hz,'Hz';'upper_frequency',B.upper_hz,'Hz';'bandwidth',B.bandwidth_hz,'Hz';'band_power',band_power,power_unit;'band_rms',band_rms,rms_unit;'band_level_db',band_level_db,'dB';'coverage_fraction',coverage_fraction,'1'};
    for vi=1:size(vars,1)
      P=gxtxt_publication_v2_declare_variable(P,vars{vi,1},struct('dtype','float64','dimension_ids','band','name',vars{vi,1},'unit',vars{vi,3},'semantic_role','measured','coordinate_variable_ids','center_frequency','chunks',chunks));
    endfor
    for start0=0:publication_chunk_rows:(nb-1)
      count=min(publication_chunk_rows,nb-start0);rr=(start0+1):(start0+count);
      P=gxtxt_publication_v2_write_range(P,'center_frequency',start0,B.center_hz(rr));
      for vi=1:size(vars,1),P=gxtxt_publication_v2_write_range(P,vars{vi,1},start0,vars{vi,2}(rr));endfor
      gxtxt_progress_update(start0+count,nb,'publish',sprintf('Published %d/%d bands',start0+count,nb));
    endfor
    output_provider=P.provider;[P,pub_result]=gxtxt_publication_v2_finalize(P);publication_finalized=true;publication_open=false;

    write_report(fullfile(outdir,'fractional_octave_report.txt'),module_version,source_dataset_id,frequency_id,psd_id,psd_name,psd_unit,bands_per_octave,range_mode,S,B,reference_rms,power_unit,rms_unit,source_provider,output_provider,pub_id,peak_center,peak_power,total_band_power);
    db_baseline=min(band_level_db)-max(6,0.1*max(1,max(band_level_db)-min(band_level_db)));
    gxtxt_progress_stage('plot','Creating persistent plot.dataset fractional-octave graphs','indeterminate');
    graphs=create_standard_graphs(session,pub_id,reference_rms,power_unit,rms_unit,db_baseline,module_id);copy_graph_artifacts(graphs,outdir,module_id);write_graph_manifest(fullfile(outdir,'automatic_graphs.ini'),graphs);
    gxtxt_progress_complete('done',sprintf('Published %s with %d bands and %d persistent graphs',pub_id,nb,numel(graphs)));
  catch err
    if(publication_open&&!publication_finalized),try P=gxtxt_publication_v2_abort(P);catch;end_try_catch;endif
    try gxtxt_progress_fail('failed',err.message);catch;end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function S=scan_frequency_axis(cfg,frequency_id,frequency_unit,chunk_rows)
  st=gxtxt_table_stream_open_source(cfg,'primary',{frequency_id},chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));
  first=NaN;second=NaN;prev=NaN;last=NaN;minpos=Inf;rows=0;
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_v3_next(st);
      if(ch.nrows>0)
        f=gxtxt_table_chunk_numeric(ch,frequency_id);f=gxtxt_unit_convert(f(:),frequency_unit,'Hz');
        if(any(!isfinite(f))),error('analysis.fractional_octave_spectrum: frequency contains non-finite values');endif
        if(any(f<0)),error('analysis.fractional_octave_spectrum: frequency must be non-negative');endif
        if(isfinite(prev)&&f(1)<=prev),error('analysis.fractional_octave_spectrum: frequency must be strictly increasing');endif
        if(any(diff(f)<=0)),error('analysis.fractional_octave_spectrum: frequency must be strictly increasing');endif
        if(rows==0),first=f(1);if(numel(f)>=2),second=f(2);endif;elseif(!isfinite(second)),second=f(1);endif
        pos=f(f>0);if(!isempty(pos)),minpos=min(minpos,min(pos));endif
        rows+=numel(f);prev=f(end);last=f(end);
      endif
      if(ch.eof),break;endif
    endwhile
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(rows<2||!isfinite(second)),error('analysis.fractional_octave_spectrum: at least two frequency samples are required');endif
  if(!isfinite(minpos)),error('analysis.fractional_octave_spectrum: source contains no positive frequency');endif
  first_gap=second-first;source_lo=max(0,first-first_gap/2);
  st=gxtxt_table_stream_open_source(cfg,'primary',{frequency_id},2,struct('start',rows-2,'count',2,'require_direct',false,'numeric_transport','auto'));
  unwind_protect
    [st,ch]=gxtxt_table_stream_v3_next(st);tail=gxtxt_table_chunk_numeric(ch,frequency_id);tail=gxtxt_unit_convert(tail(:),frequency_unit,'Hz');
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
  if(numel(tail)!=2),error('analysis.fractional_octave_spectrum: failed to read source frequency tail');endif
  source_hi=tail(2)+(tail(2)-tail(1))/2;
  S=struct('rows',rows,'first_hz',first,'last_hz',last,'min_positive_hz',minpos,'source_lower_hz',source_lo,'source_upper_hz',source_hi);
endfunction

function [power,covered,provider]=integrate_psd_stream(cfg,frequency_id,frequency_unit,psd_id,B,chunk_rows)
  nb=numel(B.center_hz);power=zeros(nb,1);covered=zeros(nb,1);band_cursor=1;pending=false;pf=NaN;pp=NaN;pleft=NaN;last_gap=NaN;
  st=gxtxt_table_stream_open_source(cfg,'primary',{frequency_id,psd_id},chunk_rows,struct('start',0,'count',-1,'require_direct',false,'numeric_transport','auto'));provider=st.storage_provider;
  unwind_protect
    while(true)
      [st,ch]=gxtxt_table_stream_v3_next(st);
      if(ch.nrows>0)
        f=gxtxt_table_chunk_numeric(ch,frequency_id);f=gxtxt_unit_convert(f(:),frequency_unit,'Hz');
        p=gxtxt_table_chunk_numeric(ch,psd_id);p=p(:);
        if(numel(f)!=numel(p)),error('analysis.fractional_octave_spectrum: source chunk column-size mismatch');endif
        if(any(!isfinite(p))),error('analysis.fractional_octave_spectrum: PSD contains non-finite values');endif
        if(any(p<0)),error('analysis.fractional_octave_spectrum: linear PSD must be non-negative');endif
        for i=1:numel(f)
          cf=f(i);cp=p(i);
          if(!pending)
            pending=true;pf=cf;pp=cp;pleft=NaN;
          else
            gap=cf-pf;if(!(gap>0)),error('analysis.fractional_octave_spectrum: frequency must be strictly increasing');endif
            right=(pf+cf)/2;if(!isfinite(pleft)),left=max(0,pf-gap/2);else left=pleft;endif
            [power,covered,band_cursor]=accumulate_cell(power,covered,band_cursor,B,left,right,pp);
            pleft=right;last_gap=gap;pf=cf;pp=cp;
          endif
        endfor
      endif
      if(ch.eof),break;endif
    endwhile
    if(!pending||!isfinite(last_gap)),error('analysis.fractional_octave_spectrum: insufficient spectral samples');endif
    right=pf+last_gap/2;[power,covered,band_cursor]=accumulate_cell(power,covered,band_cursor,B,pleft,right,pp);
  unwind_protect_cleanup
    st=gxtxt_table_stream_close(st);
  end_unwind_protect
endfunction

function [power,covered,cursor]=accumulate_cell(power,covered,cursor,B,left,right,density)
  nb=numel(B.center_hz);
  while(cursor<=nb&&B.upper_hz(cursor)<=left),cursor+=1;endwhile
  k=cursor;
  while(k<=nb&&B.lower_hz(k)<right)
    ov=min(right,B.upper_hz(k))-max(left,B.lower_hz(k));
    if(ov>0),power(k)+=density*ov;covered(k)+=ov;endif
    k+=1;
  endwhile
endfunction

function [power_unit,rms_unit]=derive_band_units(psd_unit)
  u=strtrim(psd_unit);
  if(strcmp(u,'1/Hz')),power_unit='1';rms_unit='1';return;endif
  suffix='^2/Hz';
  if(length(u)>length(suffix)&&strcmp(u(end-length(suffix)+1:end),suffix))
    base=u(1:end-length(suffix));power_unit=[base '^2'];rms_unit=base;
  else
    power_unit=[u '*Hz'];rms_unit=['sqrt(' power_unit ')'];
  endif
endfunction
function s=binding_name(s),s=strtrim(s);p=strfind(s,'.');if(!isempty(p)),s=s(p(end)+1:end);endif;endfunction
function require_meta(m,label,module_id),if(!isfield(m,'found')||!m.found||!isfield(m,'variable_id')||isempty(strtrim(m.variable_id))),error('%s: %s binding could not be resolved to a stable variable ID',module_id,label);endif;endfunction
function v=parse_choice_int(raw,allowed,label),v=str2double(strtrim(raw));if(!isfinite(v)||v!=fix(v)||!any(v==allowed)),error('analysis.fractional_octave_spectrum: invalid %s',label);endif;endfunction
function s=safe_id(s),s=regexprep(strtrim(s),'[^A-Za-z0-9_.-]','_');if(isempty(s)),s='spectrum';endif;endfunction
function discover_plot_service(root,module_id)
  pd=fullfile(root,'plugins','modules','plot.dataset','module.ini');if(exist(pd,'file')!=2),error('%s: plot.dataset descriptor missing',module_id);endif
  d=gxtxt_ini_read(pd);ids=split_list(gxtxt_ini_get(d,'public_apis.ids',''));if(!any(strcmp(ids,'PLOT_DATASET_API_v2'))),error('%s: PLOT_DATASET_API_v2 is not advertised',module_id);endif
  caps=split_list(gxtxt_ini_get(d,'public_api.PLOT_DATASET_API_v2.capabilities',''));for req={'series_kind_bar','bar_x_bounds'},if(!any(strcmp(caps,req{1}))),error('%s: PLOT_DATASET_API_v2 capability missing: %s',module_id,req{1});endif;endfor
  bridge=fullfile(root,'core','octave','io','gxtxt_plot_dataset_v2.m');if(exist(bridge,'file')!=2),error('%s: public PLOT_DATASET_API_v2 Octave bridge unavailable',module_id);endif;addpath(fileparts(bridge));
endfunction
function G=create_standard_graphs(session,dataset_id,reference_rms,power_unit,rms_unit,db_baseline,module_id)
  G={};
  G{end+1}=create_band_plot(session,dataset_id,'band_level_db','Fractional-octave band level','band_level_db',sprintf('Band level [dB re %.6g %s RMS]',reference_rms,rms_unit),'dB',db_baseline,module_id);
  G{end+1}=create_band_plot(session,dataset_id,'band_rms','Fractional-octave band RMS','band_rms','Band RMS',rms_unit,0,module_id);
  G{end+1}=create_band_plot(session,dataset_id,'band_power','Fractional-octave band power','band_power','Band power',power_unit,0,module_id);
endfunction
function R=create_band_plot(session,dataset_id,key,title_text,yvar,ylabel,yunit,baseline,module_id)
  axes=struct('x',struct('label','Band centre frequency [Hz]','display_unit','Hz','scale','log'),'y_left',struct('label',axis_label(ylabel,yunit),'scale','linear'));
  bounds=struct('lower_variable_id','lower_frequency','upper_variable_id','upper_frequency');
  series=struct('id',key,'dataset_id',dataset_id,'x_variable_id','center_frequency','y_variable_id',yvar,'axis','left','kind','bar','label',ylabel,'bar_bounds',bounds,'bar_baseline',num2str(baseline,17),'style',struct('opacity',0.35));
  panel=struct('id','main','title',title_text,'axes',axes,'series',{{series}});spec=struct('schema','PLOT_DATASET_PLOTSPEC_v2','graph_type','cartesian_2d','graph_id','plot.dataset.xy','title',title_text,'defaults',struct('style',struct()),'panels',{{panel}},'output',struct());
  R=gxtxt_plot_dataset_v2(session,spec,struct('action','create','kind','variant','source_variant','','render',true));if(!isfield(R,'artifact')||isempty(strtrim(R.artifact))),error('%s: plot.dataset returned no artifact for %s',module_id,key);endif;R.key=key;
endfunction
function copy_graph_artifacts(G,outdir,module_id)
  for i=1:numel(G),src=strtrim(G{i}.artifact);if(isempty(src)||exist(src,'file')!=2),error('%s: plot.dataset graph artifact missing for %s',module_id,G{i}.key);endif;dst=fullfile(outdir,sprintf('%02d_%s.png',i,G{i}.key));[ok,msg]=copyfile(src,dst,'f');if(!ok),error('%s: cannot copy plot.dataset artifact: %s',module_id,msg);endif;endfor
endfunction
function write_graph_manifest(path,G)
  fid=fopen(path,'w');if(fid<0),error('analysis.fractional_octave_spectrum: cannot write automatic graph manifest');endif
  unwind_protect
    fprintf(fid,'[automatic_graphs]\ncount=%d\nprovider=plot.dataset\napi=PLOT_DATASET_API_v2\npersistent_variants=true\n',numel(G));
    for i=1:numel(G),fprintf(fid,'\n[graph.%02d]\nkey=%s\ngraph_id=%s\nvariant_id=%s\npng=%02d_%s.png\nprovider_artifact=%s\nrerender=Use the persisted plot.dataset variant\n',i,G{i}.key,ini_escape(G{i}.graph_id),ini_escape(G{i}.variant_id),i,G{i}.key,ini_escape(G{i}.artifact));endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function s=axis_label(name,unit),if(isempty(strtrim(unit))||strcmp(unit,'1')),s=name;else s=sprintf('%s [%s]',name,unit);endif;endfunction
function s=ini_escape(s),s=strrep(strrep(char(s),sprintf('\r'),' '),sprintf('\n'),' ');endfunction
function out=split_list(s),s=strrep(char(s),',',';');parts=strsplit(s,';');out={};for i=1:numel(parts),q=strtrim(parts{i});if(!isempty(q)),out{end+1}=q;endif;endfor;endfunction
function write_report(path,version,ds,fid,pid,pname,punit,N,mode,S,B,ref,power_unit,rms_unit,source_provider,output_provider,pub_id,peak_center,peak_power,total_power)
  h=fopen(path,'w');if(h<0),error('analysis.fractional_octave_spectrum: cannot write report');endif
  unwind_protect
    fprintf(h,'Fractional-Octave Band Analysis\n================================\n');
    fprintf(h,'Module version: %s\nSource Dataset: %s\nFrequency variable: %s\nPSD variable: %s (%s)\nPSD unit: %s\n',version,ds,fid,pname,pid,punit);
    fprintf(h,'Bands per octave: %d\nDefinition: exact base-10, G = 10^(3/10), reference centre = 1000 Hz\nRange mode: %s\nSource support: %.17g .. %.17g Hz\nPublished complete bands: %d\n',N,mode,S.source_lower_hz,S.source_upper_hz,numel(B.center_hz));
    fprintf(h,'Band RMS reference: %.17g %s\nBand power unit: %s\nBand RMS unit: %s\n',ref,rms_unit,power_unit,rms_unit);
    fprintf(h,'Peak band centre by integrated power: %.17g Hz\nPeak band power: %.17g %s\nSum of published band powers: %.17g %s\n',peak_center,peak_power,power_unit,total_power,power_unit);
    fprintf(h,'Source provider: %s\nOutput provider: %s\nPublished Dataset: %s\n',source_provider,output_provider,pub_id);
    fprintf(h,'Method: linear PSD integrated over exact band edges using frequency-bin cell overlap.\nCompliance note: this is FFT/PSD band integration and does not claim IEC 61260 instrument-class filter-bank compliance.\n');
  unwind_protect_cleanup
    fclose(h);
  end_unwind_protect
endfunction
function value=arg_value(args,name,default_value),value=default_value;for i=1:(numel(args)-1),if(strcmp(args{i},name)),value=args{i+1};return;endif;endfor;endfunction
