% Reversible additive mapping. No solver, scaling, clipping or data omission.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_positive_translation_v1(values,options)
  if(nargin<2),options=struct();endif
  if(!isnumeric(values)||!isreal(values)||isempty(values)||any(!isfinite(values(:))))
    error('GXTXT:Numeric','Translation requires complete finite real values');
  endif
  mode='auto';if(isfield(options,'mode')),mode=options.mode;endif
  lower=min(values(:));upper=max(values(:));delta=0;margin=0;
  if(strcmp(mode,'auto'))
    if(lower<=0)
      scale=max(abs(values(:)));margin=max(realmin,32*eps(scale));
      delta=-lower+margin;
    endif
  elseif(strcmp(mode,'manual'))
    if(!isfield(options,'delta')||!isscalar(options.delta)||!isreal(options.delta)||!isfinite(options.delta))
      error('GXTXT:Numeric','Manual translation requires one finite constant');
    endif
    delta=options.delta;
  elseif(!strcmp(mode,'off'))
    error('GXTXT:Numeric','Translation mode must be auto, manual or off');
  endif
  mapped=gxtxt_numeric_v1('array_binary','add',values,delta,struct());
  if(!isfinite(delta)||any(!isfinite(mapped.values(:)))||(strcmp(mode,'auto')&&any(mapped.values(:)<=0)))
    error('GXTXT:Numeric','Positive translation overflows or cannot resolve a strictly positive margin');
  endif
  out=struct('values',mapped.values,'mode',mode,'delta',delta,'margin',margin,...
    'original_bounds',[lower,upper],'transformed_bounds',[min(mapped.values(:)),max(mapped.values(:))],...
    'algorithm','additive_positive_v1','forward','fit=original+delta','inverse','physical=fit-delta');
endfunction
