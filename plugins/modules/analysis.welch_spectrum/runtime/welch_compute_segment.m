function R=welch_compute_segment(x,dt_seconds,nfft,window_name,detrend_mode,numeric_fn)
% Compute one one-sided normalized periodogram and amplitude spectrum.
% PSD convention: |FFT(x*w)|^2 / (Fs * sum(w.^2)), with one-sided doubling.
% Amplitude convention: |FFT(x*w)| / sum(w), with one-sided doubling.
% SPDX-License-Identifier: GPL-3.0-or-later
  x=double(x(:));L=numel(x);
  if(L<2),error('analysis.welch_spectrum: segment requires at least two samples');endif
  if(any(!isfinite(x))),error('analysis.welch_spectrum: non-finite signal samples are not allowed');endif
  if(!isfinite(dt_seconds)||dt_seconds<=0),error('analysis.welch_spectrum: sample spacing must be positive');endif
  if(!isfinite(nfft)||nfft!=fix(nfft)||nfft<L),error('analysis.welch_spectrum: NFFT must be an integer >= segment sample count');endif
  if(nargin<6||isempty(numeric_fn)),error('analysis.welch_spectrum: public NUMERIC_API_v1 binding is required');endif
  D=feval(numeric_fn,'detrend',x,struct('method',lower(strtrim(detrend_mode)),'nonfinite','error'));z=D.values;
  W=feval(numeric_fn,'window',window_name,L,struct('sampling','symmetric'));w=W.values;U=W.power_sum;CG=W.coherent_gain*L;
  if(!isfinite(U)||U<=0||!isfinite(CG)||abs(CG)<=realmin),error('analysis.welch_spectrum: invalid FFT-window normalization');endif
  fs=1/dt_seconds;F=feval(numeric_fn,'fft',z.*w,struct('nfft',nfft,'normalization','backward','nonfinite','error'));
  Nh=floor(nfft/2)+1;X=complex(F.real(1:Nh),F.imaginary(1:Nh));
  psd=(abs(X).^2)/(fs*U);amp=abs(X)/abs(CG);
  interior=2:Nh;if(mod(nfft,2)==0&&Nh>=2),interior=2:(Nh-1);endif
  if(!isempty(interior)),psd(interior)=2*psd(interior);amp(interior)=2*amp(interior);endif
  enbw_hz=fs*U/(CG^2);
  R=struct('psd',psd(:),'amplitude',amp(:),'sample_count',L,'nfft',nfft,'bin_count',Nh,'fs',fs,'df',fs/nfft,'window_power_sum',U,'coherent_gain_sum',CG,'enbw_hz',enbw_hz);
endfunction
