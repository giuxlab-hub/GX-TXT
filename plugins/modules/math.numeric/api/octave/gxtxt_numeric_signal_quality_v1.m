function out=gxtxt_numeric_signal_quality_v1(operation,x,other,options)
% Public owner of signal-energy ratios and the retained coherent-bin estimator.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),options=struct();endif
  if(!isstruct(options)||!isscalar(options)),error('GXTXT:Numeric:InvalidArguments','options must be a scalar struct');endif
  finite_vector(x,'signal');x=x(:);n=numel(x);
  if(strcmp(operation,'signal_snr'))
    if(!isempty(fieldnames(options))),error('GXTXT:Numeric:InvalidPolicy','signal_snr has no estimator options');endif
    finite_vector(other,'noise');if(numel(other)!=n),error('GXTXT:Numeric:DimensionMismatch','signal and noise lengths differ');endif
    [signal_energy,log_signal]=energy(x);[noise_energy,log_noise]=energy(other(:));
    out=struct('n',n,'snr_db',10/log(10)*(log_signal-log_noise), ...
      'signal_energy',signal_energy,'noise_energy',noise_energy, ...
      'signal_zero',all(x==0),'noise_zero',all(other(:)==0), ...
      'method','ratio_of_supplied_complex_magnitude_energies');return;
  endif
  if(!strcmp(operation,'signal_spectrum_quality')),error('GXTXT:Numeric:UnknownOperation','unknown signal quality operation');endif
  fs=other;
  if(!isreal(x)||!isnumeric(fs)||!isscalar(fs)||!isreal(fs)||!isfinite(fs)||fs<=0),error('GXTXT:Numeric:InvalidSampleRate','real signal and positive sample rate required');endif
  if(any(!ismember(fieldnames(options),{'fundamental_hz'}))),error('GXTXT:Numeric:InvalidPolicy','unknown signal spectrum quality option');endif
  f0=[];if(isfield(options,'fundamental_hz')),f0=options.fundamental_hz;endif
  if(!isnumeric(f0)||!isscalar(f0)||!isreal(f0)||!isfinite(f0)||f0<=0||f0>=fs/2),error('GXTXT:Numeric:InvalidFrequency','fundamental_hz must lie below Nyquist');endif
  fundamental_bin=f0*n/fs;
  if(abs(fundamental_bin-round(fundamental_bin))>1e-6||round(fundamental_bin)<1),error('GXTXT:Numeric:NoncoherentSampling','spectrum quality requires coherent fundamental sampling');endif
  X=fft(x);power=abs(X(1:floor(n/2)+1)).^2;index=round(fundamental_bin)+1;signal_power=power(index);
  if(signal_power==0),error('GXTXT:Numeric:ZeroEnergy','fundamental bin has zero power');endif
  spurs=power;spurs(1)=0;spurs(index)=0;
  harmonic_orders=(2:floor((fs/2)/f0))';harmonic_indices=round(harmonic_orders*fundamental_bin)+1;
  % Keep dev096's raw positive FFT-bin convention, including its Nyquist weight.
  distortion=sum(power(harmonic_indices));noise_and_distortion=sum(spurs);noise=max(0,noise_and_distortion-distortion);
  noise_bins=spurs;noise_bins(harmonic_indices)=0;positive=noise_bins(noise_bins>0);
  if(isempty(positive)),noise_floor=0;else noise_floor=median(positive);endif
  thd=sqrt(distortion/signal_power);sinad=10*log10(signal_power/noise_and_distortion);
  harmonic_powers=power(harmonic_indices);
  if(isempty(harmonic_orders)),harmonic_powers=[];endif % Preserve the public empty shape.
  out=struct('n',n,'sample_rate',fs,'fundamental_hz',f0,'fundamental_bin',round(fundamental_bin), ...
    'harmonic_orders',harmonic_orders,'method','coherent_positive_fft_bins','normalization','raw_positive_fft_squared', ...
    'fundamental_power',signal_power,'dc_power',power(1),'harmonic_powers',harmonic_powers, ...
    'noise_power',noise,'noise_floor_power_per_bin',noise_floor,'noise_floor_db_relative',10*log10(noise_floor/signal_power), ...
    'distortion_power',distortion,'thd',thd,'thd_db',20*log10(thd),'thd_plus_n',sqrt(noise_and_distortion/signal_power), ...
    'snr_db',10*log10(signal_power/noise),'sinad_db',sinad,'sfdr_db',10*log10(signal_power/max(spurs)), ...
    'enob_bits',(sinad-1.76)/6.02);
endfunction
function finite_vector(x,name)
  if(!isnumeric(x)||!isvector(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:))))),error('GXTXT:Numeric:InvalidOperand','%s must be a finite nonempty vector',name);endif
endfunction
function [value,log_value]=energy(x)
  peak=max(abs(x));
  if(!isfinite(peak)),error('GXTXT:Numeric:InvalidOperand','signal magnitude exceeds binary64 range');endif
  if(peak==0),value=0;log_value=-Inf;return;endif
  scaled=sum(abs(x/peak).^2);log_value=2*log(peak)+log(scaled);value=exp(log_value);
endfunction
