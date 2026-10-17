% Capture the model's actual input ordering without repeating selection or fit.
% SPDX-License-Identifier: GPL-3.0-or-later
function policy=dataset_curve_fit_preprocessing(name,model,measurement)
  policy=gxtxt_numeric_v1('fit_input_policy',name,model);
  path=getenv('GXDCF_TRAIN_ROW_IDS');
  if(!isempty(fieldnames(measurement))),path=getenv('GXDCF_MEASUREMENT_FIT_ROWS_OUTPUT');endif
  if(isempty(path)),return;endif
  details=dir(path);
  if(numel(details)!=1||mod(details.bytes,8)!=0),error('Invalid retained preprocessing row file');endif
  policy.observation_count=details.bytes/8;policy.model_input_count=policy.observation_count;
  if(!isfield(model,'input_order')&&!policy.removed_terminal_endpoint)
    % Reuse the existing retained fit-row resource; do not copy or load a
    % potentially large integer array merely to restate its unchanged order.
    return;
  endif
  f=fopen(path,'rb');if(f<0),error('Cannot read retained preprocessing row identities');endif
  unwind_protect,identities=fread(f,Inf,'uint64=>uint64',0,'ieee-le');unwind_protect_cleanup,fclose(f);end_unwind_protect
  policy.observation_count=numel(identities);
  if(isfield(model,'input_order'))
    order=model.input_order(:);
    if(numel(order)!=numel(identities)||any(!isfinite(order))||any(order<1)||any(order>numel(identities))||any(order!=fix(order)))
      error('Model ordering lost its exact observation alignment');
    endif
    identities=identities(order);
  elseif(policy.removed_terminal_endpoint)
    identities=identities(1:end-1);
  endif
  policy.model_input_count=numel(identities);
  path=fullfile(fileparts(getenv('GXDCF_RESULT')),'model_input_rows.bin');
  f=fopen(path,'wb');if(f<0),error('Cannot retain model input order');endif
  unwind_protect
    if(fwrite(f,identities,'uint64',0,'ieee-le')!=numel(identities)),error('Incomplete model input row receipt');endif
  unwind_protect_cleanup,fclose(f);end_unwind_protect
endfunction
