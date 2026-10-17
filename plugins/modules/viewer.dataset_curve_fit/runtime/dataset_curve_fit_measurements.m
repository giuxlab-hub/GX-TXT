% Explicit measurement data adaptation; all numerical conversion uses Numeric.
% SPDX-License-Identifier: GPL-3.0-or-later
function [training,weights,receipt,xy_sigma]=dataset_curve_fit_measurements(training)
  weights=[];receipt=struct();xy_sigma=[];kind=getenv('GXDCF_MEASUREMENT_KIND');
  if(isempty(kind)||strcmp(kind,'none')),return;endif
  if(strcmp(kind,'sigma_xy'))
    [training,xy_sigma,receipt]=xy_measurements(training);return;
  endif
  if(!any(strcmp(kind,{'sigma','relative_precision'}))),error('Invalid measurement role');endif
  raw=read_owned(getenv('GXDCF_MEASUREMENT_FILE'),'double');
  rows_input=read_owned(getenv('GXDCF_TRAIN_ROW_IDS'),'uint64=>uint64');
  if(numel(raw)!=rows(training)||numel(rows_input)!=rows(training)),error('Measurement values lost their exact training-row alignment');endif
  missing=!isfinite(raw);policy=getenv('GXDCF_MEASUREMENT_NONFINITE');
  if(!any(strcmp(policy,{'error','omit'}))),error('An explicit measurement missingness policy is required');endif
  if(any(missing)&&strcmp(policy,'error')),error('Measurement column contains missing or nonfinite values in the selected training rows; choose explicit omission or repair the source');endif
  if(strcmp(kind,'sigma'))
    if(any(raw(!missing)<=0)),error('Response sigma must be strictly positive');endif
  elseif(any(raw(!missing)<0)),error('Relative precision must be nonnegative');endif
  factor=str2double(getenv('GXDCF_MEASUREMENT_SCALE'));
  if(!isscalar(factor)||!isfinite(factor)||factor<=0),error('Invalid captured measurement unit scale');endif
  converted=gxtxt_numeric_v1('array_binary','multiply',raw,factor,struct('nonfinite','ieee'));value=converted.values;
  if(any(!isfinite(value(!missing)))),error('Converted measurement values are not finitely representable');endif
  if(strcmp(kind,'sigma')&&any(value(!missing)<=0)),error('Converted sigma is not positively representable');endif
  keep=!missing&value>0;used=find(keep);
  if(numel(used)<2),error('At least two positive-precision training observations are required');endif
  precision=NaN(size(value));
  if(strcmp(kind,'sigma'))
    inverse=gxtxt_numeric_v1('array_binary','power',value(keep),-2,struct());precision(keep)=inverse.values;semantics='inverse_variance';
  else
    precision(!missing)=value(!missing);semantics='relative';
  endif
  if(any(precision(keep)<=0)||any(!isfinite(precision(keep)))),error('Measurement precision is not finitely representable');endif
  weights=precision(keep);input_count=rows(training);training=training(keep,:);
  write_owned(getenv('GXDCF_MEASUREMENT_OUTPUT'),[raw,value,precision,double(keep)].','double');
  write_owned(getenv('GXDCF_MEASUREMENT_ROWS_OUTPUT'),rows_input,'uint64');
  write_owned(getenv('GXDCF_MEASUREMENT_FIT_ROWS_OUTPUT'),rows_input(keep),'uint64');
  receipt=struct('kind',kind,'nonfinite_policy',policy,'weight_semantics',semantics,'input_count',input_count,'fit_count',numel(used),'omitted_nonfinite_count',numel(find(missing)),'zero_precision_count',numel(find(!missing&value==0)),'scale_factor',factor,'row_identity','original_source_uint64');
endfunction
function [training,sigma,receipt]=xy_measurements(training)
  response=read_owned(getenv('GXDCF_MEASUREMENT_FILE'),'double');
  independent=read_owned(getenv('GXDCF_INDEPENDENT_MEASUREMENT_FILE'),'double');
  identities=read_owned(getenv('GXDCF_TRAIN_ROW_IDS'),'uint64=>uint64');n=rows(training);
  if(numel(response)!=n||numel(independent)!=n||numel(identities)!=n),error('Both-axis uncertainties lost their exact training-row alignment');endif
  policy=getenv('GXDCF_MEASUREMENT_NONFINITE');
  if(!any(strcmp(policy,{'error','omit'}))),error('An explicit measurement missingness policy is required');endif
  missing=!isfinite(response)|!isfinite(independent);
  if(any(missing)&&strcmp(policy,'error')),error('Both-axis sigma columns contain missing or nonfinite values; choose explicit omission or repair the source');endif
  if(any(response(isfinite(response))<=0)||any(independent(isfinite(independent))<=0)),error('Both-axis standard uncertainties must be strictly positive');endif
  scales=[str2double(getenv('GXDCF_INDEPENDENT_MEASUREMENT_SCALE')),str2double(getenv('GXDCF_MEASUREMENT_SCALE'))];
  if(any(!isfinite(scales))||any(scales<=0)),error('Invalid captured axis uncertainty scales');endif
  a=gxtxt_numeric_v1('array_binary','multiply',independent,scales(1),struct('nonfinite','ieee'));
  b=gxtxt_numeric_v1('array_binary','multiply',response,scales(2),struct('nonfinite','ieee'));
  keep=!missing;converted=[a.values,b.values];
  if(any(!isfinite(converted(keep,:))(:))||any(converted(keep,:)(:)<=0)),error('Converted axis sigma is not positively representable');endif
  if(sum(keep)<2),error('At least two observation pairs with positive sigma are required');endif
  sigma=converted(keep,:);training=training(keep,:);
  write_owned(getenv('GXDCF_MEASUREMENT_OUTPUT'),[independent,a.values,response,b.values,double(keep)].','double');
  write_owned(getenv('GXDCF_MEASUREMENT_ROWS_OUTPUT'),identities,'uint64');
  write_owned(getenv('GXDCF_MEASUREMENT_FIT_ROWS_OUTPUT'),identities(keep),'uint64');
  receipt=struct('kind','sigma_xy','nonfinite_policy',policy,'weight_semantics','inverse_variance','input_count',n,'fit_count',sum(keep),'omitted_nonfinite_count',sum(missing),'zero_precision_count',0,'scale_factor',scales(2),'independent_scale_factor',scales(1),'row_identity','original_source_uint64');
endfunction
function values=read_owned(path,type)
  fid=fopen(path,'rb');if(fid<0),error('Cannot open owned measurement input');endif
  unwind_protect,values=fread(fid,Inf,type,0,'ieee-le');unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
function write_owned(path,values,type)
  fid=fopen(path,'wb');if(fid<0),error('Cannot create owned measurement output');endif
  unwind_protect
    count=fwrite(fid,values,type,0,'ieee-le');if(count!=numel(values)),error('Incomplete owned measurement output');endif
  unwind_protect_cleanup,fclose(fid);end_unwind_protect
endfunction
