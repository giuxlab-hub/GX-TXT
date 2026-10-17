% SIGNAL_API_v1 reusable signal and linear-system mathematics.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_signal_v1(family,action,a,b,c,opts)
  if(nargin<2||!ischar(family)||!ischar(action)),error('GXTXT:Signal:InvalidArguments','family and action are required');endif
  if(nargin<3),a=[];endif;if(nargin<4),b=[];endif;if(nargin<5),c=[];endif;if(nargin<6),opts=struct();endif
  if(!isstruct(opts)),error('GXTXT:Signal:InvalidArguments','options must be a struct');endif
  if(strcmp(family,'contract'))
    count=gxtxt_signal_validate_v1(action,a,b,c,opts);
    out=struct('valid',true,'field_count',count);return;
  endif
  pkg('load','signal');family=lower(strtrim(family));action=lower(strtrim(action));
  [~,opts]=gxtxt_signal_validate_v1([family '.' action],a,b,c,opts);
  switch(family)
    case 'convolution',out=convolution_action(action,a,b,c,opts);
    case 'correlation',out=correlation_action(action,a,b,c,opts);
    case 'filter',out=filter_action(action,a,b,c,opts);
    case 'design',out=design_action(action,a,b,c,opts);
    case 'multirate',out=multirate_action(action,a,b,c,opts);
    case 'lti',out=lti_action(action,a,b,c,opts);
    case 'response',out=response_action(action,a,b,c,opts);
    case 'spectral',out=spectral_action(action,a,b,c,opts);
    case 'stft',out=stft_action(action,a,b,c,opts);
    case 'analytic',out=analytic_action(action,a,b,c,opts);
    case 'frequency_metric',out=frequency_metric_action(action,a,b,c,opts);
    case 'time_metric',out=time_metric_action(action,a,b,c,opts);
    case 'quality',out=quality_action(action,a,b,c,opts);
    case 'events',out=events_action(action,a,b,c,opts);
    case {'cepstrum','wavelet','generate'},out=gxtxt_signal_advanced_v1(family,action,a,b,c,opts);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown signal family');
  endswitch
