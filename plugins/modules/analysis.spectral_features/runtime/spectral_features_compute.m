function R=spectral_features_compute(freq,value,input_semantics,exclude_dc,numeric_api)
% Compatibility entrypoint: one call to the public numerical authority.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<5||isempty(numeric_api)),error('analysis.spectral_features: NUMERIC_API_v1 is required');endif
  R=feval(numeric_api,'spectral_features',freq,value,struct('input_semantics',input_semantics,'exclude_dc',logical(exclude_dc)));
endfunction
