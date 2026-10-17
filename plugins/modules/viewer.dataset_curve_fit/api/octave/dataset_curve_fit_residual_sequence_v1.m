% SPDX-License-Identifier: GPL-3.0-or-later
% Data adaptation only: Numeric computes; CORE interprets the captured facts.
function out=dataset_curve_fit_residual_sequence_v1(family,action,rows_data,source_rows,unused,settings)
  if(!strcmp(family,'residual_sequence')||!strcmp(action,'describe')||!isa(rows_data,'double')||!isreal(rows_data)||rows(rows_data)<4||columns(rows_data)<2||columns(rows_data)>1000000||!isa(source_rows,'uint64')||numel(source_rows)!=columns(rows_data))
    error('GXTXT:Fitter:Sequence','Owned residuals and exact source rows have inconsistent shapes');
  endif
  options=struct('ordering','ascending','max_lag',settings.max_lag,'nonfinite',settings.nonfinite);
  if(strcmp(settings.order,'retained')),keys=source_rows(:);options.ordering='input';
  elseif(strcmp(settings.order,'source_rows')),keys=source_rows(:);
  elseif(strcmp(settings.order,'predicted')),keys=rows_data(3,:)';
  elseif(strcmp(settings.order,'predictor')),keys=rows_data(settings.predictor_column,:)';
  else error('GXTXT:Fitter:Sequence','Unknown explicit residual sequence order');endif
  out=gxtxt_numeric_v1('residual_sequence',rows_data(4,:)',keys,options);
endfunction
