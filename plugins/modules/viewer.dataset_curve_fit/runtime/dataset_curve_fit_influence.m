% Data adapter for the existing Numeric fit; no diagnostic recomputation.
% SPDX-License-Identifier: GPL-3.0-or-later
function receipt=dataset_curve_fit_influence(result,response_shift)
  columns={'leverage','deleted_residual','loo_prediction','studentized_residual','cooks_distance','deletion_available','scaled_available'};
  input_positions=result.input_row_index;
  row_path=getenv('GXDCF_TRAIN_ROW_IDS');
  if(!strcmp(getenv('GXDCF_MEASUREMENT_KIND'),'none')),row_path=getenv('GXDCF_MEASUREMENT_FIT_ROWS_OUTPUT');endif
  fid=fopen(row_path,'rb');if(fid<0),error('Influence requires exact owned training row identities');endif
  unwind_protect,source_rows=fread(fid,Inf,'uint64=>uint64',0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
  if(numel(source_rows)!=result.input_count||numel(input_positions)!=result.n||any(input_positions<1)||any(input_positions>numel(source_rows))),error('Influence lost exact training row alignment');endif
  % Numerical translation inversion is delegated to the existing public owner.
  if(response_shift!=0)
    inverse=gxtxt_numeric_v1('array_binary','subtract',result.loo_prediction,response_shift,struct('nonfinite','ieee'));
    result.loo_prediction=inverse.values;
  endif
  values=zeros(result.n,numel(columns));
  for k=1:numel(columns),values(:,k)=result.(columns{k});endfor
  directory=fileparts(getenv('GXDCF_STATISTICS'));
  write_owned(fullfile(directory,'influence.bin'),values.','double');
  write_owned(fullfile(directory,'influence_input_rows.bin'),input_positions,'uint64');
  write_owned(fullfile(directory,'influence_source_rows.bin'),source_rows(input_positions),'uint64');
  receipt=rmfield(result,[columns,{'input_row_index'}]);
endfunction
function write_owned(path,values,type)
  fid=fopen(path,'wb');if(fid<0),error('Cannot create owned influence columns');endif
  unwind_protect
    count=fwrite(fid,values,type,0,'ieee-le');if(count!=numel(values)),error('Incomplete influence resource');endif
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
