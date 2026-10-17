function out=gxtxt_numeric_harmonic_peak_quality_v1(freq,amp,options)
% Public owner of the established local single-bin harmonic estimator.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<3),options=struct();endif
  allowed={'fundamental_mode','fundamental_frequency','max_harmonic','search_half_width_bins','exclude_dc_bins'};
  if(!isstruct(options)||!isscalar(options)||any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric:InvalidPolicy','unknown harmonic quality options');endif
  if(!isnumeric(freq)||!isnumeric(amp)||!isreal(freq)||!isreal(amp)||!isvector(freq)||!isvector(amp)||numel(freq)<3||numel(freq)!=numel(amp)||any(!isfinite(freq(:)))||any(!isfinite(amp(:)))||any(diff(freq(:))<=0)||freq(1)<0||any(amp(:)<0)),error('GXTXT:Numeric:InvalidOperand','increasing nonnegative frequency and nonnegative amplitude vectors are required');endif
  freq=freq(:);amp=amp(:);grid=gxtxt_numeric_v1('grid_info',freq,struct('nonfinite','error'));df=grid.step_median;
  mode=option(options,'fundamental_mode','auto_peak');explicit_f=option(options,'fundamental_frequency',NaN);
  max_harm=option(options,'max_harmonic',10);guard=option(options,'search_half_width_bins',2);dc_bins=option(options,'exclude_dc_bins',1);
  if(!ischar(mode)||!any(strcmp(mode,{'auto_peak','explicit'}))),error('GXTXT:Numeric:InvalidPolicy','unknown fundamental mode');endif
  for value={max_harm,guard,dc_bins}
    v=value{1};if(!isnumeric(v)||!isscalar(v)||!isreal(v)||!isfinite(v)||v!=fix(v)),error('GXTXT:Numeric:InvalidPolicy','harmonic limits must be finite integers');endif
  endfor
  if(max_harm<2||max_harm>10000||guard<0||guard>1000||dc_bins<0||dc_bins>1000),error('GXTXT:Numeric:InvalidPolicy','harmonic limits are outside the public contract');endif
  if(strcmp(mode,'auto_peak'))
    start=min(dc_bins+2,numel(amp));[value,index]=max(amp(start:end));fund_idx=start+index-1;fund_amp=value;
  else
    if(!isnumeric(explicit_f)||!isscalar(explicit_f)||!isreal(explicit_f)||!isfinite(explicit_f)||explicit_f<=0),error('GXTXT:Numeric:InvalidFrequency','explicit fundamental must be positive');endif
    fund_idx=local_peak(freq,amp,explicit_f,guard);fund_amp=amp(fund_idx);
  endif
  if(fund_amp<=0),error('GXTXT:Numeric:ZeroEnergy','fundamental search resolved to non-positive amplitude');endif
  f0=freq(fund_idx);orders=[];expected=[];detected=[];amplitudes=[];
  for k=1:max_harm
    target=k*f0;if(target>freq(end)+.5*df),break;endif
    idx=local_peak(freq,amp,target,guard);
    orders(end+1,1)=k;expected(end+1,1)=target;detected(end+1,1)=freq(idx);amplitudes(end+1,1)=amp(idx);
  endfor
  if(isempty(orders)||orders(1)!=1),error('GXTXT:Numeric:InvalidFrequency','fundamental cannot be represented');endif
  amplitudes(1)=fund_amp;detected(1)=f0;
  out=gxtxt_numeric_harmonic_components_v1(orders,expected,detected,amplitudes,struct('fundamental_amplitude',fund_amp,'level_floor','realmin','component_method','single_bin_peak'));
  if(numel(amplitudes)>1),thd_ratio=sqrt(sum(amplitudes(2:end).^2))/fund_amp;else thd_ratio=0;endif
  out.thd_ratio=thd_ratio;out.thd_pct=100*thd_ratio;out.thd_db=20*log10(thd_ratio);
  out.f0=f0;out.fund_amp=fund_amp;out.bin_count=numel(freq);out.resolved_harmonics=numel(orders);out.df=df;
  out.method='local_single_bin_harmonic_peaks';out.fundamental_mode=mode;out.guard_bins=guard;out.track_harmonics=max_harm;out.exclude_dc_bins=dc_bins;
endfunction
function value=option(options,key,default),value=default;if(isfield(options,key)),value=options.(key);endif;endfunction
function idx=local_peak(freq,amp,target,guard)
  [~,nearest]=min(abs(freq-target));lo=max(1,nearest-guard);hi=min(numel(amp),nearest+guard);[~,index]=max(amp(lo:hi));idx=lo+index-1;
endfunction
