function gxtxt_ir_waveform_main(args)
  try
    gxtxt_ir_waveform_main_impl(args);
  catch err
    try, gxtxt_progress_fail('failed','IR waveform analysis failed; see log for details'); catch, end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function gxtxt_ir_waveform_main_impl(args)
% Clean Standard Module API implementation of the historical GX-TXT IR
% waveform algorithm.  Acquisition/import, UI, session management and common
% graphics are intentionally delegated to the framework.
% SPDX-License-Identifier: GPL-3.0-or-later

  config_path = arg_value(args,'--config','');
  if (isempty(config_path)), error('gxtxt.ir_waveform: --config is required'); endif
  cfg = read_ini(config_path);
  numeric_fn=ir_numeric_binding(cfg);
  outdir = ini_get(cfg,'runtime.output_dir','');
  if (isempty(outdir)), error('gxtxt.ir_waveform: runtime.output_dir missing'); endif
  if (exist(outdir,'dir') != 7), mkdir(outdir); endif

  gxtxt_progress_start('loading_data','Loading canonical IR waveform','indeterminate');
  primary_dataset_id = strtrim(ini_get(cfg,'analysis_source.primary.dataset_id',ini_get(cfg,'dataset.id','')));
  data_path = strtrim(ini_get(cfg,'analysis_source.primary.path',ini_get(cfg,'dataset.path','')));
  if (exist(data_path,'file') != 2), error('Dataset not found: %s',data_path); endif
  [signal_source,signal_name] = binding_parts(ini_get(cfg,'bindings.signal',''),'primary',cfg);
  if (isempty(signal_name)), error('gxtxt.ir_waveform: signal binding is unresolved'); endif
  if (!strcmp(signal_source,'primary')), error('gxtxt.ir_waveform: IR waveform signal must use the primary Analysis Source, got %s.%s',signal_source,signal_name); endif
  [time_source,time_name] = binding_parts(ini_get(cfg,'bindings.time',''),'primary',cfg);
  if (isempty(time_name)), time_name='time_s'; endif
  if (!strcmp(time_source,'primary')), error('gxtxt.ir_waveform: time binding must use the primary Analysis Source, got %s.%s',time_source,time_name); endif
  [t,v] = read_named_csv2(data_path,time_name,signal_name);
  valid = isfinite(t) & isfinite(v);
  t=t(valid); v=v(valid);
  if (numel(t) < 1000), error('gxtxt.ir_waveform: too few valid samples (%d)',numel(t)); endif
  [t,ord]=sort(t(:)); v=v(ord);
  dtv=diff(t); dtv=dtv(isfinite(dtv) & dtv>0);
  if (isempty(dtv)), error('gxtxt.ir_waveform: invalid/non-increasing time axis'); endif
  dt=gxtxt_ir_numeric(numeric_fn,'median',dtv);
  if (!isfinite(dt) || dt<=0), error('gxtxt.ir_waveform: invalid sample interval'); endif
  Fs=1/dt;

  acfg = analysis_config(cfg);
  validate_analysis_config(acfg);

  session = strtrim(ini_get(cfg,'runtime.session',''));
  if (isempty(session)), session=fileparts(fileparts(data_path)); endif
  comparison_sources = resolve_comparison_sources(cfg,session,data_path,time_name,signal_name);

  gxtxt_progress_stage('pretest','Validating signal and carrier','indeterminate');
  P = adaptive_pretest(t,v,acfg,numeric_fn);

  baseline=P.baseline;
  if (P.polaritySign < 0), sig=baseline-v; else sig=v-baseline; endif
  sig(sig<0)=0;

  gxtxt_progress_stage('carrier','Detecting carrier pulses','indeterminate');
  carrierLogic = sig >= P.threshold;
  dLogic = diff([false; carrierLogic; false]);
  idxRise=find(dLogic==1); idxFall=find(dLogic==-1)-1;
  nPulses=min(numel(idxRise),numel(idxFall));
  idxRise=idxRise(1:nPulses); idxFall=idxFall(1:nPulses);
  keep=idxFall>=idxRise; idxRise=idxRise(keep); idxFall=idxFall(keep);
  pulseStart=t(idxRise); pulseEnd=t(idxFall); pulseWidth=pulseEnd-pulseStart+dt;
  nPulses=numel(pulseStart);
  nPulsesDetected=nPulses;
  if (nPulses<3), error('gxtxt.ir_waveform: too few carrier pulses detected (%d)',nPulses); endif
  carrierLock = gxtxt_ir_carrier_search(pulseStart,acfg.nominalCarrier_Hz,acfg.carrierSearchMode,acfg.carrierLockTolerance,acfg.carrierSearchMin_Hz,acfg.carrierSearchMax_Hz,dt,numeric_fn);
  Tcarrier=carrierLock.Tcarrier;Fcarrier=carrierLock.Fcarrier;carrierPairStart=carrierLock.pairI;carrierPairEnd=carrierLock.pairJ;

  % Keep only pulses that participate in the locked carrier-period cluster.
  % This removes threshold crossings caused by unrelated acquisition noise while
  % preserving valid carrier edges even when spurious edges occur between them.
  carrierPulse=false(nPulses,1);
  carrierPulse(carrierPairStart)=true; carrierPulse(carrierPairEnd)=true;
  pulseStart=pulseStart(carrierPulse); pulseEnd=pulseEnd(carrierPulse); pulseWidth=pulseWidth(carrierPulse);
  nPulses=numel(pulseStart);
  nPulsesLocked=nPulses;
  nPulsesRejected=nPulsesDetected-nPulsesLocked;
  if (nPulses<3), error('gxtxt.ir_waveform: too few carrier-locked pulses detected (%d)',nPulses); endif
  pulseWidthMedian=gxtxt_ir_numeric(numeric_fn,'median',pulseWidth); dutyCarrier=pulseWidthMedian/Tcarrier*100;

  gxtxt_progress_stage('mark_space','Reconstructing MARK / SPACE sequence','indeterminate');
  gapThreshold=acfg.burstGapPeriods*Tcarrier;
  gapBetween=pulseStart(2:end)-pulseEnd(1:end-1);
  newBurst=[true; gapBetween>gapThreshold];
  burstStartPulse=find(newBurst); burstEndPulse=[burstStartPulse(2:end)-1; nPulses];
  nBursts=numel(burstStartPulse);
  if (nBursts<1), error('gxtxt.ir_waveform: no MARK bursts detected'); endif
  burstStart=zeros(nBursts,1); burstEnd=zeros(nBursts,1); burstDuration=zeros(nBursts,1);
  burstCycles=zeros(nBursts,1); burstMeanPulseWidth=zeros(nBursts,1);
  for k=1:nBursts
    i1=burstStartPulse(k); i2=burstEndPulse(k);
    burstStart(k)=pulseStart(i1); burstEnd(k)=pulseEnd(i2)+dt;
    burstDuration(k)=burstEnd(k)-burstStart(k); burstCycles(k)=i2-i1+1;
    burstMeanPulseWidth(k)=gxtxt_ir_numeric(numeric_fn,'mean',pulseWidth(i1:i2));
  endfor
  if (nBursts>=2), spaceDuration=burstStart(2:end)-burstEnd(1:end-1); else spaceDuration=[]; endif
  commandStart=burstStart(1); commandEnd=burstEnd(end); commandDuration=commandEnd-commandStart;
  burstCyclesFromDuration=round(burstDuration/Tcarrier);

  gxtxt_progress_stage('analog_chain','Building analog-chain comparison metrics','indeterminate');
  analog_chain = gxtxt_ir_analog_chain(t,v,signal_name,comparison_sources,Fcarrier,commandStart,commandEnd,acfg.thresholdFraction,acfg.noiseSigmaMultiplier,acfg.maxOverviewPoints,acfg.normalizationMethod,numeric_fn);

  gxtxt_progress_stage('clustering','Grouping recurring MARK / SPACE durations','indeterminate');
  markLegacy=cluster_durations(burstDuration*1e6,acfg.clusterRelativeTolerance,Inf,numeric_fn);
  spaceLegacy=cluster_durations(spaceDuration*1e6,acfg.clusterRelativeTolerance,Inf,numeric_fn);
  markGuarded=cluster_durations(burstDuration*1e6,acfg.clusterRelativeTolerance,acfg.clusterMaxRatio,numeric_fn);
  spaceGuarded=cluster_durations(spaceDuration*1e6,acfg.clusterRelativeTolerance,acfg.clusterMaxRatio,numeric_fn);
  if (acfg.clusterGuard), markSelected=markGuarded; spaceSelected=spaceGuarded;
  else markSelected=markLegacy; spaceSelected=spaceLegacy; endif

  [eventType,eventStart,eventEnd,eventDuration,eventCycles] = build_events(burstStart,burstEnd,burstDuration,burstCycles);

  gxtxt_progress_stage('writing_results','Writing numerical outputs','indeterminate');
  write_events(fullfile(outdir,'eventi_mark_space.csv'),eventType,eventStart,eventEnd,eventDuration,eventCycles);
  write_bursts(fullfile(outdir,'burst.csv'),burstStart,burstEnd,burstDuration,burstCycles,burstCyclesFromDuration,burstMeanPulseWidth);
  write_clusters(fullfile(outdir,'duration_clusters_comparison.csv'),markGuarded,spaceGuarded,markLegacy,spaceLegacy);
  write_analog_chain_summary(fullfile(outdir,'analog_chain_comparison.csv'),analog_chain);
  write_analog_chain_timeseries(fullfile(outdir,'analog_chain_timeseries.csv'),analog_chain,numeric_fn);
  write_summary(fullfile(outdir,'riepilogo_VIR.txt'),cfg,numel(v),Fs,t(end)-t(1),P,Tcarrier,Fcarrier,pulseWidthMedian,dutyCarrier,nPulsesDetected,nPulsesLocked,nPulsesRejected,nBursts,commandStart,commandEnd,commandDuration,acfg,markSelected,spaceSelected,markLegacy,spaceLegacy,analog_chain,carrierLock);
  write_analysis_manifest(fullfile(outdir,'ir_analysis_manifest.ini'),cfg,signal_name,Fcarrier,carrierLock,nPulsesDetected,nPulsesLocked,nBursts,commandStart,commandEnd);

  [overview_t,overview_vMin,overview_vMax]=minmax_overview_fast(t,v,acfg.maxOverviewPoints);
  [~,iLongest]=max(burstCycles);
  t0zoom=burstStart(iLongest); t1zoom=min(burstEnd(iLongest),t0zoom+acfg.carrierPeriodsToPlot*Tcarrier);
  idxZoom=find(t>=t0zoom & t<=t1zoom); carrier_t_us=(t(idxZoom)-t0zoom)*1e6; carrier_v=v(idxZoom);
  [logic_t,logic_y]=build_logic_trace(burstStart,burstEnd); logic_t_ms=(logic_t-commandStart)*1000;
  overview_t_ms=overview_t*1000; overview_xlim_ms=[t(1) t(end)]*1000;
  save('-binary',fullfile(outdir,'render_cache.mat'),'overview_t_ms','overview_vMin','overview_vMax','overview_xlim_ms', ...
       'carrier_t_us','carrier_v','logic_t_ms','logic_y','burstDuration','spaceDuration','nBursts','Fcarrier', ...
       'signal_name','commandStart','commandEnd','commandDuration','analog_chain','carrierLock','nPulsesDetected','nPulsesLocked','nPulsesRejected');

  gxtxt_progress_stage('rendering','Rendering configured graphs','indeterminate');
  if(!isempty(strtrim(ini_get(cfg,'runtime.session','')))&&exist(fullfile(session,'metadata','manifest.ini'),'file')==2)
    display_cache=load(fullfile(outdir,'render_cache.mat'));
    D=gxtxt_ir_publish_plots(session,primary_dataset_id,display_cache);
    gxtxt_ir_render_public(outdir,cfg,display_cache,D);
  endif
  gxtxt_progress_complete('done','IR waveform analysis completed');
  fprintf('[gxtxt.ir_waveform] samples=%d carrier=%.6f_kHz source=%s pulses=%d/%d rejected=%d MARK=%d duration=%.6f_ms comparisons=%d\n',numel(v),Fcarrier/1e3,carrierLock.source,nPulsesLocked,nPulsesDetected,nPulsesRejected,nBursts,commandDuration*1e3,max(0,numel(analog_chain)-1));
