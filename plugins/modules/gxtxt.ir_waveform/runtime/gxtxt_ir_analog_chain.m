function A = gxtxt_ir_analog_chain(primary_t,primary_v,primary_name,sources,Fcarrier,commandStart,commandEnd,thresholdFraction,noiseSigmaMultiplier,maxOverviewPoints,normalizationMethod,numeric_fn)
% Build reproducible analog-chain comparison metrics and render-ready traces.
% sources is a struct array with name/path/time_name for optional comparison signals.
% SPDX-License-Identifier: GPL-3.0-or-later

  allSources=struct('name',{},'path',{},'time_name',{},'t',{},'v',{});
  allSources(1).name=primary_name;allSources(1).path='';allSources(1).time_name='time_s';allSources(1).t=primary_t(:);allSources(1).v=primary_v(:);
  for k=1:numel(sources)
    [t,v]=read_named_csv_local(sources(k).path,sources(k).time_name,sources(k).name);
    valid=isfinite(t)&isfinite(v);t=t(valid);v=v(valid);[t,ord]=sort(t(:));v=v(ord);
    allSources(end+1).name=sources(k).name;allSources(end).path=sources(k).path;allSources(end).time_name=sources(k).time_name;allSources(end).t=t;allSources(end).v=v;
  endfor

  A=struct('name',{},'path',{},'samples',{},'baseline',{},'noiseSigma',{},'polaritySign',{},'polarityText',{}, ...
    'vMin',{},'vMax',{},'vpp',{},'carrierAmplitude',{},'threshold',{},'marginMedian',{},'relativeGainMedian',{}, ...
    'normalizationMethod',{},'normalizationScale',{},'abs_t_ms',{},'abs_vMin',{},'abs_vMax',{}, ...
    'zero_t_ms',{},'zero_vMin',{},'zero_vMax',{},'norm_t_ms',{},'norm_vMin',{},'norm_vMax',{}, ...
    'env_t_ms',{},'env_v',{},'margin_t_ms',{},'margin_v',{},'gain_t_ms',{},'gain_v',{});

  for k=1:numel(allSources)
    t=allSources(k).t;v=allSources(k).v;
    if(numel(t)<2),error('gxtxt.ir_waveform: comparison trace %s has too few samples',allSources(k).name);endif
    baseIdx=find(t<0);if(numel(baseIdx)<50),nBase=min(numel(v),max(50,round(0.20*numel(v))));baseIdx=1:nBase;endif
    baseline=gxtxt_ir_numeric(numeric_fn,'median',v(baseIdx));noiseMAD=gxtxt_ir_numeric(numeric_fn,'median',abs(v(baseIdx)-baseline));noiseSigma=1.4826*noiseMAD;if(!isfinite(noiseSigma)),noiseSigma=0;endif
    cmdIdx=find(t>=commandStart & t<=commandEnd);if(numel(cmdIdx)<10),cmdIdx=1:numel(t);endif
    vv=v(cmdIdx);vMin=min(vv);vMax=max(vv);vpp=vMax-vMin;ampDown=baseline-vMin;ampUp=vMax-baseline;
    if(ampDown>=ampUp),polaritySign=-1;polarityText='downward';else polaritySign=1;polarityText='upward';endif
    signedZero=v-baseline;active=polaritySign*signedZero;active(active<0)=0;
    signalAmplitude=max(active(cmdIdx));threshold=max(thresholdFraction*signalAmplitude,noiseSigmaMultiplier*noiseSigma);

    dtv=diff(t);dtv=dtv(isfinite(dtv)&dtv>0);if(isempty(dtv)),error('gxtxt.ir_waveform: invalid time axis for %s',allSources(k).name);endif;dt=gxtxt_ir_numeric(numeric_fn,'median',dtv);
    [env_t,env_v]=carrier_envelope(t,active,commandStart,commandEnd,Fcarrier,dt);
    if(isempty(env_v)),env_t=t(cmdIdx);env_v=active(cmdIdx);endif
    peakEnv=max(env_v);activeEnv=env_v>max(threshold,0.20*peakEnv);
    if(any(activeEnv)),carrierAmplitude=gxtxt_ir_numeric(numeric_fn,'median',env_v(activeEnv));marginMedian=gxtxt_ir_numeric(numeric_fn,'median',env_v(activeEnv)-threshold);else carrierAmplitude=peakEnv;marginMedian=peakEnv-threshold;endif

    method=lower(strtrim(normalizationMethod));zcmd=signedZero(cmdIdx);
    if(strcmp(method,'rms')),scale=gxtxt_ir_numeric(numeric_fn,'rms',zcmd);elseif(strcmp(method,'vpp')),scale=vpp;else method='peak';scale=max(abs(zcmd));endif
    if(!isfinite(scale)||scale<=0),scale=1;endif
    normalized=signedZero/scale;

    [abs_t,abs_min,abs_max]=minmax_overview_local(t,v,maxOverviewPoints);
    [zero_t,zero_min,zero_max]=minmax_overview_local(t,signedZero,maxOverviewPoints);
    [norm_t,norm_min,norm_max]=minmax_overview_local(t,normalized,maxOverviewPoints);

    A(k).name=allSources(k).name;A(k).path=allSources(k).path;A(k).samples=numel(v);A(k).baseline=baseline;A(k).noiseSigma=noiseSigma;
    A(k).polaritySign=polaritySign;A(k).polarityText=polarityText;A(k).vMin=vMin;A(k).vMax=vMax;A(k).vpp=vpp;A(k).carrierAmplitude=carrierAmplitude;
    A(k).threshold=threshold;A(k).marginMedian=marginMedian;A(k).relativeGainMedian=NaN;A(k).normalizationMethod=method;A(k).normalizationScale=scale;
    A(k).abs_t_ms=abs_t*1000;A(k).abs_vMin=abs_min;A(k).abs_vMax=abs_max;
    A(k).zero_t_ms=zero_t*1000;A(k).zero_vMin=zero_min;A(k).zero_vMax=zero_max;
    A(k).norm_t_ms=norm_t*1000;A(k).norm_vMin=norm_min;A(k).norm_vMax=norm_max;
    A(k).env_t_ms=env_t*1000;A(k).env_v=env_v;A(k).margin_t_ms=A(k).env_t_ms;A(k).margin_v=env_v-threshold;A(k).gain_t_ms=A(k).env_t_ms;A(k).gain_v=NaN(size(env_v));
  endfor

  % Relative carrier-amplitude gain is evaluated on the primary envelope time grid.
  pt=A(1).env_t_ms(:);pv=A(1).env_v(:);primaryValid=pv>max(A(1).threshold,0.20*max(pv));
  A(1).gain_t_ms=pt;A(1).gain_v=NaN(size(pv));A(1).gain_v(primaryValid)=1;A(1).relativeGainMedian=1;
  for k=2:numel(A)
    cv=gxtxt_ir_numeric(numeric_fn,'interpolate',A(k).env_t_ms(:),A(k).env_v(:),pt);
    valid=primaryValid & isfinite(cv) & pv>0;g=NaN(size(pv));g(valid)=cv(valid)./pv(valid);
    A(k).gain_t_ms=pt;A(k).gain_v=g;if(any(valid)),A(k).relativeGainMedian=gxtxt_ir_numeric(numeric_fn,'median',g(valid));endif
  endfor
