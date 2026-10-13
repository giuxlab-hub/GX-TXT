% SPDX-License-Identifier: GPL-3.0-or-later
% Mark level transforms explicitly: old affine inverse metadata is not used.
function gxtxt_level_scale_metadata(ax,spec,axis)
  if(nargin<3),axis='y';endif
  if(!any(strcmp(axis,{'y','z'}))),error('GXTXT:LevelScale','Metadata axis must be y or z');endif
  if(isempty(ax)),return;endif
  if(strcmp(spec.scale,'linear')),transform='affine';else transform='level_scale_v1';endif
  setappdata(ax,['gxtxt_' axis '_transform'],transform);
  for f={'scale','quantity_kind','amplitude_basis','reference_value','reference_unit','zero_policy'}
    name=f{1};value=spec.(name);
    if(isnumeric(value)),if(isnan(value)),value='';else value=sprintf('%.17g',value);endif;endif
    setappdata(ax,['gxtxt_' axis '_level_' name],value);
  endfor
endfunction