endfunction

function acfg=analysis_config(cfg)
  acfg.nominalCarrier_Hz=get_num(cfg,'config.nominal_carrier_hz',38000);
  acfg.carrierLockTolerance=get_num(cfg,'config.carrier_lock_tolerance',0.20);
  acfg.carrierSearchMode=lower(strtrim(ini_get(cfg,'config.carrier_search_mode','nominal_recovery')));
  acfg.carrierSearchMin_Hz=get_num(cfg,'config.carrier_search_min_hz',33000);
  acfg.carrierSearchMax_Hz=get_num(cfg,'config.carrier_search_max_hz',60000);
  acfg.comparisonPlotMode=lower(strtrim(ini_get(cfg,'config.comparison_plot_mode','stacked')));
  acfg.normalizationMethod=lower(strtrim(ini_get(cfg,'config.normalization_method','peak')));
  mode=lower(strtrim(ini_get(cfg,'config.pretest_mode','auto')));
  if (strcmp(mode,'manual'))
    acfg.pretestWindows_ms=[get_num(cfg,'config.manual_pre_ms',5),get_num(cfg,'config.manual_post_ms',40)];
    acfg.pretestAuto=false;
  else
    acfg.pretestWindows_ms=[5 30;10 60;20 120;40 250]; acfg.pretestAuto=true;
  endif
  acfg.minSignalAmplitude_V=get_num(cfg,'config.min_signal_amplitude_v',0.050);
  acfg.thresholdFraction=get_num(cfg,'config.threshold_fraction',0.30);
  acfg.noiseSigmaMultiplier=get_num(cfg,'config.noise_sigma_multiplier',8);
  acfg.burstGapPeriods=get_num(cfg,'config.burst_gap_periods',3.0);
  acfg.clusterRelativeTolerance=get_num(cfg,'config.cluster_relative_tolerance',0.20);
  acfg.clusterGuard=parse_bool(ini_get(cfg,'config.cluster_guard','1'),true);
  acfg.clusterMaxRatio=get_num(cfg,'config.cluster_max_ratio',1.60);
  acfg.maxOverviewPoints=round(get_num(cfg,'config.max_overview_points',6000));
  acfg.carrierPeriodsToPlot=round(get_num(cfg,'config.carrier_periods_to_plot',12));
