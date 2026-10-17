function out=gxtxt_numeric_signal_spectral_v1(operation,x,y,fs,options)
% Public Numeric owner of Signal's periodogram/Welch-derived estimators.
% SPDX-License-Identifier: GPL-3.0-or-later
  actions={'periodogram','welch','asd','cross_psd','coherence','frf_h1','frf_h2'};
  if(!any(strcmp(operation,actions))),error('GXTXT:Numeric:UnknownOperation','Unknown spectral estimator');endif
  valid(x,'signal');x=double(x(:));n=numel(x);paired=any(strcmp(operation,{'cross_psd','coherence','frf_h1','frf_h2'}));
  if(paired),valid(y,'second signal');y=double(y(:));if(numel(y)!=n),error('GXTXT:Numeric:DimensionMismatch','Signals must have equal length');endif;endif
  if(!isnumeric(fs)||!isreal(fs)||!isscalar(fs)||!isfinite(fs)||fs<=0),error('GXTXT:Numeric:InvalidSampleRate','Finite positive sample rate required');endif
  if(!isstruct(options)||!isscalar(options)||any(!ismember(fieldnames(options),{'nfft','window','overlap'}))),error('GXTXT:Numeric:InvalidPolicy','Spectral options are nfft, window and overlap');endif
  pkg('load','signal');nfft=option(options,'nfft',max(256,2^nextpow2(n)));
  if(isempty(nfft)),nfft=max(256,2^nextpow2(n));endif
  if(!isnumeric(nfft)||!isreal(nfft)||!isscalar(nfft)||!isfinite(nfft)||nfft<0||nfft!=fix(nfft)),error('GXTXT:Numeric:InvalidLength','NFFT must be a nonnegative integer');endif
  window=option(options,'window',hamming(min(n,nfft)));overlap=option(options,'overlap',.5);
  kind='real';if(!isreal(x)||(paired&&!isreal(y))),kind='complex';endif
  if(strcmp(operation,'periodogram'))
    if(nfft<1),error('GXTXT:Numeric:InvalidLength','Periodogram NFFT must be positive');endif
    if(isempty(window)),window=ones(n,1);endif
    valid(window,'window');if(!isvector(window)||numel(window)!=n),error('GXTXT:Numeric:InvalidWindow','Periodogram window length must equal signal length');endif
    window=double(window(:));if(!any(window!=0)),error('GXTXT:Numeric:InvalidWindow','Window must have nonzero energy');endif
    if(!isreal(window)),kind='complex';endif
    sidedness='onesided';if(strcmp(kind,'complex')),sidedness='twosided';endif
    [v,f]=periodogram(x,window,nfft,fs,sidedness);
    window_length=n;overlap_samples=0;window_count=1;used=n;detrend='none';
    method='octave_periodogram_window_energy';
  else
    if(isempty(overlap)),overlap=.5;endif
    if(!isnumeric(overlap)||!isreal(overlap)||!isscalar(overlap)||!isfinite(overlap)||overlap<0||overlap>.95),error('GXTXT:Numeric:InvalidPolicy','Native Welch overlap fraction must be in [0,0.95]');endif
    if(isempty(window))
      % Native signal-package default, made explicit before the backend call.
      window_length=2^ceil(log(sqrt(n/(1-overlap)))*(1-10*eps)/log(2));window=hamming(window_length);
    elseif(isscalar(window))
      if(!isnumeric(window)||!isreal(window)||!isfinite(window)||window<=3||window!=fix(window)),error('GXTXT:Numeric:InvalidWindow','Welch scalar window length must be an integer greater than three');endif
      window_length=double(window);window=hamming(window_length);
    else
      valid(window,'window');if(!isreal(window)||!isvector(window)),error('GXTXT:Numeric:InvalidWindow','Welch window must be a finite real vector');endif
      window=double(window(:));window_length=numel(window);
    endif
    if(!any(window!=0)),error('GXTXT:Numeric:InvalidWindow','Window must have nonzero energy');endif
    nfft=max(nfft,window_length);overlap_samples=fix(window_length*overlap);
    padded=max(n,window_length);window_count=fix((padded-window_length)/(window_length-overlap_samples))+1;
    used=(window_length-overlap_samples)*(window_count-1)+window_length;
    sidedness='onesided';if(strcmp(kind,'complex')),sidedness='twosided';endif
    detrend='global_mean_over_used_segment_span';method='octave_native_welch_window_energy';
    % A caller's persistent Matlab compatibility setting must neither change
    % this API's estimator nor be changed by it, including exceptional exits.
    previous=pwelch([]);cleanup=onCleanup(@() pwelch(previous));
    if(paired)
      % One joint backend pass provides all spectra, with a common sidedness.
      % Cross-spectrum convention is Y*conj(X), matching accepted cpsd.
      [spectra,f]=pwelch(x,y,window,overlap,nfft,fs,'power','cross','ypower',sidedness,'long-mean');
      pxx=real(spectra(:,1));pxy=spectra(:,2);pyy=real(spectra(:,3));
      switch(operation)
        case 'cross_psd',v=pxy;
        case 'coherence',v=abs(pxy).^2./(pxx.*pyy);
        case 'frf_h1',v=pxy./pxx;
        case 'frf_h2',v=pyy./conj(pxy);
      endswitch
    else
      [v,f]=pwelch(x,window,overlap,nfft,fs,sidedness,'long-mean');
      if(strcmp(operation,'asd')),v=sqrt(real(v));endif
    endif
    clear cleanup;
  endif
  out=struct('frequency_hz',f);
  if(any(strcmp(operation,{'periodogram','welch'}))),out.psd_real=real(v);out.psd_imaginary=imag(v);
  elseif(strcmp(operation,'asd')),out.asd=real(v);
  else out.value_real=real(v);out.value_imaginary=imag(v);endif
  out.n=n;out.sample_rate=fs;out.fft_length=nfft;out.bin_count=numel(f);
  out.window_length=window_length;out.overlap_samples=overlap_samples;out.window_count=window_count;out.used_sample_count=used;
  out.method=method;out.spectral_operation=operation;out.sidedness=sidedness;out.detrend=detrend;out.input_kind=kind;
  out.normalization='window_energy_and_sample_rate';
endfunction
function v=option(options,key,default),v=default;if(isfield(options,key)),v=options.(key);endif;endfunction
function valid(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Numeric:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
