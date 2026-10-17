% P1/P2 reusable signal mathematics. All stochastic paths require a seed.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_signal_advanced_v1(family,action,a,b,c,opts)
  switch(family)
    case 'cepstrum',out=cepstrum_action(action,a,b,c,opts);
    case 'wavelet',out=wavelet_action(action,a,b,c,opts);
    case 'generate',out=generate_action(action,a,b,c,opts);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown signal family');
  endswitch
endfunction
function v=option(s,k,d),v=d;if(isfield(s,k)),v=s.(k);endif;endfunction
function check(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Signal:InvalidOperand','%s must be finite numeric',name);
  endif
endfunction
function out=split_value(v),out=struct('value_real',real(v),'value_imaginary',imag(v));endfunction
function out=cepstrum_action(action,x,b,c,opts)
  check(x,'signal');x=x(:);
  switch(action)
    case 'real'
      spectrum=fft(x);floor_value=option(opts,'magnitude_floor',eps);if(floor_value<=0),error('GXTXT:Signal:InvalidFloor','magnitude floor must be positive');endif
      out=split_value(real(ifft(log(max(abs(spectrum),floor_value)))));
    case 'complex'
      spectrum=fft(x);if(any(abs(spectrum)<option(opts,'magnitude_floor',eps))),error('GXTXT:Signal:SpectralZero','complex cepstrum requires nonzero spectrum');endif
      log_spectrum=log(abs(spectrum))+1i*unwrap(angle(spectrum));out=split_value(ifft(log_spectrum));
    case 'inverse'
      out=split_value(ifft(exp(fft(x))));
    case 'lifter'
      check(b,'quefrency bounds');if(numel(b)!=2||any(b<0)||b(2)<b(1)),error('GXTXT:Signal:InvalidWindow','lifter requires [minimum maximum] nonnegative quefrency');endif
      indices=min((0:numel(x)-1)',(numel(x)-1:-1:0)');mask=(indices>=b(1)&indices<=b(2));out=split_value(x.*mask);out.mask=mask;
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown cepstrum action');
  endswitch
  out.quefrency_samples=(0:numel(x)-1)';
endfunction
function [h,g]=filters(name)
  switch(lower(name))
    case {'haar','db1'},h=[1,1]/sqrt(2);
    case {'db2','sym2'},h=[(1+sqrt(3)),(3+sqrt(3)),(3-sqrt(3)),(1-sqrt(3))]/(4*sqrt(2));
    otherwise,error('GXTXT:Signal:UnknownWavelet','supported discrete wavelets: haar, db1, db2, sym2');
  endswitch
  g=(-1).^(0:numel(h)-1).*fliplr(h);
endfunction
function A=analysis_matrix(n,h,g)
  if(mod(n,2)!=0),error('GXTXT:Signal:InvalidLength','periodic DWT requires even signal length');endif
  A=zeros(n);half=n/2;
  for k=0:half-1
    for j=0:numel(h)-1
      col=mod(2*k+j,n)+1;A(k+1,col)+=h(j+1);A(k+half+1,col)+=g(j+1);
    endfor
  endfor
endfunction
function out=wavelet_action(action,a,b,c,opts)
  name=option(opts,'wavelet','haar');
  switch(action)
    case 'dwt'
      check(a,'signal');x=a(:);[h,g]=filters(name);A=analysis_matrix(numel(x),h,g);v=A*x;
      out=struct('approximation_real',real(v(1:end/2)),'approximation_imaginary',imag(v(1:end/2)), ...
                 'detail_real',real(v(end/2+1:end)),'detail_imaginary',imag(v(end/2+1:end)),'wavelet',name,'boundary','periodic');
    case 'inverse_dwt'
      check(a,'approximation');check(b,'detail');if(numel(a)!=numel(b)),error('GXTXT:Signal:DimensionMismatch','approximation and detail must match');endif
      [h,g]=filters(name);A=analysis_matrix(2*numel(a),h,g);out=split_value(A'*[a(:);b(:)]);out.wavelet=name;
    case 'cwt'
      check(a,'signal');check(b,'scales');x=a(:);scales=b(:);if(any(scales<=0)),error('GXTXT:Signal:InvalidScale','scales must be positive');endif
      fs=option(opts,'sample_rate',1);if(!isscalar(fs)||fs<=0),error('GXTXT:Signal:InvalidSampleRate','sample rate must be positive');endif
      W=zeros(numel(scales),numel(x));
      for k=1:numel(scales)
        radius=ceil(8*scales(k));tau=(-radius:radius)/scales(k);
        if(strcmp(name,'morlet')),psi=pi^(-1/4)*exp(1i*6*tau).*exp(-tau.^2/2);
        elseif(strcmp(name,'mexican_hat')),psi=(2/(sqrt(3)*pi^(1/4)))*(1-tau.^2).*exp(-tau.^2/2);
        else,error('GXTXT:Signal:UnknownWavelet','CWT supports morlet or mexican_hat');endif
        W(k,:)=conv(x,conj(fliplr(psi))/sqrt(scales(k)),'same');
      endfor
      out=struct('coefficients_real',real(W),'coefficients_imaginary',imag(W),'power',abs(W).^2, ...
                 'scales',scales,'time_seconds',(0:numel(x)-1)'/fs,'wavelet',name);
    case 'scalogram'
      check(a,'coefficients');check(b,'scales');fs=option(opts,'sample_rate',1);
      out=struct('power',abs(a).^2,'scales',b(:),'time_seconds',(0:columns(a)-1)'/fs);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown wavelet action');
  endswitch
endfunction
function out=generate_action(action,time,b,c,opts)
  check(time,'time');t=time(:);if(!isreal(t)||numel(t)<2||any(diff(t)<=0)),error('GXTXT:Signal:InvalidGrid','time must be real and increasing');endif
  amplitude=option(opts,'amplitude',1);phase=option(opts,'phase_rad',0);
  switch(action)
    case 'sine'
      check(b,'frequency');y=amplitude*sin(2*pi*b*t+phase);
    case 'multi_tone'
      check(b,'frequencies');f=b(:);amplitudes=option(opts,'amplitudes',ones(numel(f),1));
      if(numel(amplitudes)!=numel(f)),error('GXTXT:Signal:DimensionMismatch','amplitudes must match frequencies');endif
      y=zeros(size(t));for k=1:numel(f),y+=amplitudes(k)*sin(2*pi*f(k)*t+phase);endfor
    case 'chirp'
      check(b,'initial frequency');check(c,'final frequency');duration=t(end)-t(1);tau=t-t(1);
      y=amplitude*sin(2*pi*(b*tau+(c-b)*tau.^2/(2*duration))+phase);
    case {'square','pulse'}
      check(b,'frequency');duty=option(opts,'duty',0.5);if(duty<=0||duty>=1),error('GXTXT:Signal:InvalidDuty','duty must be between zero and one');endif
      y=amplitude*double(mod(b*(t-t(1))+phase/(2*pi),1)<duty);
      if(strcmp(action,'square')),y=2*y-amplitude;endif
    case 'impulse'
      at=option(opts,'index',1);if(at<1||at>numel(t)||at!=fix(at)),error('GXTXT:Signal:InvalidIndex','impulse index outside signal');endif
      y=zeros(size(t));y(at)=amplitude;
    case {'white_noise','colored_noise'}
      seed=option(opts,'seed',[]);if(isempty(seed)||seed<0||seed!=fix(seed)),error('GXTXT:Signal:SeedRequired','deterministic noise requires nonnegative integer seed');endif
      previous=rng();unwind_protect
        rng(seed,'twister');y=randn(size(t));
      unwind_protect_cleanup,rng(previous);end_unwind_protect
      if(strcmp(action,'colored_noise'))
        exponent=option(opts,'spectral_exponent',1);n=numel(y);f=(0:n-1)';f=min(f,n-f);f(1)=1;
        y=real(ifft(fft(y)./(f.^(exponent/2))));
        scale=gxtxt_numeric_v1('array_reduce','std_sample',y);y=y/scale.values;
      endif
      y=amplitude*y;
    case 'am'
      check(b,'carrier frequency');check(c,'modulation frequency');depth=option(opts,'depth',0.5);
      y=amplitude*(1+depth*sin(2*pi*c*t)).*sin(2*pi*b*t+phase);
    case 'fm'
      check(b,'carrier frequency');check(c,'modulation frequency');deviation=option(opts,'frequency_deviation',1);
      if(!isscalar(c)||c<=0),error('GXTXT:Signal:InvalidFrequency','FM modulation frequency must be positive scalar');endif
      y=amplitude*sin(2*pi*b*t-(deviation/c)*cos(2*pi*c*t)+phase);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown generator action');
  endswitch
  out=split_value(y);out.time=t;
endfunction
