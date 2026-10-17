% Keep regional observation selection aligned with owned measurement/row inputs.
% SPDX-License-Identifier: GPL-3.0-or-later
function [training,model,receipt]=dataset_curve_fit_regions(training,orientation)
  if(!any(strcmp(orientation,{'y_of_x','x_of_y'}))),error('Joint regions require a physical functional orientation');endif
  captured=gxtxt_scientific_result_read_v1(getenv('GXDCF_REGION_RECIPE'));
  model=gxtxt_numeric_v1('fit_region_compose',captured.recipe);
  axis=1;if(strcmp(orientation,'x_of_y')),axis=2;endif
  selected=gxtxt_numeric_v1('fit_region_selection',model,training(:,axis));keep=selected.selected_mask;
  if(sum(keep)<2),error('Regional observation windows retain fewer than two training points');endif
  output=fileparts(getenv('GXDCF_REGION_RECIPE'));
  for variable={'GXDCF_TRAIN_ROW_IDS','GXDCF_MEASUREMENT_FILE','GXDCF_INDEPENDENT_MEASUREMENT_FILE'}
    name=variable{1};path=getenv(name);if(isempty(path)),continue;endif
    type='double';readtype='double';leaf=[name,'.bin'];
    if(strcmp(name,'GXDCF_TRAIN_ROW_IDS')),type='uint64';readtype='uint64=>uint64';leaf='region_training_rows.bin';endif
    fid=fopen(path,'rb');if(fid<0),error('Cannot open regional paired input');endif
    unwind_protect,values=fread(fid,Inf,readtype,0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
    if(numel(values)!=rows(training)),error('Regional selection lost exact paired input alignment');endif
    path=fullfile(output,leaf);fid=fopen(path,'wb');if(fid<0),error('Cannot create private regional paired input');endif
    unwind_protect
      written=fwrite(fid,values(keep),type,0,'ieee-le');if(written!=sum(keep)),error('Incomplete regional paired output');endif
    unwind_protect_cleanup,fclose(fid);end_unwind_protect
    setenv(name,path);
  endfor
  if(isempty(getenv('GXDCF_TRAIN_ROW_IDS'))),error('Regional fitting requires exact original training-row identities');endif
  training=training(keep,:);
  receipt=rmfield(selected,{'selected_mask','source_row_positions','region_indices','region_counts','breakpoint_values'});
  receipt.row_identity='original_source_uint64';
  receipt.selection_stage='before_measurement_missingness_or_zero_weight';
endfunction
