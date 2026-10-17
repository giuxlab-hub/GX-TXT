function [values,receipt]=gxtxt_coordinate_values_v1(context,variable_id,canonical_values,options,native_unit)
% Display-only projection through public DATASET_METADATA_API_v1 plans.
% Original arrays remain caller-owned. Identity preserves exact integer storage.
% Nonidentity output is float64; NaN/Inf gaps retain their positions.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<4),options=struct();endif
  if(!isnumeric(canonical_values)||!isreal(canonical_values)||islogical(canonical_values))
    error('GXTXT:Coordinates','Presentation requires a real numeric array');
  endif
  lifetime=gxtxt_presentation_scope_v1();
  source_unit=context.variables.(variable_id).source.unit;
  if(nargin<5),native_unit=source_unit;endif
  if(isfield(options,'source_unit_assumption')&&isempty(native_unit)),native_unit=options.source_unit_assumption;endif
  plan=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_affine_plan',{context,variable_id,native_unit,options});
  values=canonical_values;finite=isfinite(canonical_values);
  identity=plan.affine&&plan.scale==1&&plan.offset==0;
  if(!identity)
    values=double(canonical_values);
    if(plan.affine)
      values(finite)=values(finite)*plan.scale+plan.offset;
    else
      indices=find(finite);
      for start=1:4096:numel(indices)
        selected=indices(start:min(start+4095,numel(indices)));
        input=canonical_values(selected);
        inverse=isfield(options,'direction')&&strcmp(options.direction,'inverse');
        if(!inverse&&!strcmp(native_unit,source_unit))
          normalized=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_values',{context,variable_id,input,struct('mode','canonical','unit',native_unit,'direction','inverse')});
          input=normalized.values;
        endif
        converted=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_values',{context,variable_id,input,options});
        if(inverse&&!strcmp(native_unit,source_unit))
          converted=gxtxt_api_call('DATASET_METADATA_API_v1','coordinate_snapshot_values',{context,variable_id,converted.values,struct('mode','canonical','unit',native_unit)});
        endif
        values(selected)=converted.values;
      endfor
    endif
    if(any(!isfinite(values(finite))))
      error('GXTXT:Coordinates','Coordinate conversion overflowed a finite source value');
    endif
  endif
  receipt=plan;receipt.input_class=class(canonical_values);receipt.output_class=class(values);
  receipt.exact_identity=identity;receipt.source_values_modified=false;
  receipt.calibration_applied=strcmp(plan.coordinate_mode,'effective');
  receipt.finite_count=sum(finite(:));receipt.gap_count=numel(finite)-receipt.finite_count;
endfunction