endfunction

function validate_analysis_config(c)
  if (!isfinite(c.nominalCarrier_Hz)||c.nominalCarrier_Hz<=0), error('nominal_carrier_hz must be > 0'); endif
  if (!isfinite(c.carrierLockTolerance)||c.carrierLockTolerance<=0||c.carrierLockTolerance>=0.50), error('carrier_lock_tolerance must be > 0 and < 0.50'); endif
  if (!any(strcmp(c.carrierSearchMode,{'nominal_recovery','strict_nominal','automatic'}))), error('carrier_search_mode must be nominal_recovery, strict_nominal or automatic'); endif
  if (!isfinite(c.carrierSearchMin_Hz)||!isfinite(c.carrierSearchMax_Hz)||c.carrierSearchMin_Hz<=0||c.carrierSearchMax_Hz<=c.carrierSearchMin_Hz), error('carrier search range is invalid'); endif
  if (!any(strcmp(c.comparisonPlotMode,{'stacked','overlay'}))), error('comparison_plot_mode must be stacked or overlay'); endif
  if (!any(strcmp(c.normalizationMethod,{'peak','vpp','rms'}))), error('normalization_method must be peak, vpp or rms'); endif
  if (any(!isfinite(c.pretestWindows_ms(:)))||any(c.pretestWindows_ms(:)<0)), error('pretest window values must be finite and >= 0'); endif
  if (!isfinite(c.minSignalAmplitude_V)||c.minSignalAmplitude_V<=0), error('min_signal_amplitude_v must be > 0'); endif
  if (!isfinite(c.thresholdFraction)||c.thresholdFraction<=0||c.thresholdFraction>=1), error('threshold_fraction must be between 0 and 1'); endif
  if (!isfinite(c.noiseSigmaMultiplier)||c.noiseSigmaMultiplier<0), error('noise_sigma_multiplier must be >= 0'); endif
  if (!isfinite(c.burstGapPeriods)||c.burstGapPeriods<=0), error('burst_gap_periods must be > 0'); endif
  if (!isfinite(c.clusterRelativeTolerance)||c.clusterRelativeTolerance<0), error('cluster_relative_tolerance must be >= 0'); endif
  if (!isfinite(c.clusterMaxRatio)||c.clusterMaxRatio<1), error('cluster_max_ratio must be >= 1'); endif
  if (c.maxOverviewPoints<100), error('max_overview_points must be >= 100'); endif
  if (c.carrierPeriodsToPlot<1), error('carrier_periods_to_plot must be >= 1'); endif
