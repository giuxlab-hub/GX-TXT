% Retained Fitter data adapter; Numeric owns evaluation and CORE owns unit plans.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=dataset_curve_fit_query_v1(family,action,captured,query,bracket,options)
  if(nargin==1&&strcmp(family,'file'))
    addpath(getenv('GXDCF_CORE_OCTAVE_DIR'));addpath(getenv('GXDCF_NUMERIC_API_DIR'));
    request=gxtxt_scientific_result_read_v1(getenv('GXDCF_QUERY_REQUEST'));
    out=dataset_curve_fit_query_v1('retained_query',request.action,request.model,request.query,request.bracket,request.options);
    gxtxt_scientific_result_write_v1(getenv('GXDCF_QUERY_RESULT'),out);return;
  endif
  if(!strcmp(family,'retained_query')||!any(strcmp(action,{'query','inverse','geometry'}))),error('GXTXT:Fitter:Query','Unknown retained query action');endif
  if(strcmp(captured.restore,'saved_json_file'))
    fid=fopen(captured.model,'rb');if(fid<0),error('GXTXT:Fitter:Query','Cannot open the owned saved model copy');endif
    unwind_protect
      bytes=fread(fid,128*1024*1024+1,'*uint8');
    unwind_protect_cleanup,fclose(fid);end_unwind_protect
    if(numel(bytes)>128*1024*1024),error('GXTXT:Fitter:Query','Saved model exceeds128 MiB');endif
    model=gxtxt_numeric_v1('model_state_decode',bytes);clear bytes;
  elseif(strcmp(captured.restore,'saved_json')),model=captured.model;
  elseif(strcmp(captured.restore,'model')),model=captured.model;
  elseif(strcmp(captured.restore,'rational_model_restore')),model=gxtxt_numeric_v1('rational_model_restore',captured.state);
  else
    if(!any(strcmp(captured.restore,{'fit_formula_compose','fit_model_compose','fit_region_compose'}))),error('GXTXT:Fitter:Query','Unknown frozen model reconstruction');endif
    model=gxtxt_numeric_v1(captured.restore,captured.recipe);
    model.parameters=captured.parameters;
    model.source_sha256=captured.source_sha256;
    model.binding_sha256=captured.binding_sha256;
  endif
  if(strcmp(action,'geometry')),out=gxtxt_numeric_v1('model_geometry',model,options);return;endif
  scales=struct();
  for field={'derivative_scale','inverse_derivative_scale'}
    if(isfield(options,field{1})),scales.(field{1})=options.(field{1});options=rmfield(options,field{1});endif
  endfor
  if(strcmp(action,'query'))
    out=gxtxt_numeric_v1('model_query',model,query,options);
    out.interpreted_derivative=NaN(size(out.derivative));out.interpreted_inverse_derivative=NaN(size(out.inverse_derivative));
    mask=out.derivative_valid&isfinite(out.derivative);
    if(isfield(scales,'derivative_scale')&&any(mask))
      mapped=gxtxt_numeric_v1('array_binary','multiply',out.derivative(mask),scales.derivative_scale,struct());out.interpreted_derivative(mask)=mapped.values;
    endif
    mask=out.inverse_derivative_valid&isfinite(out.inverse_derivative);
    if(isfield(scales,'inverse_derivative_scale')&&any(mask))
      mapped=gxtxt_numeric_v1('array_binary','multiply',out.inverse_derivative(mask),scales.inverse_derivative_scale,struct());out.interpreted_inverse_derivative(mask)=mapped.values;
    endif
    out.interpreted_derivative_valid=out.derivative_valid&isfinite(out.interpreted_derivative);
    out.interpreted_inverse_derivative_valid=out.inverse_derivative_valid&isfinite(out.interpreted_inverse_derivative);
    out.interpreted_derivative(!out.interpreted_derivative_valid)=NaN;out.interpreted_inverse_derivative(!out.interpreted_inverse_derivative_valid)=NaN;
  else,out=gxtxt_numeric_v1('model_inverse',model,query,bracket,options);endif
endfunction
