% math.numeric private worker implementation for the public Tcl binding.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_numeric_worker_main(args)
  request=arg_value(args,'--request','');response=arg_value(args,'--response','');
  if(isempty(request)||isempty(response)),fprintf(2,'math.numeric worker requires --request and --response\n');exit(2);endif
  try
    cfg=gxtxt_ini_read(request);op=lower(strtrim(gxtxt_ini_get(cfg,'request.operation','')));opts=read_options(cfg);S=read_selection(cfg);if(S.enabled),opts.selection=S;endif
    switch(op)
      case 'array_unary',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'),opts);
      case 'array_binary',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'),read_array(cfg,'b'),opts);
      case 'array_compare',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'),read_array(cfg,'b'),opts);
      case 'array_mask'
        if(has_data(cfg,'b')),out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'),read_array(cfg,'b'));else out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'));endif
      case 'array_select',out=gxtxt_numeric_v1(op,read_array(cfg,'a'),read_array(cfg,'mask'));
      case 'array_where',out=gxtxt_numeric_v1(op,read_array(cfg,'mask'),read_array(cfg,'a'),read_array(cfg,'b'));
      case 'array_reduce',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'a'),opts);
      case 'complex_unary',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'real_part'),read_array(cfg,'imaginary_part'),opts);
      case 'complex_binary',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_array(cfg,'real_a'),read_array(cfg,'imaginary_a'),read_array(cfg,'real_b'),read_array(cfg,'imaginary_b'),opts);
      case 'unwrap',out=gxtxt_numeric_v1(op,read_array(cfg,'phase'),opts);
      case 'dataset_array_unary',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'variable_id'),read_string(cfg,'name'),opts);
      case 'dataset_array_binary',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'left_variable_id'),read_string(cfg,'right_variable_id'),read_string(cfg,'name'),opts);
      case 'dataset_array_scalar',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'variable_id'),read_scalar(cfg,'scalar'),read_string(cfg,'name'),opts);
      case 'interpolate',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),read_vector(cfg,'xq'),opts);
      case 'resample',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),read_vector(cfg,'xq'),opts);
      case 'resample_uniform',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),read_scalar(cfg,'step'),opts);
      case 'spline_create',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'spline_evaluate',out=gxtxt_numeric_v1(op,read_spline_model(cfg),read_vector(cfg,'xq'),opts);
      case 'spline_integral',out=gxtxt_numeric_v1(op,read_spline_model(cfg),read_scalar(cfg,'a'),read_scalar(cfg,'b'),opts);
      case 'integrate',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'cumulative_integrate',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'differentiate',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'grid_info',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),opts);
      case 'validate_monotonic',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),opts);
      case 'uniform_grid',out=gxtxt_numeric_v1(op,read_scalar(cfg,'start'),read_scalar(cfg,'stop'),read_scalar(cfg,'spacing'),opts);
      case 'common_range',out=gxtxt_numeric_v1(op,read_vector(cfg,'x1'),read_vector(cfg,'x2'),opts);
      case 'statistics',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'rank',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'covariance',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'correlation',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'mad',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'histogram'
        edges=[];if(has_data(cfg,'edges')),edges=read_vector(cfg,'edges');endif
        out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),edges,opts);
      case 'ecdf',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'normal_cdf',out=gxtxt_numeric_v1(op,read_array(cfg,'x'),read_array(cfg,'mu'),read_array(cfg,'sigma'),opts);
      case 'student_t_cdf',out=gxtxt_numeric_v1(op,read_array(cfg,'t'),read_array(cfg,'df'),opts);
      case 'f_cdf',out=gxtxt_numeric_v1(op,read_array(cfg,'f'),read_array(cfg,'df1'),read_array(cfg,'df2'),opts);
      case 'matrix_svd',out=gxtxt_numeric_v1(op,read_matrix(cfg,'matrix'),opts);
      case 'linear_matrix'
        a=complex(read_matrix(cfg,'a_real'),read_matrix(cfg,'a_imaginary'));b=[];
        if(has_data(cfg,'b_real')),b=complex(read_matrix(cfg,'b_real'),read_matrix(cfg,'b_imaginary'));endif
        out=gxtxt_numeric_v1(op,read_string(cfg,'action'),a,b,opts);
      case 'resample_indices',out=gxtxt_numeric_v1(op,read_scalar(cfg,'population_size'),read_scalar(cfg,'draw_count'),read_scalar(cfg,'replicates'),read_scalar(cfg,'seed'),opts);
      case 'residual_metrics',out=gxtxt_numeric_v1(op,read_vector(cfg,'observed'),read_vector(cfg,'predicted'),opts);
      case 'quantiles',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),read_vector(cfg,'probabilities'),opts);
      case 'weighted_quantiles',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),read_vector(cfg,'weights'),read_vector(cfg,'probabilities'),opts);
      case 'cumulative_sum',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'vector_normalize',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'vector_similarity',out=gxtxt_numeric_v1(op,read_vector(cfg,'a'),read_vector(cfg,'b'),opts);
      case 'weighted_statistics',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),read_vector(cfg,'weights'),opts);
      case 'least_squares'
        w=[];if(has_data(cfg,'weights')),w=read_vector(cfg,'weights');endif;out=gxtxt_numeric_v1(op,read_matrix(cfg,'design'),read_vector(cfg,'response'),w,opts);
      case 'linear_regression'
        w=[];if(has_data(cfg,'weights')),w=read_vector(cfg,'weights');endif;out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),w,opts);
      case 'polynomial_fit'
        w=[];if(has_data(cfg,'weights')),w=read_vector(cfg,'weights');endif;out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),read_scalar(cfg,'degree'),w,opts);
      case 'polynomial_evaluate',out=gxtxt_numeric_v1(op,read_polynomial_model(cfg),read_vector(cfg,'xq'),opts);
      case 'smooth',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'digital_filter',out=gxtxt_numeric_v1(op,read_vector(cfg,'y'),read_vector(cfg,'b'),read_vector(cfg,'a'),opts);
      case 'find_peaks',out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),opts);
      case 'baseline'
        ax=[];ay=[];if(has_data(cfg,'anchor_x')),ax=read_vector(cfg,'anchor_x');endif;if(has_data(cfg,'anchor_y')),ay=read_vector(cfg,'anchor_y');endif;out=gxtxt_numeric_v1(op,read_vector(cfg,'x'),read_vector(cfg,'y'),ax,ay,opts);
      case 'propagate_uncertainty'
        kind=lower(strtrim(gxtxt_ini_get(cfg,'options.input_kind','standard_uncertainty')));if(strcmp(kind,'covariance')),u=read_matrix(cfg,'uncertainty');else u=read_vector(cfg,'uncertainty');endif;out=gxtxt_numeric_v1(op,read_matrix(cfg,'jacobian'),u,opts);
      case 'fft',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'ifft',out=gxtxt_numeric_v1(op,read_vector(cfg,'real_values'),read_vector(cfg,'imaginary_values'),opts);
      case 'analytic_signal',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'frequency_grid',out=gxtxt_numeric_v1(op,read_scalar(cfg,'sample_rate'),read_scalar(cfg,'nfft'),opts);
      case 'one_sided',out=gxtxt_numeric_v1(op,read_vector(cfg,'real_values'),read_vector(cfg,'imaginary_values'),opts);
      case 'detrend',out=gxtxt_numeric_v1(op,read_vector(cfg,'values'),opts);
      case 'window',out=gxtxt_numeric_v1(op,read_string(cfg,'name'),read_scalar(cfg,'length'),opts);
      case 'dataset_integrate',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      case 'dataset_cumulative_integrate',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      case 'dataset_differentiate',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      case 'dataset_interpolate',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),read_vector(cfg,'xq'),opts);
      case 'dataset_resample',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),read_vector(cfg,'xq'),opts);
      case 'dataset_resample_uniform',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),read_scalar(cfg,'step'),opts);
      case 'dataset_statistics',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'variable_id'),opts);
      case 'dataset_reduce_summary',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'variable_id'),opts);
      case 'dataset_weighted_statistics',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'variable_id'),read_string(cfg,'weight_variable_id'),opts);
      case 'dataset_grid_info',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),opts);
      case 'dataset_polynomial_fit',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),read_scalar(cfg,'degree'),opts);
      case 'dataset_smooth',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      case 'dataset_find_peaks',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      case 'dataset_baseline',out=gxtxt_numeric_v1(op,read_string(cfg,'session'),read_string(cfg,'dataset_id'),read_string(cfg,'x_variable_id'),read_string(cfg,'y_variable_id'),opts);
      otherwise,error('GXTXT:Numeric','unsupported worker operation: %s',op);
    endswitch
    write_result(response,out);
  catch err
    try write_error(response,err);catch;end_try_catch
    fprintf(2,'math.numeric: %s\n',err.message);exit(1);
  end_try_catch
