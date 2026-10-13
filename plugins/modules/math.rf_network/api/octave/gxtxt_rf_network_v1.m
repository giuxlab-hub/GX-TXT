% RF_NETWORK_API_v1 complex network post-processing primitives.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_rf_network_v1(family,action,a,b,c,opts)
  if(nargin<2||!ischar(family)||!ischar(action)),error('GXTXT:RF:InvalidArguments','family and action are required');endif
  if(nargin<3),a=[];endif;if(nargin<4),b=[];endif;if(nargin<5),c=[];endif;if(nargin<6),opts=struct();endif
  if(!isstruct(opts)),error('GXTXT:RF:InvalidArguments','options must be a struct');endif
  family=lower(strtrim(family));action=lower(strtrim(action));
  switch(family)
    case 'convert',out=convert_action(action,a,b,opts);
    case 'compose',out=compose_action(action,a,b,opts);
    case 'metric',out=metric_action(action,a,b,c,opts);
    case 'quality',out=quality_action(action,a,b,opts);
    case 'sweep',out=sweep_action(action,a,b,opts);
    case 'calibration',out=calibration_action(action,a,b,c,opts);
    otherwise,error('GXTXT:RF:UnknownOperation','unknown RF family');
  endswitch
endfunction
function v=opt(s,k,d),v=d;if(isfield(s,k)),v=s.(k);endif,endfunction
function valid(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:RF:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
function out=split(v)
  if(any(!isfinite(real(v(:))))||any(!isfinite(imag(v(:))))),error('GXTXT:RF:NonFiniteResult','network result is nonfinite');endif
  out=struct('value_real',real(v),'value_imaginary',imag(v));
endfunction
function n=network_size(M)
  valid(M,'network matrix');if(!ismatrix(M)||rows(M)!=columns(M)),error('GXTXT:RF:DimensionMismatch','network matrix must be square');endif;n=rows(M);
endfunction
function D=impedance(z0,n)
  if(isempty(z0)),z0=50;endif
  valid(z0,'reference impedance');if(isscalar(z0)),z0=repmat(z0,n,1);endif
  if(!isreal(z0)||numel(z0)!=n||any(z0(:)<=0)),error('GXTXT:RF:InvalidReference','reference impedance must be positive real scalar or per-port vector');endif
  D=diag(sqrt(z0(:)));
endfunction
function [Z0,D,C]=wave_reference(z0,n,opts)
  if(isempty(z0)),z0=50;endif
  valid(z0,'reference impedance');if(isscalar(z0)),z0=repmat(z0,n,1);endif
  if(numel(z0)!=n||any(real(z0(:))<=0)),error('GXTXT:RF:InvalidReference','each reference impedance must have positive real part');endif
  convention=opt(opts,'wave_convention','power');
  if(!any(strcmp(convention,{'power','traveling'}))),error('GXTXT:RF:InvalidReference','wave_convention must be power or traveling');endif
  Z0=diag(z0(:));
  if(strcmp(convention,'power')),D=diag(sqrt(real(z0(:))));C=conj(Z0);
  else,D=diag(sqrt(z0(:)));C=Z0;endif
endfunction
function check_condition(M,opts)
  limit=opt(opts,'condition_limit',1e12);if(!isscalar(limit)||limit<1||!isfinite(limit)),error('GXTXT:RF:InvalidTolerance','condition limit must be finite and >=1');endif
  if(rcond(M)<1/limit),error('GXTXT:RF:IllConditioned','network conversion is singular or ill-conditioned');endif
endfunction
function Z=to_z(kind,M,z0,opts)
  n=network_size(M);[Z0,D,C]=wave_reference(z0,n,opts);I=eye(n);
  switch(kind)
    case 'z',Z=M;
    case 'y',check_condition(M,opts);Z=M\I;
    case 's',X=D*M/D;check_condition(I-X,opts);Z=(I-X)\(X*Z0+C);
    case 'h'
      if(n!=2||abs(M(2,2))<eps),error('GXTXT:RF:Singular','H to Z requires nonzero h22');endif
      Z=[M(1,1)-M(1,2)*M(2,1)/M(2,2),M(1,2)/M(2,2);-M(2,1)/M(2,2),1/M(2,2)];
    case 't'
      if(n!=2||abs(M(1,1))<eps),error('GXTXT:RF:Singular','T to S requires nonzero T11');endif
      S=[M(2,1)/M(1,1),det(M)/M(1,1);1/M(1,1),-M(1,2)/M(1,1)];Z=to_z('s',S,z0,opts);
    case 'abcd'
      if(n!=2),error('GXTXT:RF:DimensionMismatch','ABCD representation requires two ports');endif
      if(abs(M(2,1))<eps*norm(M,'fro')),error('GXTXT:RF:Singular','ABCD to Z requires nonzero C');endif
      A=M(1,1);B=M(1,2);C=M(2,1);T=M(2,2);Z=[A/C,(A*T-B*C)/C;1/C,T/C];
    otherwise,error('GXTXT:RF:InvalidRepresentation','representation must be s, z, y or abcd');
  endswitch
endfunction
function M=from_z(kind,Z,z0,opts)
  n=network_size(Z);[Z0,D,C]=wave_reference(z0,n,opts);I=eye(n);
  switch(kind)
    case 'z',M=Z;
    case 'y',check_condition(Z,opts);M=Z\I;
    case 's',check_condition(Z+Z0,opts);M=(D\((Z-C)/(Z+Z0)))*D;
    case 'h'
      if(n!=2||abs(Z(2,2))<eps),error('GXTXT:RF:Singular','Z to H requires nonzero Z22');endif
      M=[Z(1,1)-Z(1,2)*Z(2,1)/Z(2,2),Z(1,2)/Z(2,2);-Z(2,1)/Z(2,2),1/Z(2,2)];
    case 't'
      if(n!=2),error('GXTXT:RF:DimensionMismatch','T requires two ports');endif
      S=from_z('s',Z,z0,opts);if(abs(S(2,1))<eps),error('GXTXT:RF:Singular','S to T requires nonzero S21');endif
      M=[1,-S(2,2);S(1,1),-det(S)]/S(2,1);
    case 'abcd'
      if(n!=2),error('GXTXT:RF:DimensionMismatch','ABCD representation requires two ports');endif
      if(abs(Z(2,1))<eps*norm(Z,'fro')),error('GXTXT:RF:Singular','Z to ABCD requires nonzero Z21');endif
      M=[Z(1,1)/Z(2,1),det(Z)/Z(2,1);1/Z(2,1),Z(2,2)/Z(2,1)];
    otherwise,error('GXTXT:RF:InvalidRepresentation','representation must be s, z, y or abcd');
  endswitch
endfunction
function out=convert_action(action,M,z0,opts)
  source=opt(opts,'source','s');target=opt(opts,'target','z');
  if(strcmp(action,'renormalize'))
    old=opt(opts,'old_z0',z0);new=opt(opts,'new_z0',[]);if(isempty(new)),error('GXTXT:RF:InvalidReference','new_z0 is required');endif
    if(isequal(old,new)),n=network_size(M);impedance(old,n);out=split(M);return;endif
    Z=to_z('s',M,old,opts);out=split(from_z('s',Z,new,opts));return;
  elseif(!strcmp(action,'representation')),error('GXTXT:RF:UnknownOperation','unknown conversion action');endif
  if(strcmp(source,target))
    if(!any(strcmp(source,{'s','z','y','abcd','h','t'}))),error('GXTXT:RF:InvalidRepresentation','unknown network representation');endif
    n=network_size(M);if(strcmp(source,'abcd')&&n!=2),error('GXTXT:RF:DimensionMismatch','ABCD requires two ports');endif
    wave_reference(z0,n,opts);out=split(M);out.source=source;out.target=target;return;
  endif
  if(strcmp(source,'s')&&strcmp(target,'abcd')&&isscalar(z0)&&isreal(z0))
    if(!isequal(size(M),[2 2])||abs(M(2,1))<=eps),error('GXTXT:RF:Singular','S to ABCD requires nonzero S21');endif
    s11=M(1,1);s12=M(1,2);s21=M(2,1);s22=M(2,2);
    V=[((1+s11)*(1-s22)+s12*s21)/(2*s21),z0*((1+s11)*(1+s22)-s12*s21)/(2*s21); ...
       ((1-s11)*(1-s22)-s12*s21)/(2*z0*s21),((1-s11)*(1+s22)+s12*s21)/(2*s21)];
  elseif(strcmp(source,'abcd')&&strcmp(target,'s')&&isscalar(z0)&&isreal(z0))
    if(!isequal(size(M),[2 2])),error('GXTXT:RF:DimensionMismatch','ABCD requires two ports');endif
    A=M(1,1);B=M(1,2);C=M(2,1);D=M(2,2);den=A+B/z0+C*z0+D;
    if(abs(den)<=eps*norm(M,'fro')),error('GXTXT:RF:Singular','ABCD to S denominator is zero');endif
    V=[(A+B/z0-C*z0-D)/den,2*det(M)/den;2/den,(-A+B/z0-C*z0+D)/den];
  else
    Z=to_z(source,M,z0,opts);V=from_z(target,Z,z0,opts);
  endif
  out=split(V);out.source=source;out.target=target;
endfunction
function out=compose_action(action,A,B,opts)
  valid(A,'first two-port');if(!isequal(size(A),[2 2])),error('GXTXT:RF:DimensionMismatch','composition requires 2-port matrices');endif
  switch(action)
    case 'cascade',valid(B,'second two-port');if(!isequal(size(B),[2 2])),error('GXTXT:RF:DimensionMismatch','second matrix must be 2 by 2');endif;v=A*B;
    case 'deembed_left',valid(B,'fixture');check_condition(B,opts);v=B\A;
    case 'deembed_right',valid(B,'fixture');check_condition(B,opts);v=A/B;
    case 'deembed_both'
      if(!isfield(opts,'right_fixture')),error('GXTXT:RF:InvalidArguments','right fixture required');endif
      R=opts.right_fixture;valid(R,'right fixture');check_condition(B,opts);check_condition(R,opts);v=B\A/R;
    case 'series',valid(B,'second Z matrix');v=A+B;
    case 'shunt',valid(B,'second Y matrix');v=A+B;
    case 'port_extension'
      frequency=opt(opts,'frequency_hz',[]);delays=opt(opts,'delay_seconds',[]);
      valid(frequency,'frequency');valid(delays,'port delays');
      if(!isscalar(frequency)||numel(delays)!=2||frequency<0||any(delays(:)<0)),error('GXTXT:RF:InvalidArguments','port extension needs nonnegative frequency and two delays');endif
      phase=exp(-1i*2*pi*frequency*delays(:));v=A.*(phase*phase.');
    otherwise,error('GXTXT:RF:UnknownOperation','unknown composition action');
  endswitch
  out=split(v);
endfunction
function out=metric_action(action,S,z0,frequency,opts)
  if(any(strcmp(action,{'group_delay','phase_delay'})))
    valid(S,'complex sweep');valid(frequency,'frequency');
    if(!isvector(S)||!isvector(frequency)||numel(S)!=numel(frequency)||numel(S)<2||any(diff(frequency(:))<=0))
      error('GXTXT:RF:DimensionMismatch','frequency and complex sweep must be matching increasing vectors');
    endif
    phase=unwrap(angle(S(:)));
    if(strcmp(action,'group_delay')),v=-gradient(phase,2*pi*frequency(:));else
      if(any(frequency(:)<=0)),error('GXTXT:RF:InvalidFrequency','phase delay requires positive frequency');endif
      v=-phase./(2*pi*frequency(:));
    endif
    out=split(v);return;
  endif
  n=network_size(S);default_port=1;default_source=1;
  if(strcmp(action,'insertion_loss')),default_port=2;endif
  if(strcmp(action,'isolation')),default_source=2;endif
  p=opt(opts,'port',default_port);q=opt(opts,'source_port',default_source);
  if(p<1||p>n||q<1||q>n||p!=fix(p)||q!=fix(q)),error('GXTXT:RF:InvalidPort','port index outside network');endif
  switch(action)
    case 'return_loss',v=-20*log10(abs(S(p,p)));
    case 'insertion_loss',if(n<2),error('GXTXT:RF:DimensionMismatch','insertion loss needs two ports');endif;v=-20*log10(abs(S(p,q)));
    case 'isolation',v=-20*log10(abs(S(p,q)));
    case 'vswr',rho=abs(S(p,p));if(rho>=1),error('GXTXT:RF:InvalidReflection','VSWR is unbounded for |reflection| >=1');endif;v=(1+rho)/(1-rho);
    case 'reflection',v=S(p,p);
    case 'transmission',v=S(p,q);
    case {'impedance','admittance'}
      [Z0,~,C]=wave_reference(z0,n,opts);gamma=S(p,p);
      if(abs(1-gamma)<eps),error('GXTXT:RF:Singular','reflection to impedance is singular');endif
      z=(gamma*Z0(p,p)+C(p,p))/(1-gamma);
      if(strcmp(action,'impedance')),v=z;else
        if(abs(z)<eps),error('GXTXT:RF:Singular','port admittance is singular');endif
        v=1/z;
      endif
    case 'transducer_gain'
      if(n!=2),error('GXTXT:RF:DimensionMismatch','transducer gain requires two ports');endif
      gs=opt(opts,'gamma_source',0);gl=opt(opts,'gamma_load',0);
      if(abs(gs)>=1||abs(gl)>=1),error('GXTXT:RF:InvalidReflection','source/load reflection magnitude must be <1');endif
      den=(1-S(1,1)*gs)*(1-S(2,2)*gl)-S(1,2)*S(2,1)*gs*gl;
      if(abs(den)<=eps),error('GXTXT:RF:Singular','transducer gain denominator is zero');endif
      v=abs(S(2,1))^2*(1-abs(gs)^2)*(1-abs(gl)^2)/abs(den)^2;
    otherwise,error('GXTXT:RF:UnknownOperation','unknown RF metric');
  endswitch
  out=split(v);
endfunction
function out=quality_action(action,S,z0,opts)
  if(strcmp(action,'causality'))
    valid(S,'two-sided frequency response');valid(z0,'frequency axis');f=z0(:);h=S(:);
    if(numel(f)!=numel(h)||numel(f)<8||any(diff(f)<=0)||max(abs(diff(f)-mean(diff(f))))>1e-8*mean(diff(f))||abs(f(1)+f(end)+mean(diff(f)))>1e-7*max(abs(f)))
      error('GXTXT:RF:InvalidSweep','causality requires a uniform two-sided FFT frequency grid in ascending centered order');
    endif
    impulse=ifft(ifftshift(h));n=numel(h);negative=impulse(floor(n/2)+2:end);
    ratio=sum(abs(negative).^2)/max(sum(abs(impulse).^2),eps);tol=opt(opts,'tolerance',1e-3);
    out=struct('negative_time_energy_fraction',ratio,'pass',ratio<=tol,'method','two_sided_ifft');return;
  endif
  n=network_size(S);tol=opt(opts,'tolerance',1e-9);
  if(!isscalar(tol)||tol<0||!isfinite(tol)),error('GXTXT:RF:InvalidTolerance','invalid quality tolerance');endif
  switch(action)
    case 'reciprocity',if(n==2),res=abs(S(1,2)-S(2,1));else res=norm(S-S.','fro');endif;out=struct('pass',res<=tol,'residual',res);
    case 'passivity',lambda=eig(S'*S);res=max(real(lambda))-1;out=struct('pass',res<=tol,'maximum_power_gain',max(real(lambda)),'residual',max(0,res));
    case 'losslessness',res=norm(S'*S-eye(n),'fro');out=struct('pass',res<=tol,'residual',res);
    case 'stability'
      if(n!=2),error('GXTXT:RF:DimensionMismatch','two-port stability metrics require 2 by 2 S');endif
      delta=det(S);den=2*abs(S(1,2)*S(2,1));numerator=1-abs(S(1,1))^2-abs(S(2,2))^2+abs(delta)^2;
      if(den==0),K=sign(numerator)*Inf;else K=numerator/den;endif
      mu=(1-abs(S(1,1))^2)/(abs(S(2,2)-delta*conj(S(1,1)))+abs(S(1,2)*S(2,1)));
      out=struct('rollet_k',K,'mu',mu,'delta_magnitude',abs(delta),'unconditionally_stable',K>1&&abs(delta)<1);
      if(K>1&&den>0),out.maximum_available_gain=abs(S(2,1)/S(1,2))/(K+sqrt(K^2-1));endif
      if(den>0),out.maximum_stable_gain=abs(S(2,1)/S(1,2));endif
    otherwise,error('GXTXT:RF:UnknownOperation','unknown quality action');
  endswitch
endfunction
function out=calibration_action(action,measured,known,query,opts)
  switch(action)
    case 'one_port_solve'
      valid(measured,'measured standards');valid(known,'known standards');m=measured(:);g=known(:);
      if(numel(m)<3||numel(m)!=numel(g)),error('GXTXT:RF:DimensionMismatch','three or more matching one-port standards required');endif
      A=[ones(numel(m),1),g,-m.*g];if(rank(A)<3),error('GXTXT:RF:IllConditioned','calibration standards are not independent');endif
      e=A\m;out=struct('directivity_real',real(e(1)),'directivity_imaginary',imag(e(1)), ...
        'tracking_real',real(e(2)),'tracking_imaginary',imag(e(2)), ...
        'source_match_real',real(e(3)),'source_match_imaginary',imag(e(3)),'residual_norm',norm(A*e-m));
    case 'one_port_apply'
      valid(measured,'measured reflection');if(!isstruct(known)),error('GXTXT:RF:InvalidArguments','calibration coefficients struct required');endif
      e0=known.directivity_real+1i*known.directivity_imaginary;
      e1=known.tracking_real+1i*known.tracking_imaginary;
      e2=known.source_match_real+1i*known.source_match_imaginary;
      if(any(abs(e1-e2*measured(:))<eps)),error('GXTXT:RF:Singular','one-port calibration denominator is zero');endif
      out=split((measured-e0)./(e1-e2*measured));
    otherwise,error('GXTXT:RF:UnknownOperation','unknown calibration action');
  endswitch
endfunction
function out=sweep_action(action,frequency,data,opts)
  valid(frequency,'frequency');valid(data,'complex sweep');frequency=frequency(:);
  if(!isreal(frequency)||any(diff(frequency)<=0)||numel(frequency)!=size(data,1)),error('GXTXT:RF:InvalidSweep','frequency axis must strictly increase and match first data dimension');endif
  switch(action)
    case 'describe',out=struct('frequency_hz',frequency,'real',real(data),'imaginary',imag(data),'magnitude',abs(data),'phase_rad',unwrap(angle(data)));
    case {'convert','renormalize'}
      if(ndims(data)!=3||size(data,2)!=size(data,3)),error('GXTXT:RF:DimensionMismatch','sweep conversion requires N by P by P matrices');endif
      result=zeros(size(data));for k=1:numel(frequency)
        reference=sweep_reference(opt(opts,'reference_impedance',50),k,numel(frequency),size(data,2));
        local=opts;if(strcmp(action,'convert'))
          r=convert_action('representation',squeeze(data(k,:,:)),reference,local);
        else
          local.old_z0=sweep_reference(opt(opts,'old_z0',reference),k,numel(frequency),size(data,2));
          local.new_z0=sweep_reference(opt(opts,'new_z0',[]),k,numel(frequency),size(data,2));
          r=convert_action('renormalize',squeeze(data(k,:,:)),local.old_z0,local);
        endif
        result(k,:,:)=complex(r.value_real,r.value_imaginary);
      endfor
      out=split(result);out.frequency_hz=frequency;
    case 'group_delay'
      if(ndims(data)!=3||size(data,2)!=size(data,3)),error('GXTXT:RF:DimensionMismatch','group delay requires N by P by P matrices');endif
      p=opt(opts,'port',2);q=opt(opts,'source_port',1);if(p<1||q<1||p>size(data,2)||q>size(data,3)),error('GXTXT:RF:InvalidPort','selected sweep ports are invalid');endif
      response=squeeze(data(:,p,q));r=metric_action('group_delay',response,[],frequency,opts);out=r;out.frequency_hz=frequency;
    case 'mixed_mode'
      if(ndims(data)!=3||size(data,2)!=4||size(data,3)!=4),error('GXTXT:RF:DimensionMismatch','mixed-mode conversion requires N by 4 by 4 S matrices');endif
      T=[1 -1 0 0;1 1 0 0;0 0 1 -1;0 0 1 1]/sqrt(2);v=zeros(size(data));for k=1:numel(frequency),v(k,:,:)=T*squeeze(data(k,:,:))*T.';endfor;out=split(v);out.frequency_hz=frequency;
    otherwise,error('GXTXT:RF:UnknownOperation','unknown sweep action');
  endswitch
endfunction
function z=sweep_reference(reference,k,nf,np)
  valid(reference,'reference impedance');
  if(isscalar(reference)),z=reference;
  elseif(isvector(reference)&&numel(reference)==np),z=reference(:);
  elseif(ismatrix(reference)&&isequal(size(reference),[nf,np])),z=reference(k,:).';
  else error('GXTXT:RF:DimensionMismatch','reference impedance must be scalar, per-port vector or frequency-by-port array');endif
endfunction
