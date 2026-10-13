function R=tdfft_compute_frame(x,dt_seconds,nfft,window_name,detrend_mode,representation,numeric_api)
% Compute one single-sided FFT frame with explicit window normalization.
% SPDX-License-Identifier: GPL-3.0-or-later

  if(nargin<7||isempty(numeric_api)),error('analysis.time_dependent_fft: public NUMERIC_API_v1 binding is required');endif
  x=x(:);
  L=numel(x);
  if(L<2),error('analysis.time_dependent_fft: each Temporal Set window requires at least 2 samples');endif
  if(!isfinite(dt_seconds)||dt_seconds<=0),error('analysis.time_dependent_fft: sample spacing must be positive');endif
  if(!isfinite(nfft)||nfft!=fix(nfft)||nfft<L),error('analysis.time_dependent_fft: NFFT must be an integer >= window sample count');endif

  D=feval(numeric_api,'detrend',x,struct('method',lower(strtrim(detrend_mode)),'nonfinite','error'));
  xd=double(D.values(:));clear D;
  W=feval(numeric_api,'window',window_name,L,struct('sampling','symmetric'));
  w=double(W.values(:));coherent_sum=double(W.coherent_gain)*L;
  power_sum=double(W.power_sum);clear W;
  if(!isfinite(coherent_sum)||abs(coherent_sum)<=realmin),error('analysis.time_dependent_fft: invalid FFT window coherent gain');endif
  if(!isfinite(power_sum)||power_sum<=0),error('analysis.time_dependent_fft: invalid FFT window power normalization');endif

  F=feval(numeric_api,'fft',xd.*w,struct('nfft',nfft,'normalization','backward','nonfinite','error'));
  O=feval(numeric_api,'one_sided',F.real,F.imaginary,struct('nfft',nfft,'scaling','none'));
  X=complex(double(O.real(:)),double(O.imaginary(:)));Nh=double(O.bin_count);
  clear F O xd w;
  interior=2:Nh;
  if(mod(nfft,2)==0 && Nh>=2),interior=2:(Nh-1);endif

  amplitude=abs(X)./abs(coherent_sum);
  if(!isempty(interior)),amplitude(interior)=2*amplitude(interior);endif

  representation=lower(strtrim(representation));
  switch(representation)
    case 'amplitude'
      values=amplitude;
    case 'psd'
      values=(abs(X).^2)./(1.0/dt_seconds*power_sum);
      if(!isempty(interior)),values(interior)=2*values(interior);endif
    case 'amplitude_db'
      values=20*log10(max(amplitude,realmin));
    otherwise
      error('analysis.time_dependent_fft: unsupported spectral representation: %s',representation);
  endswitch

  R=struct('values',values(:),'sample_count',L,'nfft',nfft,'bin_count',Nh, ...
    'fs',1.0/dt_seconds,'df',(1.0/dt_seconds)/nfft, ...
    'coherent_gain',coherent_sum/L,'window_power_sum',power_sum, ...
    'representation',representation);
endfunction