endfunction

function P=adaptive_pretest(t,v,c,numeric_fn)
  lastReason='no attempt executed'; W=c.pretestWindows_ms;
  for q=1:rows(W)
    idx=find(t>=-W(q,1)/1000 & t<=W(q,2)/1000);
    if (isempty(idx)), lastReason='no samples in the requested window'; continue; endif
    try
      P=pretest_signal(t(idx),v(idx),c,numeric_fn); P.pretestWindowPre_ms=W(q,1); P.pretestWindowPost_ms=W(q,2); P.pretestAttempt=q; return;
    catch err
      lastReason=err.message;
    end_try_catch
  endfor
  if (c.pretestAuto), error('PRETEST FAILED through maximum automatic window (-%.1f ... +%.1f ms): %s',W(end,1),W(end,2),lastReason);
  else error('PRETEST FAILED in manual window (-%.1f ... +%.1f ms): %s',W(1,1),W(1,2),lastReason); endif
endfunction

function P=pretest_signal(t,v,c,numeric_fn)
  valid=isfinite(t)&isfinite(v); t=t(valid);v=v(valid);
  if (numel(v)<1000), error('only %d valid numeric samples',numel(v)); endif
  idxPre=find(t<0); if (numel(idxPre)<100), nBase=min(numel(v),max(1000,round(0.20*numel(v)))); idxPre=1:nBase; endif
  baseline=gxtxt_ir_numeric(numeric_fn,'median',v(idxPre)); noiseMAD=gxtxt_ir_numeric(numeric_fn,'median',abs(v(idxPre)-baseline)); noiseSigma=1.4826*noiseMAD; if(!isfinite(noiseSigma)),noiseSigma=0;endif
  idxPost=find(t>=0); if(isempty(idxPost)),idxPost=1:numel(v);endif
  vPost=v(idxPost); vMin=min(vPost);vMax=max(vPost);ampDown=baseline-vMin;ampUp=vMax-baseline;
  if (ampDown>=ampUp), polaritySign=-1;polarityText='downward pulses';signalAmplitude=ampDown;sig=baseline-v;
  else polaritySign=1;polarityText='upward pulses';signalAmplitude=ampUp;sig=v-baseline;endif
  sig(sig<0)=0;
  if(!isfinite(signalAmplitude)||signalAmplitude<c.minSignalAmplitude_V),error('detected excursion %.6f V below minimum %.6f V',signalAmplitude,c.minSignalAmplitude_V);endif
  threshold=max(c.thresholdFraction*signalAmplitude,c.noiseSigmaMultiplier*noiseSigma);
  if(threshold>=0.90*signalAmplitude),error('threshold %.6f V too close to signal amplitude %.6f V',threshold,signalAmplitude);endif
  logic=sig>=threshold; d=diff([false;logic;false]); rise=find(d==1);
  if(numel(rise)<5),error('only %d edges detected',numel(rise));endif
  dtv=diff(t); dtv=dtv(isfinite(dtv)&dtv>0);
  if(isempty(dtv)),error('invalid time axis during carrier pretest');endif
  dtLocal=gxtxt_ir_numeric(numeric_fn,'median',dtv);L=gxtxt_ir_carrier_search(t(rise),c.nominalCarrier_Hz,c.carrierSearchMode,c.carrierLockTolerance,c.carrierSearchMin_Hz,c.carrierSearchMax_Hz,dtLocal,numeric_fn);
  carrierPulse=false(numel(rise),1);carrierPulse(L.pairI)=true;carrierPulse(L.pairJ)=true;
  P=struct('baseline',baseline,'noiseSigma',noiseSigma,'vMin',vMin,'vMax',vMax,'polaritySign',polaritySign,'polarityText',polarityText,'signalAmplitude',signalAmplitude,'threshold',threshold,'fronts',numel(rise),'carrierIntervals',numel(L.pairI),'carrierFronts',sum(carrierPulse),'Tcarrier',L.Tcarrier,'Fcarrier',L.Fcarrier,'carrierSource',L.source);
