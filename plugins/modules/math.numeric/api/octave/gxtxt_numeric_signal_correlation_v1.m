function out=gxtxt_numeric_signal_correlation_v1(x,y,options)
% Uncentered finite-sequence correlation; lag k sums x(j+k)*conj(y(j)).
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!isstruct(options)||!isscalar(options)||any(!ismember(fieldnames(options),{'normalization','sample_rate'})))
    error('GXTXT:Numeric:InvalidPolicy','Correlation accepts normalization and sample_rate');
  endif
  valid(x,'first signal');if(isempty(y)),y=x;else valid(y,'second signal');endif
  x=double(x(:));y=double(y(:));nx=numel(x);ny=numel(y);
  mode='none';if(isfield(options,'normalization')),mode=options.normalization;endif
  if(!ischar(mode)||!any(strcmp(mode,{'none','biased','unbiased','coefficient'})))
    error('GXTXT:Numeric:InvalidPolicy','Unknown correlation normalization');
  endif
  rate=NaN;if(isfield(options,'sample_rate'))
    rate=options.sample_rate;
    if(!isnumeric(rate)||!isreal(rate)||!isscalar(rate)||!isfinite(rate)||rate<=0)
      error('GXTXT:Numeric:InvalidSampleRate','Sample rate must be finite and positive');
    endif
  endif
  lags=(-(ny-1):nx-1)';
  if(strcmp(mode,'coefficient'))
    % Normalize each input before convolution, avoiding squared-energy
    % overflow/underflow. No centering or sample covariance is introduced.
    sx=max(max(abs(real(x))),max(abs(imag(x))));sy=max(max(abs(real(y))),max(abs(imag(y))));
    if(sx==0||sy==0),error('GXTXT:Numeric:ZeroEnergy','Cannot normalize zero-energy signal');endif
    xx=x/sx;yy=y/sy;xx/=sqrt(sum(abs(xx).^2));yy/=sqrt(sum(abs(yy).^2));
    r=conv(xx,flipud(conj(yy)));
  else
    r=conv(x,flipud(conj(y)));
    if(strcmp(mode,'biased')),r/=max(nx,ny);
    elseif(strcmp(mode,'unbiased'))
      overlap=max(0,min(nx,ny+lags)-max(1,1+lags)+1);r=r./overlap;
    endif
  endif
  [peak,index]=max(abs(r));resolved=all(isfinite(real(r)))&&all(isfinite(imag(r)))&&isfinite(peak)&&peak>0;
  kind='real';if(!isreal(x)||!isreal(y)),kind='complex';endif
  out=struct('value_real',real(r),'value_imaginary',imag(r),'lags',lags, ...
    'delay_samples',lags(index),'delay_seconds',lags(index)/rate, ...
    'n',nx,'n_x',nx,'n_y',ny,'lag_count',numel(lags),'sample_rate',rate, ...
    'peak_magnitude',peak,'peak_value_real',real(r(index)),'peak_value_imaginary',imag(r(index)), ...
    'peak_resolved',resolved,'input_kind',kind,'normalization',mode, ...
    'method','uncentered_conjugate_sequence_correlation','peak_policy','first_maximum_absolute_in_ascending_lag');
endfunction
function valid(x,name)
  if(!isnumeric(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Numeric:InvalidOperand','%s must be finite and nonempty',name);
  endif
endfunction
