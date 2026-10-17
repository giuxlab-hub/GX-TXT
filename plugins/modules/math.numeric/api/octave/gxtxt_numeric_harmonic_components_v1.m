function out=gxtxt_numeric_harmonic_components_v1(orders,expected,detected,amplitudes,options)
% Public amplitude-level calculation with preserved component identities.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<5),options=struct();endif
  if(!isstruct(options)||!isscalar(options)||any(!ismember(fieldnames(options),{'fundamental_amplitude','level_floor','component_method'}))),error('GXTXT:Numeric:InvalidPolicy','invalid harmonic component options');endif
  arrays={orders,expected,detected,amplitudes};n=numel(orders);
  for k=1:4
    value=arrays{k};if(!isnumeric(value)||!isreal(value)||(!isempty(value)&&!isvector(value))||numel(value)!=n||any(!isfinite(value(:)))),error('GXTXT:Numeric:InvalidOperand','harmonic columns must be equal finite real vectors');endif
  endfor
  if(n>65536||any(orders(:)<1)||any(orders(:)!=fix(orders(:)))||any(diff(orders(:))<=0)||any(amplitudes(:)<0)),error('GXTXT:Numeric:InvalidOperand','invalid bounded harmonic identities or amplitudes');endif
  reference=[];if(isfield(options,'fundamental_amplitude')),reference=options.fundamental_amplitude;endif
  if(!isnumeric(reference)||!isscalar(reference)||!isreal(reference)||!isfinite(reference)||reference<0),error('GXTXT:Numeric:InvalidOperand','nonnegative finite fundamental amplitude is required');endif
  floor_policy='none';if(isfield(options,'level_floor')),floor_policy=options.level_floor;endif
  method='supplied_component_amplitude';if(isfield(options,'component_method')),method=options.component_method;endif
  if(!ischar(floor_policy)||!any(strcmp(floor_policy,{'none','realmin'}))||!ischar(method)||!any(strcmp(method,{'supplied_component_amplitude','fft_lobe_rss','single_bin_peak'}))),error('GXTXT:Numeric:InvalidPolicy','unknown component convention');endif
  levels=amplitudes(:);if(strcmp(floor_policy,'realmin')),levels(levels<realmin)=realmin;endif
  out=struct('component_order',orders(:),'component_expected_frequency',expected(:), ...
    'component_frequency',detected(:),'component_frequency_error',detected(:)-expected(:), ...
    'component_amplitude',amplitudes(:),'component_level_db',20*log10(levels/reference), ...
    'component_percent',100*amplitudes(:)/reference,'fundamental_amplitude',reference, ...
    'component_method',method,'component_level_floor',floor_policy);
endfunction