endfunction

function C=resolve_comparison_sources(cfg,session,primaryPath,timeName,primaryName)
  C=struct('name',{},'path',{},'time_name',{});selected={};
  for slot=1:7
    raw=strtrim(ini_get(cfg,sprintf('bindings.compare%d',slot),''));
    if(isempty(raw)||strcmpi(raw,'auto')),continue;endif
    [source,name]=binding_parts(raw,'primary',cfg);
    if(isempty(name)||(strcmp(source,'primary')&&strcmp(name,primaryName))),continue;endif
    key=[source '.' name];if(any(strcmp(selected,key))),continue;endif;selected{end+1}=key;
    if(strcmp(source,'primary'))
      names=csv_header_names(primaryPath);
      if(any(strcmp(names,name)))
        path=primaryPath;tcol=choose_time_column(path,timeName);
      else
        % Historical unqualified comparison bindings may name a separate
        % canonical channel file in the same Session. Keep that fallback for
        % saved Sessions while new source-qualified bindings remain explicit.
        [path,tcol]=find_signal_dataset(session,primaryPath,timeName,name);
      endif
    else
      path=strtrim(ini_get(cfg,['analysis_source.' source '.path'],''));
      if(isempty(path))
        % Compatibility with old unqualified/session-wide comparison bindings.
        [path,tcol]=find_signal_dataset(session,primaryPath,timeName,name);
      else
        if(exist(path,'file')!=2),error('gxtxt.ir_waveform: Analysis Source %s file is missing: %s',source,path);endif
        names=csv_header_names(path);
        if(!any(strcmp(names,name))),error('gxtxt.ir_waveform: Analysis Source %s Dataset does not contain variable %s',source,name);endif
        tcol=choose_time_column(path,timeName);
      endif
    endif
    C(end+1).name=name;C(end).path=path;C(end).time_name=tcol;
  endfor
endfunction

function tcol=choose_time_column(path,preferred)
  names=csv_header_names(path);
  if(!isempty(preferred)&&any(strcmp(names,preferred))),tcol=preferred;
  elseif(any(strcmp(names,'time_s'))),tcol='time_s';
  else,error('gxtxt.ir_waveform: Dataset %s has no usable time variable (%s or time_s)',path,preferred);endif
endfunction

function [source,name]=binding_parts(value,defaultSource,cfg)
  value=strtrim(value);source=defaultSource;name=value;
  if(isempty(value)||strcmpi(value,'auto')),name='';return;endif
  dot=find(value=='.',1);
  if(!isempty(dot)&&dot>1&&dot<numel(value))
    candidate=strtrim(value(1:dot-1));
    ids=regexp(ini_get(cfg,'analysis_sources.ids','primary'),'[;,]','split');
    for k=1:numel(ids),ids{k}=strtrim(ids{k});endfor
    if(any(strcmp(ids,candidate)))
      source=candidate;name=strtrim(value(dot+1:end));
    endif
  endif
endfunction

function [path,tcol]=find_signal_dataset(session,primaryPath,timeName,signalName)
  candidates={primaryPath};channelDir=fullfile(session,'channels');
  if(exist(channelDir,'dir')==7),g=glob(fullfile(channelDir,'*_canonical.csv'));for k=1:numel(g),candidates{end+1}=g{k};endfor;endif
  datasetDir=fullfile(session,'datasets');if(exist(datasetDir,'dir')==7),g=glob(fullfile(datasetDir,'*.csv'));for k=1:numel(g),candidates{end+1}=g{k};endfor;endif
  checked={};matches={};matchTime={};
  for k=1:numel(candidates)
    p=candidates{k};if(any(strcmp(checked,p))),continue;endif;checked{end+1}=p;if(exist(p,'file')!=2),continue;endif
    try,names=csv_header_names(p);catch,continue;end_try_catch
    if(!any(strcmp(names,signalName))),continue;endif
    if(any(strcmp(names,timeName))),tc=timeName;elseif(any(strcmp(names,'time_s'))),tc='time_s';else continue;endif
    matches{end+1}=p;matchTime{end+1}=tc;
  endfor
  if(isempty(matches)),error('gxtxt.ir_waveform: comparison trace %s not found in canonical datasets for this session',signalName);endif
  path=matches{1};tcol=matchTime{1};
endfunction

function names=csv_header_names(path)
  fid=fopen(path,'r');if(fid<0),error('Cannot open dataset: %s',path);endif
  header=fgetl(fid);fclose(fid);if(!ischar(header)),error('Dataset is empty: %s',path);endif
  counts=[numel(strfind(header,',')),numel(strfind(header,';')),numel(strfind(header,sprintf('\t')))];[~,di]=max(counts);
  if(di==2),delim=';';elseif(di==3),delim=sprintf('\t');else delim=',';endif
  names=strsplit(strtrim(header),delim);names=cellfun(@(x)strtrim(strrep(x,'"','')),names,'UniformOutput',false);
endfunction