endfunction

function v=arg_value(args,key,default),v=default;for i=1:numel(args)-1,if(strcmp(args{i},key)),v=args{i+1};return;endif,endfor,endfunction
function tf=has_data(cfg,name),tf=gxtxt_ini_has(cfg,['data.' name '.kind']);endfunction
function s=read_string(cfg,name),s=gxtxt_ini_get(cfg,['data.' name '.value'],'');endfunction
function v=read_vector(cfg,name)
  kind=lower(strtrim(gxtxt_ini_get(cfg,['data.' name '.kind'],'')));if(!strcmp(kind,'vector')),error('GXTXT:Numeric','request data %s is not a vector',name);endif
  raw=strtrim(gxtxt_ini_get(cfg,['data.' name '.value'],''));if(isempty(raw)),v=zeros(0,1);return;endif;toks=strsplit(raw,';');v=zeros(numel(toks),1);for i=1:numel(toks),v(i)=parse_number(toks{i},['data.' name]);endfor
endfunction
function v=read_scalar(cfg,name),v=read_vector(cfg,name);if(numel(v)!=1),error('GXTXT:Numeric','request data %s must be one scalar',name);endif;v=v(1);endfunction
function v=read_array(cfg,name)
  kind=lower(strtrim(gxtxt_ini_get(cfg,['data.' name '.kind'],'')));
  switch(kind)
    case 'scalar',v=parse_number(gxtxt_ini_get(cfg,['data.' name '.value'],''),['data.' name]);
    case 'vector',v=read_vector(cfg,name);
    case 'matrix',v=read_matrix(cfg,name);
    otherwise,error('GXTXT:Numeric','request data %s is not a scalar, vector or matrix',name);
  endswitch
