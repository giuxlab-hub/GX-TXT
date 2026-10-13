function L = gxtxt_ir_carrier_search(edgeTimes, nominalHz, mode, tolRel, minHz, maxHz, dt, numeric_fn)
% Robust carrier search for GX-TXT IR waveform analysis.
% The nominal frequency is a prior, never a forced output value.
% SPDX-License-Identifier: GPL-3.0-or-later

  edgeTimes=edgeTimes(:); n=numel(edgeTimes);
  if(n<3),error('gxtxt.ir_waveform: too few edges for carrier search (%d)',n);endif
  if(!isfinite(nominalHz)||nominalHz<=0),error('gxtxt.ir_waveform: invalid nominal carrier frequency');endif
  if(!isfinite(minHz)||!isfinite(maxHz)||minHz<=0||maxHz<=minHz),error('gxtxt.ir_waveform: invalid automatic carrier search range');endif
  mode=lower(strtrim(mode));
  if(!any(strcmp(mode,{'nominal_recovery','strict_nominal','automatic'}))),error('gxtxt.ir_waveform: unknown carrier search mode %s',mode);endif

  nominalT=1/nominalHz;
  nominalOk=false; nominalErr='';
  if(!strcmp(mode,'automatic'))
    try
      [Tc,pairI,pairJ,count,relMad]=lock_near_period(edgeTimes,nominalT,tolRel,dt,numeric_fn);
      nominalOk=true;
    catch err
      nominalErr=err.message;
    end_try_catch
    if(nominalOk)
      L=make_lock(Tc,pairI,pairJ,count,relMad,nominalHz,'nominal',mode,minHz,maxHz,n);
      return;
    endif
    if(strcmp(mode,'strict_nominal'))
      error('gxtxt.ir_waveform: strict nominal carrier lock failed: %s',nominalErr);
    endif
  endif

  [Tc,pairI,pairJ,count,relMad]=lock_automatic(edgeTimes,minHz,maxHz,dt,nominalT,numeric_fn);
  if(strcmp(mode,'automatic')),source='automatic';else source='adaptive_recovery';endif
  L=make_lock(Tc,pairI,pairJ,count,relMad,nominalHz,source,mode,minHz,maxHz,n);
endfunction

function L=make_lock(Tc,pairI,pairJ,count,relMad,nominalHz,source,mode,minHz,maxHz,nEdges)
  Fc=1/Tc; deviation=100*(Fc-nominalHz)/nominalHz;
  coverage=min(1,numel(unique([pairI(:);pairJ(:)]))/max(1,nEdges));
  quality=max(0,min(1,coverage/(1+25*relMad)));
  if(quality>=0.55 && count>=8),qualityText='high';elseif(quality>=0.25 && count>=4),qualityText='medium';else qualityText='low';endif
  L=struct('Tcarrier',Tc,'Fcarrier',Fc,'pairI',pairI(:),'pairJ',pairJ(:),'pairCount',count, ...
    'relativeMAD',relMad,'coverage',coverage,'quality',quality,'qualityText',qualityText, ...
    'nominalHz',nominalHz,'deviationPercent',deviation,'source',source,'mode',mode, ...
    'searchMinHz',minHz,'searchMaxHz',maxHz);
endfunction

function [Tc,pairI,pairJ,count,relMad]=lock_near_period(edgeTimes,targetT,tolRel,dt,numeric_fn)
  n=numel(edgeTimes);lo=(1-tolRel)*targetT;hi=(1+tolRel)*targetT;
  candT=[];candI=[];candJ=[];j=2;
  for i=1:n-1
    if(j<=i),j=i+1;endif
    target=edgeTimes(i)+targetT;
    while(j<n && edgeTimes(j)<target),j++;endwhile
    bestJ=0;bestErr=Inf;bestT=NaN;
    for jj=[j-1,j]
      if(jj<=i||jj>n),continue;endif
      d=edgeTimes(jj)-edgeTimes(i);
      if(d<lo||d>hi),continue;endif
      e=abs(d-targetT);
      if(e<bestErr),bestErr=e;bestJ=jj;bestT=d;endif
    endfor
    if(bestJ>0),candT(end+1,1)=bestT;candI(end+1,1)=i;candJ(end+1,1)=bestJ;endif
  endfor
  if(numel(candT)<3),error('no coherent carrier near %.3f kHz within +/- %.1f %%',1e-3/targetT,100*tolRel);endif
  [selected,Tc]=densest_cluster(candT,targetT,dt,0.04,0.02,numeric_fn);
  if(sum(selected)<3),error('carrier lock produced too few coherent period pairs');endif
  pairI=candI(selected);pairJ=candJ(selected);count=sum(selected);relMad=relative_mad(candT(selected),Tc,numeric_fn);
