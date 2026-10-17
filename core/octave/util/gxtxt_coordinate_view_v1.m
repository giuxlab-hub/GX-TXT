function [display_range,receipt]=gxtxt_coordinate_view_v1(context,variable_id,reference_display_range,display_unit)
% Apply captured Dataset magnification once to a newly fitted displayed range.
% Numerical calibration is deliberately excluded from viewport policy.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),display_unit='display';endif
  if(!isnumeric(reference_display_range)||!isreal(reference_display_range)||numel(reference_display_range)!=2||...
     any(!isfinite(reference_display_range(:)))||reference_display_range(1)>=reference_display_range(2))
    error('GXTXT:Coordinates','Viewport requires two increasing finite displayed endpoints');
  endif
  lifetime=gxtxt_presentation_scope_v1();
  options=struct('mode','canonical','unit',display_unit,'direction','inverse');
  source=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_values',{context,variable_id,reference_display_range,options});
  receipt=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_view_range',{context,variable_id,sort(source.values(:))});
  display_range=reference_display_range;
  if(receipt.view_factor!=1)
    options.direction='forward';
    shown=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_values',{context,variable_id,receipt.canonical_range,options});
    display_range=reshape(sort(shown.values(:)),size(reference_display_range));
    if(any(!isfinite(display_range))||display_range(1)>=display_range(2))
      error('GXTXT:Coordinates','Magnification collapses the displayed viewport');
    endif
  endif
  receipt.reference_display_range=reference_display_range;receipt.display_range=display_range;
  receipt.display_unit=display_unit;receipt.calibration_applied=false;receipt.source_values_modified=false;
endfunction