endfunction
function A=read_matrix(cfg,name)
  kind=lower(strtrim(gxtxt_ini_get(cfg,['data.' name '.kind'],'')));if(!strcmp(kind,'matrix')),error('GXTXT:Numeric','request data %s is not a matrix',name);endif
  nr=str2double(gxtxt_ini_get(cfg,['data.' name '.rows'],'NaN'));nc=str2double(gxtxt_ini_get(cfg,['data.' name '.cols'],'NaN'));if(!isfinite(nr)||!isfinite(nc)||nr<1||nc<1||nr!=fix(nr)||nc!=fix(nc)),error('GXTXT:Numeric','invalid matrix shape for %s',name);endif
  raw=strtrim(gxtxt_ini_get(cfg,['data.' name '.value'],''));toks=strsplit(raw,';');if(numel(toks)!=nr*nc),error('GXTXT:Numeric','matrix %s value count does not match shape',name);endif;flat=zeros(1,numel(toks));for i=1:numel(toks),flat(i)=parse_number(toks{i},['data.' name]);endfor;A=reshape(flat,nc,nr).';
endfunction
function v=parse_number(s,where)
  q=lower(strtrim(s));if(any(strcmp(q,{'nan','+nan','-nan'}))),v=NaN;return;endif;if(any(strcmp(q,{'inf','+inf','infinity','+infinity'}))),v=Inf;return;endif;if(any(strcmp(q,{'-inf','-infinity'}))),v=-Inf;return;endif;v=str2double(q);if(isnan(v)),error('GXTXT:Numeric','invalid numeric value in %s: %s',where,s);endif
endfunction
function opts=read_options(cfg)
  opts=struct();names={'nonfinite','axis','probability','ties','scale','bin_mode','bin_count','bin_width','period','replace','scalar_first','method','extrapolation','start','stop','rtol','atol','chunk_rows','mode','rank_policy','rank_tolerance','condition_limit','exponent','weight_semantics','has_intercept','intercept','center_scale','window','degree','min_height','min_prominence','min_distance','distance_mode','relative_height','value','estimator','anchor_method','input_kind','weight_variable_id','max_iterations','tolerance','function_tolerance','derivative_order','nfft','normalization','representation','ordering','scaling','sampling'};
  for i=1:numel(names),key=['options.' names{i}];if(gxtxt_ini_has(cfg,key)),opts.(names{i})=gxtxt_ini_get(cfg,key,'');endif,endfor
