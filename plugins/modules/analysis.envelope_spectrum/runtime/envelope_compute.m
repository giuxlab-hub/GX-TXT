function R=envelope_compute(x,dt_seconds,input_detrend,filter_mode,band_low_hz,band_high_hz,envelope_dc,window_name,nfft,numeric_api)
% Scientific kernel for analytic-signal envelope spectrum.
% Generic numerical primitives are obtained from public NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<10||isempty(numeric_api)),error('analysis.envelope_spectrum: public NUMERIC_API function is required');endif
  x=double(x(:));N=numel(x);if(N<4),error('analysis.envelope_spectrum: at least 4 samples are required');endif
  if(any(!isfinite(x))),error('analysis.envelope_spectrum: input signal contains non-finite values');endif
  if(!isfinite(dt_seconds)||dt_seconds<=0),error('analysis.envelope_spectrum: sample spacing must be positive');endif
  fs=1/dt_seconds;

  D=feval(numeric_api,'detrend',x,struct('method',input_detrend,'nonfinite','error'));
  filtered=double(D.values(:));
  if(strcmpi(strtrim(filter_mode),'ideal_fft_bandpass'))
    if(!isfinite(band_low_hz)||!isfinite(band_high_hz)||band_low_hz<=0||band_high_hz<=band_low_hz||band_high_hz>=fs/2),error('analysis.envelope_spectrum: bandpass must satisfy 0 < low < high < Nyquist');endif
    F=feval(numeric_api,'fft',filtered,struct('nfft',N,'normalization','backward','nonfinite','error'));
    G=feval(numeric_api,'frequency_grid',fs,N,struct('representation','two_sided','ordering','fft'));
    mask=(abs(double(G.frequency(:)))>=band_low_hz)&(abs(double(G.frequency(:)))<=band_high_hz);
    I=feval(numeric_api,'ifft',double(F.real(:)).*double(mask),double(F.imaginary(:)).*double(mask),struct('nfft',N,'normalization','backward','nonfinite','error'));
    filtered=double(I.real(:));
  elseif(!strcmpi(strtrim(filter_mode),'none'))
    error('analysis.envelope_spectrum: unsupported demodulation filter: %s',filter_mode);
  endif

  A=feval(numeric_api,'analytic_signal',filtered,struct('nonfinite','error'));
  envelope=double(A.amplitude(:));
  S=feval(numeric_api,'statistics',envelope,struct('nonfinite','error'));
  env_for_fft=envelope;
  if(strcmpi(strtrim(envelope_dc),'remove_mean'))
    env_for_fft=envelope-double(S.mean);
  elseif(!strcmpi(strtrim(envelope_dc),'keep'))
    error('analysis.envelope_spectrum: unsupported envelope DC mode: %s',envelope_dc);
  endif

  if(!isfinite(nfft)||nfft!=fix(nfft)||nfft<N),error('analysis.envelope_spectrum: NFFT must be an integer >= selected sample count');endif
  W=feval(numeric_api,'window',window_name,N,struct('sampling','symmetric'));
  w=double(W.values(:));CG=double(W.coherent_gain)*N;U=double(W.power_sum);
  if(abs(CG)<=realmin||U<=0),error('analysis.envelope_spectrum: invalid FFT-window normalization');endif
  F=feval(numeric_api,'fft',env_for_fft.*w,struct('nfft',nfft,'normalization','backward','nonfinite','error'));
  O=feval(numeric_api,'one_sided',F.real,F.imaginary,struct('nfft',nfft,'scaling','none'));
  E=complex(double(O.real(:)),double(O.imaginary(:)));Nh=numel(E);
  amplitude=abs(E)/abs(CG);psd=(abs(E).^2)/(fs*U);
  interior=2:Nh;if(mod(nfft,2)==0&&Nh>=2),interior=2:(Nh-1);endif
  if(!isempty(interior)),amplitude(interior)*=2;psd(interior)*=2;endif
  G=feval(numeric_api,'frequency_grid',fs,nfft,struct('representation','one_sided','ordering','fft'));
  freq=double(G.frequency(:));psd_db=10*log10(max(psd,realmin));
  R=struct('filtered',filtered,'envelope',envelope,'envelope_fft_input',env_for_fft,'frequency',freq,'amplitude',amplitude,'psd',psd,'psd_db',psd_db,'fs',fs,'df',double(G.df),'nfft',nfft,'sample_count',N,'envelope_mean',double(S.mean),'envelope_rms',double(S.rms),'filter_mode',filter_mode,'band_low_hz',band_low_hz,'band_high_hz',band_high_hz);
endfunction
