function out=gxtxt_numeric_signal_summary_v1(x,options)
% Public Numeric owner of descriptive real/complex signal moments.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<2),options=struct();endif
  if(!isstruct(options)||!isempty(fieldnames(options))),error('GXTXT:Numeric','signal_summary has no estimator options');endif
  if(!isnumeric(x)||!isvector(x)||isempty(x)||any(!isfinite(real(x(:))))||any(!isfinite(imag(x(:)))))
    error('GXTXT:Numeric','signal_summary requires a nonempty finite real or complex vector');
  endif
  x=x(:);n=numel(x);magnitude=abs(x);peak=max(magnitude);
  if(!isfinite(peak)),error('GXTXT:Numeric','signal magnitude exceeds binary64 range');endif
  if(peak==0),rms_value=0;crest=NaN;
  else normalized_rms=norm(magnitude/peak)/sqrt(n);rms_value=peak*normalized_rms;crest=1/normalized_rms;endif
  % Divide before summation so a finite mean does not overflow its raw sum.
  out=struct('n',n,'rms',rms_value,'peak',peak, ...
    'peak_to_peak',max(real(x))-min(real(x)),'crest_factor',crest, ...
    'dc_real',sum(real(x)/n),'dc_imaginary',sum(imag(x)/n), ...
    'input_kind',ternary(isreal(x),'real','complex'),'method','descriptive_complex_magnitude');
endfunction
function value=ternary(condition,yes,no),if(condition),value=yes;else value=no;endif;endfunction