function [types,starts,ends,durs,cycles]=build_events(bs,be,bd,bc)
  types={};starts=[];ends=[];durs=[];cycles=[];ev=0;
  for k=1:numel(bs)
    ev++;types{ev,1}='MARK';starts(ev,1)=bs(k);ends(ev,1)=be(k);durs(ev,1)=bd(k);cycles(ev,1)=bc(k);
    if(k<numel(bs)),ev++;types{ev,1}='SPACE';starts(ev,1)=be(k);ends(ev,1)=bs(k+1);durs(ev,1)=bs(k+1)-be(k);cycles(ev,1)=0;endif
  endfor
endfunction

function [lt,ly]=build_logic_trace(bs,be)
  lt=[];ly=[];
  for k=1:numel(bs)
    lt=[lt;bs(k);bs(k);be(k);be(k)];ly=[ly;0;1;1;0];
    if(k<numel(bs)),lt=[lt;bs(k+1)];ly=[ly;0];endif
  endfor
endfunction

function C=cluster_durations(durations,tolRel,maxRatio,numeric_fn)
  if(isempty(maxRatio)),maxRatio=Inf;endif
  x=durations(isfinite(durations)&durations>0); C=struct('centro',{},'mediana',{},'minimo',{},'massimo',{},'conteggio',{});
  if(isempty(x)),return;endif
  x=sort(x(:));groups={x(1)};g=1;
  for k=2:numel(x)
    center=gxtxt_ir_numeric(numeric_fn,'median',groups{g});tol=max(1.0,tolRel*center);candidateMin=min(min(groups{g}),x(k));candidateMax=max(max(groups{g}),x(k));
    spanOk=isinf(maxRatio)||(candidateMin>0&&candidateMax/candidateMin<=maxRatio);
    if(abs(x(k)-center)<=tol&&spanOk),groups{g}(end+1,1)=x(k);else g++;groups{g}=x(k);endif
  endfor
  for k=1:numel(groups),z=groups{k};C(k).centro=gxtxt_ir_numeric(numeric_fn,'mean',z);C(k).mediana=gxtxt_ir_numeric(numeric_fn,'median',z);C(k).minimo=min(z);C(k).massimo=max(z);C(k).conteggio=numel(z);endfor
endfunction

function [tb,vMin,vMax]=minmax_overview_fast(t,v,maxPoints)
  N=numel(v);binSize=max(1,ceil(N/maxPoints));nFull=floor(N/binSize);
  if(nFull<1),tb=t;vMin=v;vMax=v;return;endif
  nUsed=nFull*binSize;V=reshape(v(1:nUsed),binSize,nFull);vMin=min(V,[],1)';vMax=max(V,[],1)';idx1=(0:nFull-1)'*binSize+1;idx2=idx1+binSize-1;tb=(t(idx1)+t(idx2))/2;
  if(nUsed<N),tb(end+1,1)=(t(nUsed+1)+t(end))/2;vMin(end+1,1)=min(v(nUsed+1:end));vMax(end+1,1)=max(v(nUsed+1:end));endif
endfunction

function write_events(path,types,s,e,d,c)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'event,type,start_s,end_s,duration_us,carrier_cycles\n');
    for k=1:numel(types),fprintf(fid,'%d,%s,%.12g,%.12g,%.6f,%d\n',k,types{k},s(k),e(k),d(k)*1e6,c(k));endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_bursts(path,s,e,d,c,cd,pw)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'burst,start_s,end_s,duration_us,carrier_cycles,cycles_from_duration,mean_pulse_width_us\n');
    for k=1:numel(s),fprintf(fid,'%d,%.12g,%.12g,%.6f,%d,%d,%.6f\n',k,s(k),e(k),d(k)*1e6,c(k),cd(k),pw(k)*1e6);endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_clusters(path,mg,sg,ml,sl)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'method,event_type,group,median_us,mean_us,min_us,max_us,count,max_min_ratio\n');
    write_cluster_rows(fid,'guarded_span_v1','MARK',mg);write_cluster_rows(fid,'guarded_span_v1','SPACE',sg);write_cluster_rows(fid,'legacy_running_median_v1','MARK',ml);write_cluster_rows(fid,'legacy_running_median_v1','SPACE',sl);
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function write_cluster_rows(fid,method,eventType,C)
  for k=1:numel(C),if(C(k).minimo>0),ratio=C(k).massimo/C(k).minimo;else ratio=NaN;endif;fprintf(fid,'%s,%s,%d,%.12g,%.12g,%.12g,%.12g,%d,%.12g\n',method,eventType,k,C(k).mediana,C(k).centro,C(k).minimo,C(k).massimo,C(k).conteggio,ratio);endfor
endfunction