endfunction

function [et,ev]=carrier_envelope(t,active,cs,ce,Fc,dt)
  idx=find(t>=cs & t<=ce);if(isempty(idx)),et=[];ev=[];return;endif
  samplesPer=max(1,round((1/Fc)/dt));n=numel(idx);nBins=ceil(n/samplesPer);et=zeros(nBins,1);ev=zeros(nBins,1);
  for b=1:nBins
    a=(b-1)*samplesPer+1;z=min(n,b*samplesPer);ii=idx(a:z);et(b)=(t(ii(1))+t(ii(end)))/2;ev(b)=max(active(ii));
  endfor
endfunction

function [tb,vMin,vMax]=minmax_overview_local(t,v,maxPoints)
  N=numel(v);binSize=max(1,ceil(N/maxPoints));nFull=floor(N/binSize);
  if(nFull<1),tb=t;vMin=v;vMax=v;return;endif
  nUsed=nFull*binSize;V=reshape(v(1:nUsed),binSize,nFull);vMin=min(V,[],1)';vMax=max(V,[],1)';idx1=(0:nFull-1)'*binSize+1;idx2=idx1+binSize-1;tb=(t(idx1)+t(idx2))/2;
  if(nUsed<N),tb(end+1,1)=(t(nUsed+1)+t(end))/2;vMin(end+1,1)=min(v(nUsed+1:end));vMax(end+1,1)=max(v(nUsed+1:end));endif
endfunction

function [x,y]=read_named_csv_local(path,xname,yname)
  fid=fopen(path,'r');if(fid<0),error('Cannot open dataset: %s',path);endif;header=fgetl(fid);fclose(fid);if(!ischar(header)),error('Dataset is empty: %s',path);endif
  counts=[numel(strfind(header,',')),numel(strfind(header,';')),numel(strfind(header,sprintf('\t')))];[~,di]=max(counts);if(di==2),delim=';';elseif(di==3),delim=sprintf('\t');else delim=',';endif
  names=strsplit(strtrim(header),delim);names=cellfun(@(s)strtrim(strrep(s,'"','')),names,'UniformOutput',false);ix=find(strcmp(names,xname),1);iy=find(strcmp(names,yname),1);
  if(isempty(ix)||isempty(iy)),error('Required dataset columns not found: %s, %s',xname,yname);endif
  data=dlmread(path,delim,1,0);x=data(:,ix);y=data(:,iy);
endfunction