endfunction
function S=read_selection(cfg)
  S=struct('enabled',parse_bool(gxtxt_ini_get(cfg,'selection.enabled','0')));if(!S.enabled),return;endif;text_fields={'id','type','source_dataset_id','x_variable_id','x_unit','x_coordinate_space','y_variable_id','y_unit'};for i=1:numel(text_fields),k=text_fields{i};S.(k)=strtrim(gxtxt_ini_get(cfg,['selection.' k],''));endfor;numeric_fields={'x_min','x_max','x_binding_count','y_min','y_max'};for i=1:numel(numeric_fields),k=numeric_fields{i};raw=strtrim(gxtxt_ini_get(cfg,['selection.' k],''));if(isempty(raw)),S.(k)=NaN;else S.(k)=parse_number(raw,['selection.' k]);endif,endfor
endfunction
function b=parse_bool(s),b=any(strcmp(lower(strtrim(s)),{'1','true','yes','on'}));endfunction
function model=read_spline_model(cfg)
  model=struct('model_type','piecewise_polynomial','method',read_string(cfg,'model_method'),'breaks',read_vector(cfg,'model_breaks'),'coefficients',read_matrix(cfg,'model_coefficients'),'pieces',read_scalar(cfg,'model_pieces'),'order',read_scalar(cfg,'model_order'),'dimension',read_scalar(cfg,'model_dimension'));
endfunction
function model=read_polynomial_model(cfg)
  model=struct();model.coefficients=read_vector(cfg,'model_coefficients');if(has_data(cfg,'model_scaled_coefficients')),model.scaled_coefficients=read_vector(cfg,'model_scaled_coefficients');model.x_center=read_scalar(cfg,'model_x_center');model.x_scale=read_scalar(cfg,'model_x_scale');endif
endfunction
function write_result(path,S)
  if(!isstruct(S)||numel(S)!=1),error('GXTXT:Numeric','worker result must be a scalar struct');endif;f=fopen(path,'w');if(f<0),error('GXTXT:Numeric','cannot create response file');endif
  unwind_protect
    names=fieldnames(S);fprintf(f,'[result]\nok=1\nfields=%s\n\n',strjoin(names,';'));
    for i=1:numel(names)
      name=names{i};value=S.(name);fprintf(f,'[result.%s]\n',name);
      if(ischar(value)),fprintf(f,'type=string\nvalue=%s\n\n',single_line(value));
      elseif(islogical(value)&&isscalar(value)),fprintf(f,'type=boolean\nvalue=%d\n\n',logical(value));
      elseif((isnumeric(value)||islogical(value))&&isscalar(value)),fprintf(f,'type=number\nvalue=%s\n\n',number_text(double(value)));
      elseif((isnumeric(value)||islogical(value))&&isempty(value)),fprintf(f,'type=vector\nvalue=\n\n');
      elseif((isnumeric(value)||islogical(value))&&isvector(value)),fprintf(f,'type=vector\nvalue=%s\n\n',numeric_join(double(value(:))));
      elseif((isnumeric(value)||islogical(value))&&ismatrix(value)),flat=reshape(double(value).',1,[]);fprintf(f,'type=matrix\nrows=%d\ncols=%d\nvalue=%s\n\n',rows(value),columns(value),numeric_join(flat));
      else error('GXTXT:Numeric','result field %s has unsupported transport type',name);endif
    endfor
  unwind_protect_cleanup
    fclose(f);
  end_unwind_protect
endfunction
function write_error(path,err),f=fopen(path,'w');if(f<0),return;endif;id='';if(isfield(err,'identifier')),id=err.identifier;endif;fprintf(f,'[result]\nok=0\nfields=\n\n[error]\nidentifier=%s\nmessage=%s\n',single_line(id),single_line(err.message));fclose(f);endfunction
function s=numeric_join(v),if(isempty(v)),s='';return;endif;parts=cell(1,numel(v));for i=1:numel(v),parts{i}=number_text(v(i));endfor;s=strjoin(parts,';');endfunction
function s=number_text(v),if(isnan(v)),s='NaN';elseif(isinf(v)&&v>0),s='Inf';elseif(isinf(v)),s='-Inf';else s=sprintf('%.17g',v);endif,endfunction
function s=single_line(s),s=strrep(s,sprintf('\r'),' ');s=strrep(s,sprintf('\n'),' ');endfunction
