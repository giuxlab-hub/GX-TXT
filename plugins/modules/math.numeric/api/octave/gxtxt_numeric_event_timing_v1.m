function out=gxtxt_numeric_event_timing_v1(operation,rising,falling,options)
% Public Numeric owner of descriptive timing from already detected crossings.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isstruct(options)||!isempty(fieldnames(options))),error('GXTXT:Numeric','Event timing has no estimator options');endif
  check_times(rising,2,'reference crossings');rising=rising(:);periods=diff(rising);n=numel(periods);
  period=mean(periods);frequency=1/period;
  out=struct('n',n,'crossing_count',numel(rising),'period_count',n,'method','arithmetic_intercrossing_intervals');
  if(strcmp(operation,'event_period'))
    out.period=period;out.frequency_hz=frequency;return;
  endif
  if(!strcmp(operation,'pulse_timing')),error('GXTXT:Numeric','Unknown event timing operation');endif
  check_times(falling,1,'falling crossings');falling=falling(:);widths=zeros(n,1);count=0;j=1;
  % Same first-following-fall convention as Signal v1, with a monotonic scan
  % rather than rescanning all falling events for every rising event.
  for k=1:n
    while(j<=numel(falling)&&falling(j)<=rising(k)),j+=1;endwhile
    if(j<=numel(falling)&&falling(j)<rising(k+1)),count+=1;widths(count)=falling(j)-rising(k);endif
  endfor
  if(count==0),error('GXTXT:Numeric','No complete pulse width');endif
  width=mean(widths(1:count));jitter=NaN;if(n>=2),jitter=std(periods,0);endif
  out.method='complete_pulse_intervals';out.width_count=count;out.period_seconds=period;out.frequency_hz=frequency;
  out.pulse_width_seconds=width;out.duty_cycle=width/period;out.jitter_std_seconds=jitter;
endfunction
function check_times(values,minimum,label)
  if(!isnumeric(values)||!isreal(values)||!isvector(values)||numel(values)<minimum||any(!isfinite(values))||any(diff(values(:))<0))
    error('GXTXT:Numeric','%s must be a finite nondecreasing vector with at least %d entries',label,minimum);
  endif
endfunction