function write_analog_chain_summary(path,A)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'trace,role,samples,baseline_V,noise_sigma_V,polarity,Vmin_V,Vmax_V,Vpp_V,carrier_amplitude_V,threshold_V,median_margin_V,relative_gain_vs_primary,normalization_method,normalization_scale\n');
    for k=1:numel(A)
      if(k==1),role='primary';else role='comparison';endif
      fprintf(fid,'%s,%s,%d,%.12g,%.12g,%s,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%s,%.12g\n',csv_atom(A(k).name),role,A(k).samples,A(k).baseline,A(k).noiseSigma,A(k).polarityText,A(k).vMin,A(k).vMax,A(k).vpp,A(k).carrierAmplitude,A(k).threshold,A(k).marginMedian,A(k).relativeGainMedian,A(k).normalizationMethod,A(k).normalizationScale);
    endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_analog_chain_timeseries(path,A,numeric_fn)
  if(isempty(A)),return;endif
  t=A(1).env_t_ms(:);E=cell(numel(A),1);M=cell(numel(A),1);
  E{1}=A(1).env_v(:);M{1}=A(1).margin_v(:);
  for k=2:numel(A)
    E{k}=gxtxt_ir_numeric(numeric_fn,'interpolate',A(k).env_t_ms,A(k).env_v,t);
    M{k}=gxtxt_ir_numeric(numeric_fn,'interpolate',A(k).margin_t_ms,A(k).margin_v,t);
  endfor
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'time_ms');
    for k=1:numel(A),n=field_atom(A(k).name);fprintf(fid,',%s_envelope_V,%s_margin_V,%s_gain_vs_primary',n,n,n);endfor
    fprintf(fid,'\n');
    for i=1:numel(t)
      fprintf(fid,'%.12g',t(i));
      for k=1:numel(A)
        ev=E{k}(i);mv=M{k}(i);gv=A(k).gain_v(i);
        fprintf(fid,',%.12g,%.12g,%.12g',ev,mv,gv);
      endfor
      fprintf(fid,'\n');
    endfor
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_analysis_manifest(path,cfg,signalName,Fc,L,nDetected,nLocked,nBursts,cs,ce)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'[ir_analysis]\nmodule_id=gxtxt.ir_waveform\nmodule_version=3.6.2\n');
    fprintf(fid,'dataset_id=%s\nsignal=%s\n',primary_dataset_id(cfg),signalName);
    fprintf(fid,'events_file=eventi_mark_space.csv\nsummary_file=riepilogo_VIR.txt\nanalog_chain_file=analog_chain_comparison.csv\n');
    fprintf(fid,'carrier_hz=%.12g\ncarrier_nominal_hz=%.12g\ncarrier_source=%s\ncarrier_quality=%s\ncarrier_deviation_percent=%.9g\n',Fc,L.nominalHz,L.source,L.qualityText,L.deviationPercent);
    fprintf(fid,'detected_pulses=%d\nlocked_pulses=%d\nmark_bursts=%d\ncommand_start_s=%.12g\ncommand_end_s=%.12g\n',nDetected,nLocked,nBursts,cs,ce);
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction

function write_summary(path,cfg,N,Fs,dur,P,Tc,Fc,pw,duty,nDetected,nLocked,nRejected,nB,cs,ce,cd,c,ms,ss,ml,sl,A,L)
  fid=fopen(path,'w');if(fid<0),error('Cannot write %s',path);endif;unwind_protect
    fprintf(fid,'GX-TXT IR waveform / MARK-SPACE analysis\n');fprintf(fid,'Module: gxtxt.ir_waveform v3.6.2\n');fprintf(fid,'Dataset: %s\n',primary_dataset_id(cfg));fprintf(fid,'Signal binding: %s\n',ini_get(cfg,'bindings.signal',''));fprintf(fid,'Samples: %d\nSample rate: %.6f MSa/s\nAcquired duration: %.6f ms\n',N,Fs/1e6,dur*1e3);
    fprintf(fid,'\nSIGNAL\nBaseline: %.9g V\nPolarity: %s\nPretest amplitude: %.9g V\nNoise sigma: %.9g V\nThreshold: %.9g V\nPretest window: -%.3f ... +%.3f ms\n',P.baseline,P.polarityText,P.signalAmplitude,P.noiseSigma,P.threshold,P.pretestWindowPre_ms,P.pretestWindowPost_ms);
    fprintf(fid,'\nCARRIER\nNominal frequency: %.6f kHz\nMeasured frequency: %.6f kHz\nDeviation from nominal: %+.3f %%\nSearch mode: %s\nLock source: %s\nLock quality: %s\nAutomatic search range: %.3f ... %.3f kHz\nLock tolerance around nominal: +/- %.3f %%\nMedian period: %.6f us\nMedian pulse width: %.6f us\nEstimated duty cycle: %.3f %%\n',c.nominalCarrier_Hz/1e3,Fc/1e3,L.deviationPercent,c.carrierSearchMode,L.source,L.qualityText,c.carrierSearchMin_Hz/1e3,c.carrierSearchMax_Hz/1e3,100*c.carrierLockTolerance,Tc*1e6,pw*1e6,duty);
    if(!strcmp(L.source,'nominal')),fprintf(fid,'WARNING: carrier lock did not come from the nominal search window; analysis continued with the measured carrier.\n');endif
    fprintf(fid,'\nPULSES\nTotal detected pulses: %d\nValid carrier pulses: %d\nRejected/spurious pulses: %d\n',nDetected,nLocked,nRejected);
    fprintf(fid,'\nANALOG CHAIN\nTraces: %d (1 primary + %d comparison)\nNormalization method for optional normalized graph: %s\n',numel(A),max(0,numel(A)-1),c.normalizationMethod);
    for k=1:numel(A),fprintf(fid,'%d. %s: baseline=%.9g V, Vpp=%.9g V, carrier_amp=%.9g V, noise_sigma=%.9g V, threshold=%.9g V, margin=%.9g V, gain_vs_primary=%.9g\n',k,A(k).name,A(k).baseline,A(k).vpp,A(k).carrierAmplitude,A(k).noiseSigma,A(k).threshold,A(k).marginMedian,A(k).relativeGainMedian);endfor
    fprintf(fid,'\nCOMMAND\nMARK bursts: %d\nStart: %.6f ms\nEnd: %.6f ms\nDuration: %.6f ms\n',nB,cs*1e3,ce*1e3,cd*1e3);
    fprintf(fid,'\nMARK DURATION GROUPS [us]\nSpan guard: %s; maximum max/min ratio: %.6g\n',bool_text(c.clusterGuard),c.clusterMaxRatio);write_cluster_summary(fid,ms);
    fprintf(fid,'\nSPACE DURATION GROUPS [us]\n');write_cluster_summary(fid,ss);
    fprintf(fid,'\nLEGACY MARK GROUPS [us] - running median only\n');write_cluster_summary(fid,ml);
    fprintf(fid,'\nLEGACY SPACE GROUPS [us] - running median only\n');write_cluster_summary(fid,sl);
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function write_cluster_summary(fid,C)
  if(isempty(C)),fprintf(fid,'no class available\n');return;endif
  fprintf(fid,'%6s %12s %12s %12s %12s %8s\n','Group','Median','Mean','Min','Max','N');
  for k=1:numel(C),fprintf(fid,'%6d %12.3f %12.3f %12.3f %12.3f %8d\n',k,C(k).mediana,C(k).centro,C(k).minimo,C(k).massimo,C(k).conteggio);endfor
