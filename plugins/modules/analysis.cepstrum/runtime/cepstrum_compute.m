function R=cepstrum_compute(x,dt_seconds,window_name,detrend_mode,log_floor_db,min_frequency_hz,max_frequency_hz,numeric_api)
% Compute a one-sided real cepstrum and dominant positive-quefrency peak.
% SPDX-License-Identifier: GPL-3.0-or-later
  x=double(x(:));N=numel(x);
  if(N<16),error('analysis.cepstrum: at least 16 samples are required');endif
  if(!isfinite(dt_seconds)||dt_seconds<=0),error('analysis.cepstrum: sample interval must be positive');endif
  if(any(!isfinite(x))),error('analysis.cepstrum: signal contains non-finite values');endif
  if(!isfinite(log_floor_db)||log_floor_db>=0||log_floor_db<-600),error('analysis.cepstrum: log_floor_db must be in [-600, 0)');endif
  fs=1/dt_seconds;nyquist=fs/2;
  if(!isfinite(min_frequency_hz)||!isfinite(max_frequency_hz)||min_frequency_hz<=0||max_frequency_hz<=min_frequency_hz)
    error('analysis.cepstrum: invalid fundamental search-frequency interval');
  endif
  if(max_frequency_hz>=nyquist)
    max_frequency_hz=nyquist*(1-1e-12);
  endif
  if(min_frequency_hz>=max_frequency_hz)
    error('analysis.cepstrum: fundamental search range lies outside the usable frequency interval');
  endif

  D=feval(numeric_api,'detrend',x,struct('method',detrend_mode,'nonfinite','error'));xd=double(D.values(:));
  W=feval(numeric_api,'window',window_name,N,struct('sampling','symmetric'));w=double(W.values(:));
  F=feval(numeric_api,'fft',xd.*w,struct('nfft',N,'normalization','backward','nonfinite','error'));X=complex(double(F.real(:)),double(F.imaginary(:)));
  mag=abs(X);
  peak_mag=max(mag);
  if(!isfinite(peak_mag)||peak_mag<=0),error('analysis.cepstrum: signal has no positive spectral magnitude');endif
  mag_floor=peak_mag*10^(log_floor_db/20);
  logmag=log(max(mag,mag_floor));
  I=feval(numeric_api,'ifft',logmag,zeros(size(logmag)),struct('nfft',N,'normalization','backward','nonfinite','error'));c=double(I.real(:));

  Nh=floor(N/2)+1;
  quefrency=(0:Nh-1)'*dt_seconds;
  real_cepstrum=c(1:Nh);

  qmin=1/max_frequency_hz;
  qmax=1/min_frequency_hz;
  search=find(quefrency>=qmin & quefrency<=qmax);
  search=search(search>1);
  if(isempty(search)),error('analysis.cepstrum: no positive quefrency samples fall inside the requested search interval');endif
  [peak_value,j]=max(real_cepstrum(search));
  peak_index=search(j);
  peak_quefrency=parabolic_peak_quefrency_numeric(quefrency,real_cepstrum,peak_index,numeric_api);
  if(!isfinite(peak_quefrency)||peak_quefrency<=0),peak_quefrency=quefrency(peak_index);endif
  estimated_frequency=1/peak_quefrency;

  R=struct('N',N,'fs',fs,'dt_seconds',dt_seconds,'nyquist_hz',nyquist, ...
    'window_name',window_name,'detrend_mode',detrend_mode,'log_floor_db',log_floor_db, ...
    'quefrency',quefrency,'real_cepstrum',real_cepstrum,'peak_index',peak_index, ...
    'peak_value',peak_value,'peak_quefrency_s',peak_quefrency, ...
    'estimated_frequency_hz',estimated_frequency,'search_qmin_s',qmin,'search_qmax_s',qmax, ...
    'search_min_frequency_hz',min_frequency_hz,'search_max_frequency_hz',max_frequency_hz);
endfunction

function q=parabolic_peak_quefrency_numeric(x,y,i,numeric_api)
  q=x(i);if(i<=1||i>=numel(y)),return;endif
  xx=double(x(i-1:i+1));yy=double(y(i-1:i+1));
  try
    fit=feval(numeric_api,'polynomial_fit',xx,yy,2,[],struct('center_scale',true,'nonfinite','error'));
    c=double(fit.coefficients(:));if(numel(c)!=3||!isfinite(c(1))||abs(c(1))<eps),return;endif
    candidate=-c(2)/(2*c(1));if(isfinite(candidate)&&candidate>=xx(1)&&candidate<=xx(3)),q=candidate;endif
  catch
    q=x(i);
  end_try_catch
endfunction