endfunction
function v=opt(s,key,default),v=default;if(isfield(s,key)),v=s.(key);endif,endfunction
function valid(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Signal:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
function out=split(v,prefix)
  if(nargin<2),prefix='value';endif
  out=struct();out.([prefix '_real'])=real(v);out.([prefix '_imaginary'])=imag(v);
endfunction
function out=convolution_action(action,x,h,c,opts)
  valid(x,'signal');valid(h,'kernel');x=x(:);h=h(:);
  switch(action)
    case 'linear',y=conv(x,h);
    case 'circular'
      n=opt(opts,'length',max(numel(x),numel(h)));if(!isscalar(n)||n<1||n!=fix(n)),error('GXTXT:Signal:InvalidLength','invalid circular length');endif
      xx=zeros(n,1);hh=zeros(n,1);
      for k=1:numel(x),index=mod(k-1,n)+1;xx(index)+=x(k);endfor
      for k=1:numel(h),index=mod(k-1,n)+1;hh(index)+=h(k);endfor
      y=ifft(fft(xx).*fft(hh));
    case 'deconvolve'
      if(numel(x)<numel(h)),error('GXTXT:Signal:DimensionMismatch','output shorter than kernel');endif
      n=numel(x)+numel(h)-1;H=fft(h,n);floorvalue=opt(opts,'relative_floor',1e-10);lambda=opt(opts,'regularization',0);
      if(!isscalar(floorvalue)||floorvalue<0||!isscalar(lambda)||lambda<0),error('GXTXT:Signal:InvalidTolerance','invalid deconvolution conditioning policy');endif
      if(lambda==0&&min(abs(H))<=floorvalue*max(abs(H))),error('GXTXT:Signal:IllConditioned','kernel spectrum requires positive regularization');endif
      y=ifft(conj(H).*fft(x,n)./(abs(H).^2+lambda^2));y=y(1:(numel(x)-numel(h)+1));
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown convolution action');
  endswitch
  out=split(y);out.output_length=numel(y);
endfunction
function out=correlation_action(action,x,y,c,opts)
  valid(x,'first signal');if(isempty(y)),y=x;else valid(y,'second signal');endif;x=x(:);y=y(:);
  if(!any(strcmp(action,{'auto','cross','delay'}))),error('GXTXT:Signal:UnknownOperation','unknown correlation action');endif
  options=struct();for key={'normalization','sample_rate'}
    if(isfield(opts,key{1})),options.(key{1})=opts.(key{1});endif
  endfor
  try out=gxtxt_numeric_v1('signal_correlation',x,y,options);
  catch err
    err.identifier=strrep(err.identifier,'GXTXT:Numeric:','GXTXT:Signal:');rethrow(err);
  end_try_catch
  if(!isfield(opts,'sample_rate')),out=rmfield(out,'delay_seconds');endif
endfunction
function out=filter_action(action,model,x,state,opts)
  if(!isstruct(model)||(!isfield(model,'numerator')&&!isfield(model,'sos'))),error('GXTXT:Signal:InvalidModel','filter model requires numerator or SOS');endif
  if(!isfield(model,'numerator')&&strcmp(action,'causal')),action='sos';endif
  if(!isfield(model,'numerator')&&strcmp(action,'zero_phase')),error('GXTXT:Signal:InvalidModel','zero-phase SOS filtering requires equivalent numerator/denominator coefficients');endif
  if(isfield(model,'numerator')),valid(model.numerator,'numerator');b=model.numerator(:).';a=opt(model,'denominator',1);valid(a,'denominator');a=a(:).';
  else b=1;a=1;endif
  if(a(1)==0),error('GXTXT:Signal:InvalidModel','leading denominator coefficient is zero');endif
  if(strcmp(action,'inspect'))
    if(isfield(model,'sos')&&!isfield(model,'numerator'))
      sos=model.sos;valid(sos,'SOS');if(columns(sos)!=6||any(sos(:,4)==0)),error('GXTXT:Signal:InvalidModel','SOS requires six columns and nonzero denominator leads');endif
      roots_a=[];for k=1:rows(sos),roots_a=[roots_a;roots(sos(k,4:6))];endfor
      filter_order=2*rows(sos);
    else roots_a=roots(a);filter_order=max(numel(a),numel(b))-1;endif
    out=split(roots_a,'poles');out.stable=all(abs(roots_a)<1);out.order=filter_order;return;
  endif
  valid(x,'signal');x=x(:);
  if(strcmp(action,'sos'))
    sos=opt(model,'sos',[]);valid(sos,'SOS');if(columns(sos)!=6||any(sos(:,4)==0)),error('GXTXT:Signal:InvalidModel','SOS requires six columns and nonzero denominator leads');endif
    if(isempty(state)),state=zeros(rows(sos),2);endif
    if(!isequal(size(state),[rows(sos),2])),error('GXTXT:Signal:DimensionMismatch','SOS state must have one two-sample row per section');endif
    y=x;final=zeros(rows(sos),2);
    for k=1:rows(sos),[y,zf]=filter(sos(k,1:3),sos(k,4:6),y,state(k,:).');final(k,:)=zf(:).';endfor
    out=split(y);out.state_real=real(final);out.state_imaginary=imag(final);return;
  endif
  if(strcmp(action,'zero_phase')&&!isempty(state)),error('GXTXT:Signal:InvalidArguments','zero-phase filtering does not accept causal initial state');endif
  if(isempty(state)),state=zeros(max(numel(a),numel(b))-1,1);endif
  if(numel(state)!=max(numel(a),numel(b))-1),error('GXTXT:Signal:DimensionMismatch','initial filter state length differs from model order');endif
  switch(action)
    case 'causal',[y,zf]=filter(b,a,x,state(:));out=split(y);out.state_real=real(zf);out.state_imaginary=imag(zf);
    case 'zero_phase'
      if(any(abs(roots(a))>=1)),error('GXTXT:Signal:UnstableFilter','zero-phase IIR filtering requires stable poles');endif
      if(numel(x)<=3*(max(numel(a),numel(b))-1)),error('GXTXT:Signal:InvalidLength','signal is too short for zero-phase filtering');endif
      y=filtfilt(b,a,x);out=split(y);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown filter action');
  endswitch
endfunction
function out=design_action(action,order,cutoff,ripple,opts)
  if(strcmp(action,'estimate_order'))
    valid(order,'passband edge');valid(cutoff,'stopband edge');valid(ripple,'passband ripple');stop=opt(opts,'stopband_db',40);family=opt(opts,'prototype','butterworth');
    if(!isscalar(ripple)||ripple<=0||!isscalar(stop)||stop<=ripple),error('GXTXT:Signal:InvalidTolerance','positive passband and larger stopband attenuation required');endif
    switch(family)
      case 'butterworth',[n,w]=buttord(order,cutoff,ripple,stop);
      case 'chebyshev1',[n,w]=cheb1ord(order,cutoff,ripple,stop);
      case 'chebyshev2',[n,w]=cheb2ord(order,cutoff,ripple,stop);
      case 'elliptic',[n,w]=ellipord(order,cutoff,ripple,stop);
      otherwise,error('GXTXT:Signal:InvalidModel','unsupported order-estimation prototype');
    endswitch
    out=struct('order',n,'cutoff',w);return;
  endif
  % Typed and conditional design admission is shared with public preflight.
  band=opt(opts,'band','low');domain=opt(opts,'domain','discrete');
  suffix={};if(strcmp(domain,'analog')),suffix={'s'};endif
  switch(action)
    case 'butterworth',[b,a]=butter(order,cutoff,band,suffix{:});
    case 'chebyshev1',valid(ripple,'passband ripple');[b,a]=cheby1(order,ripple,cutoff,band,suffix{:});
    case 'chebyshev2',valid(ripple,'stopband attenuation');[b,a]=cheby2(order,ripple,cutoff,band,suffix{:});
    case 'elliptic'
      valid(ripple,'passband ripple');stop=opt(opts,'stopband_db',40);[b,a]=ellip(order,ripple,stop,cutoff,band,suffix{:});
    case 'bessel'
      if(strcmp(domain,'discrete')),suffix={'z'};endif
      [b,a]=besself(order,cutoff,band,suffix{:});
    case 'fir_window'
      window_name=opt(opts,'window','hamming');switch(window_name)
        case 'hamming',w=hamming(order+1);case 'hann',w=hanning(order+1);case 'blackman',w=blackman(order+1);
        otherwise,error('GXTXT:Signal:InvalidWindow','unsupported FIR window');
      endswitch
      b=fir1(order,cutoff,band,w);a=1;
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown design family');
  endswitch
  out=split(b,'numerator');out.denominator_real=real(a);out.denominator_imaginary=imag(a);
  out.poles_real=real(roots(a));out.poles_imaginary=imag(roots(a));out.domain=domain;
  if(strcmp(domain,'discrete')),out.stable=all(abs(roots(a))<1);else out.stable=all(real(roots(a))<0);endif
  if(numel(a)>2&&strcmp(domain,'discrete'))
    [sos,g]=tf2sos(b,a);out.sos_real=real(sos);out.sos_imaginary=imag(sos);out.sos_gain=g;
  endif
endfunction
function out=multirate_action(action,x,p,q,opts)
  valid(x,'signal');x=x(:);valid(p,'factor');
  switch(action)
    case 'decimate',if(!isscalar(p)||p!=fix(p)||p<1),error('GXTXT:Signal:InvalidFactor','invalid decimation factor');endif;y=decimate(x,p);
    case 'interpolate',if(!isscalar(p)||p!=fix(p)||p<1),error('GXTXT:Signal:InvalidFactor','invalid interpolation factor');endif;y=interp(x,p);
    case 'rational',valid(q,'denominator');if(p!=fix(p)||q!=fix(q)||p<1||q<1),error('GXTXT:Signal:InvalidFactor','rational factors must be positive integers');endif;y=resample(x,p,q);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown multirate action');
  endswitch
  out=split(y);out.up_factor=p;if(strcmp(action,'decimate')),out.down_factor=p;out.up_factor=1;elseif(strcmp(action,'interpolate')),out.down_factor=1;else out.down_factor=q;endif
  start=opt(opts,'start_time',0);rate=opt(opts,'sample_rate',[]);
  if(isfield(opts,'input_time'))
    t=opts.input_time(:);valid(t,'input time');if(!isreal(t)||numel(t)!=numel(x)||any(diff(t)<=0)),error('GXTXT:Signal:InvalidGrid','input time must increase and match samples');endif
    dt=median(diff(t));if(max(abs(diff(t)-dt))>1e-8*dt),error('GXTXT:Signal:InvalidGrid','multirate input time must be uniform');endif
    derived_rate=1/dt;if(!isempty(rate)&&abs(rate-derived_rate)>1e-8*derived_rate),error('GXTXT:Signal:InvalidSampleRate','declared rate conflicts with input time');endif
    rate=derived_rate;start=t(1);
  endif
  if(!isempty(rate))
    if(!isscalar(rate)||!isfinite(rate)||rate<=0||!isfinite(start)),error('GXTXT:Signal:InvalidSampleRate','positive input sample rate and finite start time required');endif
    out.output_sample_rate=rate*out.up_factor/out.down_factor;out.time=start+(0:numel(y)-1)'/out.output_sample_rate;
  endif
endfunction
function model=lti_model(a,b,c,opts)
  if(!isstruct(a)||!isfield(a,'kind')),error('GXTXT:Signal:InvalidModel','LTI model requires kind');endif
  model=a;model.domain=opt(a,'domain','continuous');model.sample_period=opt(a,'sample_period',[]);
  if(strcmp(model.domain,'discrete')&&(isempty(model.sample_period)||model.sample_period<=0)),error('GXTXT:Signal:InvalidModel','discrete model needs positive sample period');endif
endfunction
function sys=as_lti(model)
  pkg('load','control');switch(model.kind)
    case 'tf'
      if(!isreal(model.numerator)||!isreal(model.denominator)),error('GXTXT:Signal:UnsupportedComplexTime','complex TF time conversion is unavailable in the current control backend');endif
      sys=tf(model.numerator,model.denominator);
    case 'zpk'
      if(!isreal(model.zeros)||!isreal(model.poles)||!isreal(model.gain)),error('GXTXT:Signal:UnsupportedComplexTime','complex ZPK time conversion is unavailable in the current control backend');endif
      sys=zpk(model.zeros,model.poles,model.gain);
    case 'ss'
      if(!isreal(model.A)||!isreal(model.B)||!isreal(model.C)||!isreal(model.D)),error('GXTXT:Signal:UnsupportedComplexTime','complex state-space time conversion is unavailable in the current control backend');endif
      sys=ss(model.A,model.B,model.C,model.D);
    otherwise,error('GXTXT:Signal:InvalidModel','unknown LTI model kind');
  endswitch
  if(strcmp(model.domain,'discrete')),sys.Ts=model.sample_period;endif
endfunction
function [num,den]=model_tf_coefficients(model)
  switch(model.kind)
    case 'tf',num=model.numerator(:).';den=model.denominator(:).';
    case 'zpk',num=model.gain*poly(model.zeros(:));den=poly(model.poles(:));
    case 'ss'
      A=model.A;B=model.B;C=model.C;D=model.D;
      if(!ismatrix(A)||rows(A)!=columns(A)||rows(B)!=rows(A)||columns(B)!=1||rows(C)!=1||columns(C)!=rows(A)||!isscalar(D))
        error('GXTXT:Signal:DimensionMismatch','SISO state-space matrices have incompatible shapes');
      endif
      den=poly(A);n=rows(A);num=zeros(1,n+1);num(1)=D;markov=zeros(1,n);v=B;
      for k=1:n,markov(k)=C*v;v=A*v;endfor
      for j=1:n
        q=0;for i=0:j-1,q+=den(i+1)*markov(j-i);endfor
        num(j+1)=D*den(j+1)+q;
      endfor
    otherwise,error('GXTXT:Signal:InvalidModel','unknown LTI model kind');
  endswitch
  valid(num,'numerator');valid(den,'denominator');if(den(1)==0),error('GXTXT:Signal:InvalidModel','leading denominator coefficient is zero');endif
  num=num/den(1);den=den/den(1);
endfunction
function [A,B,C,D]=tf_companion(num,den)
  n=numel(den)-1;if(n<1),A=zeros(0);B=zeros(0,1);C=zeros(1,0);D=num(end);return;endif
  if(numel(num)>n+1),error('GXTXT:Signal:ImproperModel','state-space conversion requires a proper transfer function');endif
  num=[zeros(1,n+1-numel(num)),num];D=num(1);A=zeros(n);A(1,:)=-den(2:end);
  if(n>1),A(2:end,1:end-1)=eye(n-1);endif
  B=zeros(n,1);B(1)=1;C=num(2:end)-D*den(2:end);
endfunction
function [n,m,p]=ss_dimensions(model)
  A=model.A;B=model.B;C=model.C;D=model.D;
  valid(A,'state matrix');valid(B,'input matrix');valid(C,'output matrix');valid(D,'feedthrough matrix');
  n=rows(A);m=columns(B);p=rows(C);
  if(columns(A)!=n||rows(B)!=n||columns(C)!=n||!isequal(size(D),[p,m]))
    error('GXTXT:Signal:DimensionMismatch','state-space A/B/C/D dimensions are incompatible');
  endif
endfunction
function out=lti_mimo(action,model,opts)
  [n,m,p]=ss_dimensions(model);A=model.A;B=model.B;C=model.C;D=model.D;
  switch(action)
    case 'inspect'
      poles_value=eig(A);out=split(poles_value,'poles');
      if(strcmp(model.domain,'discrete')),out.stable=all(abs(poles_value)<1);base=eye(n)-A;out.dc_gain_defined=rcond(base)>eps;
        if(out.dc_gain_defined),dc=D+C*(base\B);endif
      else out.stable=all(real(poles_value)<0);out.dc_gain_defined=rcond(A)>eps;
        if(out.dc_gain_defined),dc=D-C*(A\B);endif
      endif
      if(out.dc_gain_defined),out.dc_gain_real=real(dc);out.dc_gain_imaginary=imag(dc);else out.dc_gain_real=[];out.dc_gain_imaginary=[];endif
    case 'ss'
      out=split(A,'A');out.B_real=real(B);out.B_imaginary=imag(B);out.C_real=real(C);out.C_imaginary=imag(C);out.D_real=real(D);out.D_imaginary=imag(D);
    case {'zoh','foh','tustin','prewarp','matched'}
      sys=as_lti(model);Ts=opt(opts,'sample_period',[]);if(isempty(Ts)||Ts<=0),error('GXTXT:Signal:InvalidSampleRate','positive sample period required');endif
      if(strcmp(action,'prewarp')),hz=opt(opts,'prewarp_hz',[]);if(isempty(hz)||hz<=0),error('GXTXT:Signal:InvalidFrequency','prewarp_hz required');endif;sys=c2d(sys,Ts,'prewarp',2*pi*hz);
      else sys=c2d(sys,Ts,action);endif
      out=split(sys.A,'A');out.B_real=real(sys.B);out.B_imaginary=imag(sys.B);out.C_real=real(sys.C);out.C_imaginary=imag(sys.C);out.D_real=real(sys.D);out.D_imaginary=imag(sys.D);out.sample_period=Ts;
    otherwise,error('GXTXT:Signal:DimensionMismatch','MIMO state-space conversion to scalar TF/ZPK is undefined');
  endswitch
endfunction
function out=lti_action(action,model,b,c,opts)
  model=lti_model(model,b,c,opts);
  if(complex_model(model)&&any(strcmp(action,{'zoh','foh','tustin','prewarp','matched'})))
    out=complex_discretize(action,model,opts);return;
  endif
  if(strcmp(model.kind,'ss'))
    [n,m,p]=ss_dimensions(model);if(m!=1||p!=1),out=lti_mimo(action,model,opts);return;endif
  endif
  [num,den]=model_tf_coefficients(model);
  if(any(strcmp(action,{'inspect','tf','zpk','ss'})))
    poles_value=roots(den);zeros_value=roots(num);gain_value=num(1);
    switch(action)
      case 'inspect'
        out=split(poles_value,'poles');out.zeros_real=real(zeros_value);out.zeros_imaginary=imag(zeros_value);
        if(strcmp(model.domain,'discrete')),out.stable=all(abs(poles_value)<1);point=1;else out.stable=all(real(poles_value)<0);point=0;endif
        denominator_at_dc=polyval(den,point);out.dc_gain_defined=abs(denominator_at_dc)>eps;
        if(out.dc_gain_defined),value=polyval(num,point)/denominator_at_dc;out.dc_gain_real=real(value);out.dc_gain_imaginary=imag(value);
        else out.dc_gain_real=[];out.dc_gain_imaginary=[];endif
      case 'tf',out=split(num,'numerator');out.denominator_real=real(den);out.denominator_imaginary=imag(den);
      case 'zpk',out=split(zeros_value,'zeros');out.poles_real=real(poles_value);out.poles_imaginary=imag(poles_value);out.gain_real=real(gain_value);out.gain_imaginary=imag(gain_value);
      case 'ss'
        if(strcmp(model.kind,'ss')),A=model.A;B=model.B;C=model.C;D=model.D;else [A,B,C,D]=tf_companion(num,den);endif
        out=split(A,'A');out.B_real=real(B);out.B_imaginary=imag(B);out.C_real=real(C);out.C_imaginary=imag(C);out.D_real=real(D);out.D_imaginary=imag(D);
    endswitch
    return;
  endif
  sys=as_lti(model);
  switch(action)
    case {'zoh','foh','tustin','prewarp','matched'}
      if(!strcmp(model.domain,'continuous')),error('GXTXT:Signal:InvalidModel','continuous model required');endif
      Ts=opt(opts,'sample_period',[]);if(isempty(Ts)||Ts<=0),error('GXTXT:Signal:InvalidSampleRate','positive sample period required');endif
      if(strcmp(action,'prewarp'))
        prewarp=opt(opts,'prewarp_hz',[]);if(isempty(prewarp)||prewarp<=0),error('GXTXT:Signal:InvalidFrequency','positive prewarp frequency in Hz required');endif
        discrete=c2d(sys,Ts,'prewarp',2*pi*prewarp);
      else discrete=c2d(sys,Ts,action);endif
      discrete=tf(discrete);out=split(discrete.num{1},'numerator');out.denominator_real=real(discrete.den{1});out.denominator_imaginary=imag(discrete.den{1});out.sample_period=Ts;
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown LTI action');
  endswitch
endfunction
function out=response_action(action,model,axis,input,opts)
  model=lti_model(model,[],[],opts);
  if(complex_model(model)&&any(strcmp(action,{'impulse','step','input'})))
    out=complex_time_response(action,model,axis,input,opts);return;
  endif
  if(strcmp(model.kind,'ss'))
    [n,m,p]=ss_dimensions(model);
    if(m!=1||p!=1)
      if(any(strcmp(action,{'evaluate','frequency'})))
        valid(axis,'evaluation axis');points=axis(:);value=zeros(numel(points),p,m);
        for k=1:numel(points)
          s=points(k);if(strcmp(action,'frequency'))
            if(strcmp(model.domain,'discrete')),s=exp(1i*2*pi*s*model.sample_period);else s=1i*2*pi*s;endif
          endif
          base=s*eye(n)-model.A;if(rcond(base)<=eps),error('GXTXT:Signal:PoleEvaluation','state-space response is singular at an evaluation point');endif
          value(k,:,:)=model.C*(base\model.B)+model.D;
        endfor
        out=split(value);if(strcmp(action,'frequency')),out.frequency_hz=points;endif
        return;
      endif
      sys=as_lti(model);valid(axis,'time');
      if(strcmp(action,'input')),valid(input,'input');out=split(lsim(sys,input,axis(:),opt(opts,'initial_state',[])));
      elseif(strcmp(action,'step')),out=split(step(sys,axis(:)));
      elseif(strcmp(action,'impulse')),out=split(impulse(sys,axis(:)));
      else error('GXTXT:Signal:UnknownOperation','unknown MIMO response action');endif
      out.time=axis(:);return;
    endif
  endif
  [num,den]=model_tf_coefficients(model);
  switch(action)
    case 'evaluate'
      valid(axis,'complex evaluation points');denominator=polyval(den,axis);
      if(any(abs(denominator(:))<=eps*max(1,norm(den)))),error('GXTXT:Signal:PoleEvaluation','transfer function is singular at an evaluation point');endif
      y=polyval(num,axis)./denominator;out=split(y);
    case 'frequency'
      valid(axis,'frequency');if(any(axis(:)<0)),error('GXTXT:Signal:InvalidGrid','frequency must be nonnegative');endif
      if(strcmp(model.domain,'continuous')),s=1i*2*pi*axis(:);else s=exp(1i*2*pi*axis(:)*model.sample_period);endif
      denominator=polyval(den,s);if(any(abs(denominator(:))<=eps*max(1,norm(den)))),error('GXTXT:Signal:PoleEvaluation','frequency response is singular at an evaluation point');endif
      h=polyval(num,s)./denominator;out=split(h);out.magnitude=abs(h);out.phase_rad=unwrap(angle(h));out.frequency_hz=axis(:);
      if(numel(axis)>1),out.group_delay_seconds=-gradient(out.phase_rad,2*pi*axis(:));endif
    case {'impulse','step','input'}
      sys=as_lti(model);
      valid(axis,'time');if(any(diff(axis(:))<=0)),error('GXTXT:Signal:InvalidGrid','time must increase');endif
      if(strcmp(action,'impulse')),y=impulse(sys,axis(:));elseif(strcmp(action,'step')),y=step(sys,axis(:));else
        valid(input,'input');if(numel(input)!=numel(axis)),error('GXTXT:Signal:DimensionMismatch','input and time lengths differ');endif
        y=lsim(sys,input(:),axis(:),opt(opts,'initial_state',[]));
      endif
      out=split(y);out.time=axis(:);
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown response action');
  endswitch
endfunction
function out=spectral_action(action,x,y,fs,opts)
  valid(x,'signal');valid(fs,'sample rate');if(!isscalar(fs)||fs<=0),error('GXTXT:Signal:InvalidSampleRate','positive sample rate required');endif
  if(strcmp(action,'window_metrics'))
    try out=gxtxt_numeric_v1('window_metrics',x,fs);
    catch err
      err.identifier=strrep(err.identifier,'GXTXT:Numeric:','GXTXT:Signal:');rethrow(err);
    end_try_catch
    return;
  endif
  options=struct();for key={'window','overlap','nfft'}
    if(isfield(opts,key{1})),options.(key{1})=opts.(key{1});endif
  endfor
  try
    if(any(strcmp(action,{'periodogram','welch','asd'})))
      out=gxtxt_numeric_v1(['signal_' action],x,fs,options);
    elseif(any(strcmp(action,{'cross_psd','coherence','frf_h1','frf_h2'})))
      out=gxtxt_numeric_v1(['signal_' action],x,y,fs,options);
    else error('GXTXT:Signal:UnknownOperation','Unknown spectral action');endif
  catch err
    err.identifier=strrep(err.identifier,'GXTXT:Numeric:','GXTXT:Signal:');rethrow(err);
  end_try_catch
endfunction
function out=stft_action(action,x,window,hop,opts)
  valid(window,'window');w=window(:);valid(hop,'hop');if(!isscalar(hop)||hop!=fix(hop)||hop<1||hop>numel(w)),error('GXTXT:Signal:InvalidHop','hop must be integer within window length');endif
  nfft=opt(opts,'nfft',numel(w));if(nfft<numel(w)||nfft!=fix(nfft)),error('GXTXT:Signal:InvalidLength','NFFT must cover window');endif
  switch(action)
    case 'forward'
      valid(x,'signal');x=x(:);original_length=numel(x);pad_left=0;pad_right=0;
      if(opt(opts,'pad',false))
        pad_left=floor(numel(w)/2);pad_right=pad_left;
        x=[zeros(pad_left,1);x;zeros(pad_right,1)];
        extra=mod(hop-mod(numel(x)-numel(w),hop),hop);x=[x;zeros(extra,1)];pad_right+=extra;
      endif
      starts=1:hop:(numel(x)-numel(w)+1);if(isempty(starts)),error('GXTXT:Signal:InvalidLength','signal shorter than window');endif
      S=zeros(nfft,numel(starts));for k=1:numel(starts),S(:,k)=fft(x(starts(k):starts(k)+numel(w)-1).*w,nfft);endfor
      out=split(S);out.sample_positions=starts(:)-1-pad_left;out.frequency_bins=(0:nfft-1)';out.pad_left=pad_left;out.pad_right=pad_right;out.original_length=original_length;
      if(isfield(opts,'sample_rate')),out.time_seconds=out.sample_positions/opts.sample_rate;out.frequency_hz=out.frequency_bins*opts.sample_rate/nfft;endif
    case 'inverse'
      valid(x,'STFT');if(rows(x)!=nfft),error('GXTXT:Signal:DimensionMismatch','STFT row count differs from NFFT');endif
      n=(columns(x)-1)*hop+numel(w);y=zeros(n,1);weight=zeros(n,1);
      for k=1:columns(x),at=(k-1)*hop+(1:numel(w));frame=ifft(x(:,k));y(at)+=frame(1:numel(w)).*w;weight(at)+=w.^2;endfor
      left=opt(opts,'pad_left',0);original=opt(opts,'original_length',n-left);
      if(!isscalar(left)||!isscalar(original)||left<0||original<1||left+original>n),error('GXTXT:Signal:InvalidLength','invalid STFT inverse trim');endif
      retained=(left+1):(left+original);
      if(any(weight(retained)==0)),error('GXTXT:Signal:InvalidWindow','window and hop leave uncovered output samples');endif
      weight(weight==0)=1;reconstructed=y./weight;
      out=split(reconstructed(retained));out.minimum_overlap_weight=min(weight(retained));out.maximum_overlap_weight=max(weight(retained));
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown STFT action');
  endswitch
endfunction
function out=quality_action(action,x,y,fs,opts)
  valid(x,'signal');x=x(:);
  switch(action)
    case 'basic'
      out=gxtxt_numeric_v1('signal_summary',x);
    case {'snr','harmonics','spectrum'}
      try
        if(strcmp(action,'snr')),out=gxtxt_numeric_v1('signal_snr',x,y);
        else
          quality_options=struct();if(isfield(opts,'fundamental_hz')),quality_options.fundamental_hz=opts.fundamental_hz;endif
          out=gxtxt_numeric_v1('signal_spectrum_quality',x,fs,quality_options);
        endif
      catch err
        % Preserve Signal's existing public error namespace after owner migration.
        err.identifier=strrep(err.identifier,'GXTXT:Numeric:','GXTXT:Signal:');rethrow(err);
      end_try_catch
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown quality action');
  endswitch
endfunction
function out=events_action(action,time,x,other,opts)
  valid(time,'time');valid(x,'signal');time=time(:);x=x(:);if(numel(time)!=numel(x)||any(diff(time)<=0)||!isreal(x)),error('GXTXT:Signal:InvalidGrid','real signal and increasing time must match');endif
  level=opt(opts,'threshold',0);direction=opt(opts,'direction','rising');
  if(!any(strcmp(direction,{'rising','falling','both'}))),error('GXTXT:Signal:InvalidPolicy','invalid crossing direction');endif
  hysteresis=opt(opts,'hysteresis',0);if(!isscalar(hysteresis)||!isreal(hysteresis)||hysteresis<0),error('GXTXT:Signal:InvalidThreshold','hysteresis must be nonnegative');endif
  if(hysteresis>0)
    crossing=[];lower=level-hysteresis/2;upper=level+hysteresis/2;
    armed_rising=x(1)<=lower;armed_falling=x(1)>=upper;
    for i=1:numel(x)-1
      if(x(i)<=lower),armed_rising=true;endif
      if(x(i)>=upper),armed_falling=true;endif
      if(armed_rising&&x(i)<upper&&x(i+1)>=upper&&any(strcmp(direction,{'rising','both'})))
        crossing(end+1,1)=time(i)+(upper-x(i))*(time(i+1)-time(i))/(x(i+1)-x(i));armed_rising=false;
      endif
      if(armed_falling&&x(i)>lower&&x(i+1)<=lower&&any(strcmp(direction,{'falling','both'})))
        crossing(end+1,1)=time(i)+(lower-x(i))*(time(i+1)-time(i))/(x(i+1)-x(i));armed_falling=false;
      endif
    endfor
    crossing=sort(crossing);
  else
    indices=find((x(1:end-1)-level).*(x(2:end)-level)<=0 & x(1:end-1)!=x(2:end));
    slope=x(indices+1)-x(indices);if(strcmp(direction,'rising')),indices=indices(slope>0);elseif(strcmp(direction,'falling')),indices=indices(slope<0);endif
    crossing=time(indices)+(level-x(indices)).*(time(indices+1)-time(indices))./(x(indices+1)-x(indices));
  endif
  switch(action)
    case 'crossings',out=struct('time',crossing,'count',numel(crossing));
    case 'period'
      if(numel(crossing)<2),error('GXTXT:Signal:InsufficientEvents','at least two crossings required');endif
      out=gxtxt_numeric_v1('event_period',crossing);out.crossing_times=crossing;
    case 'delay',valid(other,'second signal');r=events_action('crossings',time,other,[],opts);if(isempty(crossing)||isempty(r.time)),error('GXTXT:Signal:InsufficientEvents','both channels require a crossing');endif;out=struct('delay_seconds',r.time(1)-crossing(1));
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown event action');
  endswitch
endfunction
function out=analytic_action(action,x,fs,c,opts)
  valid(x,'real signal');if(!isreal(x)||!isvector(x)),error('GXTXT:Signal:DimensionMismatch','analytic input must be a real vector');endif
  z=hilbert(x(:));phase=unwrap(angle(z));
  switch(action)
    case 'signal',out=split(z);
    case 'envelope',out=struct('amplitude',abs(z));
    case 'phase',out=struct('phase_rad',phase);
    case 'instantaneous_frequency'
      valid(fs,'sample rate');if(!isscalar(fs)||fs<=0),error('GXTXT:Signal:InvalidSampleRate','positive sample rate required');endif
      out=struct('frequency_hz',gradient(phase)*fs/(2*pi));
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown analytic signal action');
  endswitch
endfunction
function out=frequency_metric_action(action,f,H,c,opts)
  valid(H,'frequency response');H=H(:);
  if(strcmp(action,'gain'))
    out=struct('magnitude',abs(H),'gain_db',20*log10(abs(H)),'phase_rad',unwrap(angle(H)));return;
  endif
  valid(f,'frequency');f=f(:);if(!isreal(f)||numel(f)!=numel(H)||numel(f)<2||any(diff(f)<=0))
    error('GXTXT:Signal:InvalidGrid','increasing frequency and response vectors required');
  endif
  phase=unwrap(angle(H));mag=abs(H);db=20*log10(mag);
  switch(action)
    case 'group_delay',out=struct('delay_seconds',-gradient(phase,2*pi*f));
    case 'phase_delay'
      if(any(f<=0)),error('GXTXT:Signal:InvalidGrid','phase delay requires positive frequencies');endif
      out=struct('delay_seconds',-phase./(2*pi*f));
    case {'peak','resonance'}
      [peak,index]=max(mag);out=struct('peak_frequency_hz',f(index),'peak_magnitude',peak,'peak_db',db(index));
    case {'bandwidth','q'}
      [peak,index]=max(mag);threshold=peak/sqrt(2);below=mag<threshold;
      left=find(below(1:index),1,'last');right=index+find(below(index:end),1,'first')-1;
      if(isempty(left)||isempty(right)||left>=index||right<=index),error('GXTXT:Signal:NoCrossing','response does not have two -3 dB crossings');endif
      fl=interp1(mag(left:left+1),f(left:left+1),threshold);fr=interp1(mag(right-1:right),f(right-1:right),threshold);
      out=struct('lower_3db_hz',fl,'upper_3db_hz',fr,'bandwidth_hz',fr-fl,'peak_frequency_hz',f(index),'q',f(index)/(fr-fl));
    case 'margins'
      magdiff=mag-1;idx=find(magdiff(1:end-1).*magdiff(2:end)<=0,1,'first');
      if(isempty(idx)),error('GXTXT:Signal:NoCrossing','loop response has no unity-gain crossover');endif
      fc=interp1(mag(idx:idx+1),f(idx:idx+1),1);phase_at=interp1(f,phase,fc);
      phase_margin=180+phase_at*180/pi;
      out=struct('gain_crossover_hz',fc,'phase_margin_deg',phase_margin);
      phase_diff=phase+pi;j=find(phase_diff(1:end-1).*phase_diff(2:end)<=0,1,'first');
      if(!isempty(j))
        fp=interp1(phase(j:j+1),f(j:j+1),-pi);out.phase_crossover_hz=fp;out.gain_margin_db=-interp1(f,db,fp);
      endif
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown frequency metric');
  endswitch
endfunction
function out=time_metric_action(action,t,y,other,opts)
  valid(t,'time');valid(y,'signal');t=t(:);y=y(:);
  if(!isreal(t)||!isreal(y)||numel(t)!=numel(y)||numel(t)<2||any(diff(t)<=0))
    error('GXTXT:Signal:InvalidGrid','real signal and increasing time vectors required');
  endif
  switch(action)
    case 'step'
      baseline=opt(opts,'baseline',y(1));final=opt(opts,'final',y(end));delta=final-baseline;
      if(delta==0),error('GXTXT:Signal:ZeroStep','step amplitude is zero');endif
      normalized=(y-baseline)/delta;lower=opt(opts,'lower_fraction',0.1);upper=opt(opts,'upper_fraction',0.9);settle=opt(opts,'settling_fraction',0.02);
      if(lower<0||upper>1||lower>=upper||settle<=0),error('GXTXT:Signal:InvalidThreshold','invalid step thresholds');endif
      tlo=first_cross(t,normalized,lower);thi=first_cross(t,normalized,upper);
      err=abs(normalized-1);last=find(err>settle,1,'last');if(isempty(last)),settling=t(1);elseif(last==numel(t)),settling=NaN;else settling=t(last+1);endif
      [peak,index]=max(normalized);out=struct('rise_time_seconds',thi-tlo,'lower_crossing_seconds',tlo,'upper_crossing_seconds',thi,'settling_time_seconds',settling,'overshoot_fraction',max(0,peak-1),'peak_time_seconds',t(index),'steady_state_value',final);
      out.undershoot_fraction=max(0,-min(normalized));
      if(delta<0),out.fall_time_seconds=out.rise_time_seconds;out.rise_time_seconds=[];endif
    case 'slew',slope=diff(y)./diff(t);out=struct('maximum_slew_per_second',max(slope),'minimum_slew_per_second',min(slope));
    case 'pulse'
      threshold=opt(opts,'threshold',(max(y)+min(y))/2);
      rising=events_action('crossings',t,y,[],struct('threshold',threshold,'direction','rising'));
      falling=events_action('crossings',t,y,[],struct('threshold',threshold,'direction','falling'));
      if(numel(rising.time)<2||isempty(falling.time)),error('GXTXT:Signal:InsufficientEvents','pulse metrics require repeated rising and falling crossings');endif
      try out=gxtxt_numeric_v1('pulse_timing',rising.time,falling.time);
      catch err
        if(!isempty(strfind(err.message,'No complete pulse width'))),error('GXTXT:Signal:InsufficientEvents','no complete pulse width');endif
        rethrow(err);
      end_try_catch
    otherwise,error('GXTXT:Signal:UnknownOperation','unknown time metric');
  endswitch
endfunction
function tc=first_cross(t,y,level)
  k=find(y(1:end-1)<level & y(2:end)>=level,1,'first');if(isempty(k)),error('GXTXT:Signal:NoCrossing','threshold was not crossed');endif
  tc=t(k)+(level-y(k))*(t(k+1)-t(k))/(y(k+1)-y(k));
endfunction
function tf=complex_model(model)
  switch(model.kind)
    case 'tf',tf=!isreal(model.numerator)||!isreal(model.denominator);
    case 'zpk',tf=!isreal(model.zeros)||!isreal(model.poles)||!isreal(model.gain);
    case 'ss',tf=!isreal(model.A)||!isreal(model.B)||!isreal(model.C)||!isreal(model.D);
  endswitch
endfunction
function [A,B,C,D]=model_ss_matrices(model)
  if(strcmp(model.kind,'ss'))
    ss_dimensions(model);A=model.A;B=model.B;C=model.C;D=model.D;
  else
    [num,den]=model_tf_coefficients(model);[A,B,C,D]=tf_companion(num,den);
  endif
endfunction
function out=complex_discretize(action,model,opts)
  if(!strcmp(model.domain,'continuous')),error('GXTXT:Signal:InvalidModel','continuous model required');endif
  Ts=opt(opts,'sample_period',[]);if(isempty(Ts)||!isscalar(Ts)||Ts<=0),error('GXTXT:Signal:InvalidSampleRate','positive sample period required');endif
  [A,B,C,D]=model_ss_matrices(model);n=rows(A);m=columns(B);
  switch(action)
    case 'zoh'
      block=zeros(n+m);block(1:n,1:n)=A;block(1:n,n+1:end)=B;E=expm(Ts*block);
      Ad=E(1:n,1:n);Bd=E(1:n,n+1:end);Cd=C;Dd=D;
    case 'foh'
      block=zeros(n+2*m);block(1:n,1:n)=A;block(1:n,n+1:n+m)=B;block(n+1:n+m,n+m+1:end)=eye(m);
      E=expm(Ts*block);Ad=E(1:n,1:n);G0=E(1:n,n+1:n+m);G1=E(1:n,n+m+1:end)/Ts;
      Bd=G0+(Ad-eye(n))*G1;Cd=C;Dd=D+C*G1;
    case 'matched'
      if(m!=1||rows(C)!=1),error('GXTXT:Signal:DimensionMismatch','matched-pole-zero discretization requires SISO');endif
      [num,den]=model_tf_coefficients(model);pz=exp(roots(den)*Ts);zz=exp(roots(num)*Ts);
      d=poly(pz);z=poly(zz);z=[zeros(1,numel(d)-numel(z)),z];
      hdc=polyval(num,0)/polyval(den,0);gain=hdc*polyval(d,1)/polyval(z,1);z=gain*z;
      [Ad,Bd,Cd,Dd]=tf_companion(z,d);
    case {'tustin','prewarp'}
      effective=Ts;
      if(strcmp(action,'prewarp'))
        hz=opt(opts,'prewarp_hz',[]);if(isempty(hz)||hz<=0),error('GXTXT:Signal:InvalidFrequency','prewarp_hz required');endif
        omega=2*pi*hz;effective=2*tan(omega*Ts/2)/omega;
      endif
      Q=eye(n)-effective*A/2;if(rcond(Q)<=eps),error('GXTXT:Signal:IllConditioned','bilinear transform matrix is singular');endif
      Ad=Q\(eye(n)+effective*A/2);Bd=Q\(effective*B);Cd=C/Q;Dd=D+C*(Q\B)*effective/2;
    otherwise,error('GXTXT:Signal:UnsupportedComplexTime','unsupported complex discretization method');
  endswitch
  out=split(Ad,'A');out.B_real=real(Bd);out.B_imaginary=imag(Bd);out.C_real=real(Cd);out.C_imaginary=imag(Cd);out.D_real=real(Dd);out.D_imaginary=imag(Dd);out.sample_period=Ts;
endfunction
function out=complex_time_response(action,model,time,input,opts)
  valid(time,'time');time=time(:);if(!isreal(time)||numel(time)<2||any(diff(time)<=0)),error('GXTXT:Signal:InvalidGrid','time must be strictly increasing');endif
  [A,B,C,D]=model_ss_matrices(model);n=rows(A);m=columns(B);p=rows(C);nt=numel(time);
  state_model=struct('A',A,'B',B,'C',C,'D',D,'domain',model.domain);
  x0=opt(opts,'initial_state',zeros(n,1));if(numel(x0)!=n),error('GXTXT:Signal:DimensionMismatch','initial state size differs from A');endif;x0=x0(:);
  if(strcmp(model.domain,'discrete'))
    Ts=model.sample_period;if(max(abs(diff(time)-Ts))>1e-8*Ts),error('GXTXT:Signal:InvalidGrid','discrete response times must match sample period');endif
  endif
  if(strcmp(action,'impulse'))
    y=zeros(nt,p,m);
    for k=1:nt
      if(strcmp(model.domain,'continuous'))
        state=expm(A*(time(k)-time(1)))*B;y(k,:,:)=C*state;
      else
        if(k==1),y(k,:,:)=D;else y(k,:,:)=C*(A^(k-2))*B;endif
      endif
    endfor
    out=split(y);out.direct_feedthrough_real=real(D);out.direct_feedthrough_imaginary=imag(D);out.time=time;return;
  endif
  if(strcmp(action,'step'))
    y=zeros(nt,p,m);for j=1:m
      U=zeros(nt,m);U(:,j)=1;y(:,:,j)=complex_input_response(state_model,time,U,x0);
    endfor
  elseif(strcmp(action,'input'))
    valid(input,'input');if(isscalar(input)&&m==1),input=repmat(input,nt,1);endif
    if(rows(input)!=nt||columns(input)!=m),error('GXTXT:Signal:DimensionMismatch','input must have time-by-input shape');endif
    y=complex_input_response(state_model,time,input,x0);
  else error('GXTXT:Signal:UnknownOperation','unknown time response action');endif
  if(p==1&&m==1),y=y(:);endif
  out=split(y);out.time=time;
endfunction
function y=complex_input_response(model,time,U,x0)
  A=model.A;B=model.B;C=model.C;D=model.D;n=rows(A);nt=numel(time);p=rows(C);y=zeros(nt,p);x=x0;
  if(strcmp(model.domain,'continuous'))
    rhs=@(t,state) A*state+B*interp1(time,U,t,'linear','extrap').';
    [~,states]=ode45(rhs,time,x0);
    for k=1:nt,y(k,:)=(C*states(k,:).'+D*U(k,:).').';endfor
  else
    for k=1:nt
      y(k,:)=(C*x+D*U(k,:).').';x=A*x+B*U(k,:).';
    endfor
  endif
endfunction