endfunction
function s=bool_text(b),if(b),s='enabled';else s='disabled';endif;endfunction
function s=csv_atom(s),s=strrep(s,'"','""');if(any(s==',')||any(s=='"')),s=['"' s '"'];endif;endfunction
function s=field_atom(s),s=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(s)||!isletter(s(1))),s=['trace_' s];endif;endfunction

function id=primary_dataset_id(cfg)
  id=strtrim(ini_get(cfg,'analysis_source.primary.dataset_id',ini_get(cfg,'dataset.id','')));
endfunction

function [x,y]=read_named_csv2(path,xname,yname)
  fid=fopen(path,'r');if(fid<0),error('Cannot open dataset: %s',path);endif;header=fgetl(fid);fclose(fid);if(!ischar(header)),error('Dataset is empty');endif
  counts=[numel(strfind(header,',')),numel(strfind(header,';')),numel(strfind(header,sprintf('\t')))];[~,di]=max(counts);if(di==2),delim=';';elseif(di==3),delim=sprintf('\t');else delim=',';endif
  names=csv_header_names(path);ix=find(strcmp(names,xname),1);iy=find(strcmp(names,yname),1);
  if(isempty(ix)||isempty(iy)),error('Required dataset columns not found: %s, %s',xname,yname);endif
  data=dlmread(path,delim,1,0);x=data(:,ix);y=data(:,iy);
endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function d=read_ini(path),d=struct();sec='';fid=fopen(path,'r');if(fid<0),error('Cannot open INI: %s',path);endif;unwind_protect;while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif;tok=regexp(line,'^\[(.+)\]$','tokens','once');if(!isempty(tok)),sec=tok{1};continue;endif;eq=find(line=='=',1);if(isempty(eq)),continue;endif;key=strtrim(line(1:eq-1));val=line(eq+1:end);d.(make_key([sec '.' key]))=ini_unescape(val);endwhile;unwind_protect_cleanup;fclose(fid);end_unwind_protect;endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function s=ini_unescape(s),s=strrep(s,'\\n',sprintf('\n'));s=strrep(s,'\\r',sprintf('\r'));s=strrep(s,'\\\\','\\');endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
function v=get_num(d,key,def),v=str2double(ini_get(d,key,num2str(def,17)));if(!isfinite(v)),v=def;endif;endfunction
function b=parse_bool(s,def),s=lower(strtrim(s));if(any(strcmp(s,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(s,{'0','false','no','off'}))),b=false;else b=def;endif;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);endif;endfunction

function fn=ir_numeric_binding(cfg)
  prefix='public_api.NUMERIC_API_v1.';
  provider=strtrim(ini_get(cfg,[prefix 'module_id'],''));version=strtrim(ini_get(cfg,[prefix 'api_version'],''));
  entry=strtrim(ini_get(cfg,[prefix 'octave_entrypoint'],''));fn=strtrim(ini_get(cfg,[prefix 'octave_function'],''));
  caps=parse_list(ini_get(cfg,[prefix 'capabilities'],''));
  required={'interpolation','descriptive_statistics','linear_reductions'};
  if(!strcmp(provider,'math.numeric')||!strcmp(version,'1')||isempty(fn)||exist(entry,'file')!=2||!all(ismember(required,caps)))
    error('gxtxt.ir_waveform: public NUMERIC_API_v1 numerical binding is unavailable');
  endif
  addpath(fileparts(entry));
  if(exist(fn,'file')!=2),error('gxtxt.ir_waveform: public numeric Octave function is unavailable');endif
endfunction