endfunction

function [Tc,pairI,pairJ,count,relMad]=lock_automatic(edgeTimes,minHz,maxHz,dt,nominalT,numeric_fn)
  n=numel(edgeTimes);Tmin=1/maxHz;Tmax=1/minHz;
  candT=[];candI=[];candJ=[];
  maxLookahead=12;
  for i=1:n-1
    last=min(n,i+maxLookahead);
    for j=i+1:last
      d=edgeTimes(j)-edgeTimes(i);
      if(d>Tmax),break;endif
      if(d>=Tmin),candT(end+1,1)=d;candI(end+1,1)=i;candJ(end+1,1)=j;endif
    endfor
  endfor
  if(numel(candT)<3),error('gxtxt.ir_waveform: no carrier family found in %.1f..%.1f kHz',minHz/1e3,maxHz/1e3);endif

  % Build narrow period families and choose the most populated/coherent one.
  s=sort(candT);groups={s(1)};g=1;
  for k=2:numel(s)
    center=gxtxt_ir_numeric(numeric_fn,'median',groups{g});span=max(4*dt,0.035*center);
    if(abs(s(k)-center)<=span),groups{g}(end+1,1)=s(k);else g++;groups{g}=s(k);endif
  endfor
  best=0;bestScore=-Inf;bestDistance=Inf;
  for k=1:numel(groups)
    z=groups{k};center=gxtxt_ir_numeric(numeric_fn,'median',z);rm=relative_mad(z,center,numeric_fn);countk=numel(z);
    score=countk/(1+40*rm);dist=abs(center-nominalT);
    if(score>bestScore || (abs(score-bestScore)<1e-12 && dist<bestDistance)),best=k;bestScore=score;bestDistance=dist;endif
  endfor
  Tc0=gxtxt_ir_numeric(numeric_fn,'median',groups{best});refine=max(3*dt,0.02*Tc0);selected=abs(candT-Tc0)<=refine;
  if(sum(selected)<3),selected=abs(candT-Tc0)<=max(5*dt,0.035*Tc0);endif
  if(sum(selected)<3),error('gxtxt.ir_waveform: automatic carrier search found no stable period family');endif
  Tc=gxtxt_ir_numeric(numeric_fn,'median',candT(selected));pairI=candI(selected);pairJ=candJ(selected);count=sum(selected);relMad=relative_mad(candT(selected),Tc,numeric_fn);
endfunction

function [selected,Tc]=densest_cluster(candT,targetT,dt,spanFrac,refineFrac,numeric_fn)
  s=sort(candT);span=max(4*dt,spanFrac*targetT);left=1;bestLeft=1;bestRight=0;bestCount=0;bestDistance=Inf;
  for right=1:numel(s)
    while(left<right && s(right)-s(left)>span),left++;endwhile
    count=right-left+1;center=gxtxt_ir_numeric(numeric_fn,'median',s(left:right));distance=abs(center-targetT);
    if(count>bestCount||(count==bestCount&&distance<bestDistance)),bestLeft=left;bestRight=right;bestCount=count;bestDistance=distance;endif
  endfor
  Tc0=gxtxt_ir_numeric(numeric_fn,'median',s(bestLeft:bestRight));refine=max(3*dt,refineFrac*Tc0);selected=abs(candT-Tc0)<=refine;
  if(sum(selected)<3),selected=candT>=s(bestLeft)&candT<=s(bestRight);endif
  Tc=gxtxt_ir_numeric(numeric_fn,'median',candT(selected));
endfunction

function r=relative_mad(x,center,numeric_fn)
  if(isempty(x)||!isfinite(center)||center<=0),r=Inf;return;endif
  r=gxtxt_ir_numeric(numeric_fn,'median',abs(x-center))/center;
endfunction
