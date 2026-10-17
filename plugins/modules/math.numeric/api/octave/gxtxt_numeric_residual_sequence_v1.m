% SPDX-License-Identifier: GPL-3.0-or-later
% Numeric owns descriptive sequence calculations; CORE interprets their limits.
function out=gxtxt_numeric_residual_sequence_v1(residuals,keys,options)
  if(!isstruct(options)||numel(options)!=1),error('GXTXT:Numeric:Sequence','Explicit ordering options are required');endif
  unknown=setdiff(fieldnames(options),{'ordering','max_lag','nonfinite'});
  if(!isempty(unknown)),error('GXTXT:Numeric:Sequence','Unknown sequence option: %s',unknown{1});endif
  if(!isfield(options,'ordering')||!ischar(options.ordering)||!any(strcmp(options.ordering,{'input','ascending'})))
    error('GXTXT:Numeric:Sequence','Declare ordering=input or ascending explicitly');
  endif
  if(!(isa(residuals,'double')||isa(residuals,'single'))||!isreal(residuals)||!isvector(residuals)||numel(residuals)<2||numel(residuals)>1000000)
    error('GXTXT:Numeric:Sequence','Residuals require 2..1000000 real floating-point values');
  endif
  r=double(residuals(:));input_count=numel(r);
  generated=isempty(keys);
  if(generated)
    if(strcmp(options.ordering,'ascending')),error('GXTXT:Numeric:Sequence','Ascending order requires explicit keys');endif
    keys=uint64((1:input_count)');
  endif
  if(!isnumeric(keys)||!isreal(keys)||!isvector(keys)||numel(keys)!=input_count)
    error('GXTXT:Numeric:Sequence','Ordering keys must be a matching real numeric vector');
  endif
  keys=keys(:);input_residual_sha256=digest(r);input_order_sha256=digest(keys);
  policy='error';if(isfield(options,'nonfinite')),policy=options.nonfinite;endif
  if(!ischar(policy)||!any(strcmp(policy,{'error','omit'}))),error('GXTXT:Numeric:Sequence','nonfinite must be error or explicit omit');endif
  valid=isfinite(r)&isfinite(keys);omitted=sum(!valid);
  if(omitted&&strcmp(policy,'error')),error('GXTXT:Numeric:Sequence','Nonfinite residual/key pairs require explicit omission, which joins surviving rows');endif
  r=r(valid);keys=keys(valid);n=numel(r);
  if(n<2),error('GXTXT:Numeric:Sequence','Fewer than two finite residual/key pairs remain');endif
  ties=0;
  if(strcmp(options.ordering,'ascending'))
    [keys,index]=sort(keys,'ascend');r=r(index);ties=sum(keys(2:end)==keys(1:end-1));
  endif
  lag=min(10,n-1);if(isfield(options,'max_lag')),lag=options.max_lag;endif
  if(!isnumeric(lag)||!isreal(lag)||!isscalar(lag)||!isfinite(lag)||lag!=fix(lag)||lag<1||lag>min(64,n-1))
    error('GXTXT:Numeric:Sequence','max_lag must be an integer from1 to min(64,N-1)');
  endif
  scale=max(abs(r));v=zeros(n,1);if(scale>0),v=r/scale;endif
  centered=v-mean(v);centered_ss=sum(centered.^2);raw_ss=sum(v.^2);
  dw=NaN;if(raw_ss>0),dw=sum(diff(v).^2)/raw_ss;endif
  acf=NaN(lag,1);
  if(centered_ss>0)
    for k=1:lag,acf(k)=sum(centered(1:n-k).*centered(1+k:n))/centered_ss;endfor
  endif
  positive=sum(r>0);negative=sum(r<0);zero=sum(r==0);signs=sign(r(r!=0));count=numel(signs);
  runs=0;if(count>0),runs=1+sum(signs(2:end)!=signs(1:end-1));endif
  expected=NaN;variance=NaN;z=NaN;
  if(positive>0&&negative>0)
    expected=1+2*positive*negative/count;
    variance=2*positive*negative*(2*positive*negative-count)/(count^2*(count-1));
    if(variance>0),z=(runs-expected)/sqrt(variance);endif
  endif
  out=struct('numeric_api','NUMERIC_API_v1','operation','residual_sequence','schema','gxtxt.residual_sequence_numeric.v1',...
    'input_count',input_count,'n',n,'omitted_count',omitted,'nonfinite_policy',policy,...
    'ordering',options.ordering,'key_storage_class',class(keys),'generated_input_positions',generated,...
    'tie_count',ties,'tie_policy','stable_input_order','input_residual_sha256',input_residual_sha256,...
    'input_order_sha256',input_order_sha256,'ordered_residual_sha256',digest(r),'ordered_keys_sha256',digest(keys),...
    'positive_count',positive,'negative_count',negative,'zero_count',zero,'sign_zero_policy','exclude_exact_zeros_from_runs_only',...
    'runs',runs,'runs_expected',expected,'runs_variance',variance,'runs_z',z,...
    'runs_reference','uniform_permutation_conditional_on_nonzero_sign_counts',...
    'runs_continuity_correction','none','durbin_watson',dw,'durbin_watson_definition','successive_squared_differences_over_uncentered_squared_residuals',...
    'lags',(1:lag)','lag_pair_count',(n-(1:lag))','autocorrelation',acf,...
    'autocorrelation_definition','globally_centered_lag_product_over_complete_centered_sum_squares',...
    'constant_sequence',centered_ss==0,'zero_sequence',raw_ss==0,'work_units',n*lag,'p_values_computed',false);
endfunction
function value=digest(values)
  [unused,unused2,endian]=computer();if(endian=='B'),values=swapbytes(values);endif
  bytes=typecast(values(:),'uint8');value=hash('sha256',['gxtxt.residual_sequence.v1:' class(values) ':le:' char(bytes(:)')]);
endfunction
