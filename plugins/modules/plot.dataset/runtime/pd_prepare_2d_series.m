function S=pd_prepare_2d_series(session,dataset_id,xid,yid,requested,target,threshold,chunk_rows,stage_tag,x_window,row_filters)
% Dataset-native X/Y Graph Series preparation.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(nargin<9),stage_tag='series';endif
  if(nargin<10),x_window=struct('enabled',false);endif
  if(nargin<11),row_filters={};endif
  S=pd_prepare_2d_stream(session,dataset_id,xid,yid,{},requested,target,threshold,chunk_rows,stage_tag,x_window,row_filters);
endfunction
