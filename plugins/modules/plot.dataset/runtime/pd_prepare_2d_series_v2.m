function S=pd_prepare_2d_series_v2(session,dataset_id,xid,yid,aux_ids,requested,target,threshold,chunk_rows,stage_tag,x_window,row_filters,optional_ids)
% Dataset-native Graph Series preparation with PlotSpec auxiliary variables.
% Auxiliary values are carried from the exact selected source rows; no
% interpolation, resampling or canonical-data materialization is introduced.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<10),stage_tag='series_v2';endif
  if(nargin<11),x_window=struct('enabled',false);endif
  if(nargin<12),row_filters={};endif
  if(nargin<13),optional_ids={};endif
  S=pd_prepare_2d_stream(session,dataset_id,xid,yid,aux_ids,requested,target,threshold,chunk_rows,stage_tag,x_window,row_filters,optional_ids);
endfunction
