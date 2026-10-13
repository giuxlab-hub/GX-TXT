% SPDX-License-Identifier: GPL-3.0-or-later
% Static validator/introspection for Scientific Analysis Definition API v1.
%
% report = gxtxt_analysis_validate_definition(path [, options])
% report.valid, report.errors, report.warnings, report.meta,
% report.required_bindings, report.optional_bindings, report.operations.
function report = gxtxt_analysis_validate_definition(path, options)
  if (nargin<2), options=struct(); endif
  errors={}; warnings={}; reqb={}; optb={}; ops_out=struct();
  report=struct('valid',false,'errors',{errors},'warnings',{warnings},'meta',struct(), ...
                'required_bindings',{reqb},'optional_bindings',{optb},'operations',ops_out);
  if (exist(path,'file')!=2)
    report.errors={sprintf('definition_not_found:%s',path)}; return;
  endif
  try
    d=gxtxt_ini_read(path);
  catch err
    report.errors={sprintf('ini_error:%s',err.message)}; return;
  end_try_catch
  api=strtrim(gxtxt_ini_get(d,'meta.api_version',''));
  id=strtrim(gxtxt_ini_get(d,'meta.id',''));
  report.meta=struct('api_version',api,'id',id,'kind',strtrim(gxtxt_ini_get(d,'meta.kind','')), ...
                     'version',strtrim(gxtxt_ini_get(d,'meta.version','')));
  if (!strcmp(api,'1')), errors{end+1}=sprintf('unsupported_api_version:%s',api); endif
  if (isempty(id)), errors{end+1}='missing_meta_id'; endif

  vars=parse_list(gxtxt_ini_get(d,'variables.ids',''));
  if (isempty(vars)), errors{end+1}='no_variables'; endif
  symbols=vars;
  for i=1:numel(vars)
    v=vars{i};
    if (!valid_id(v)), errors{end+1}=sprintf('invalid_variable_id:%s',v); continue; endif
    col=strtrim(gxtxt_ini_get(d,['variable.' v '.column'],''));
    bind=strtrim(gxtxt_ini_get(d,['variable.' v '.binding'],''));
    required=parse_bool(gxtxt_ini_get(d,['variable.' v '.required'],'1'),true);
    if (isempty(col) && isempty(bind)), col=v; endif
    if (!isempty(bind))
      if (!valid_id(bind)), errors{end+1}=sprintf('invalid_binding_id:%s',bind); endif
      if (required), reqb{end+1}=bind; else optb{end+1}=bind; endif %#ok<AGROW>
    endif
    if (!isempty(col) && !isempty(bind)), warnings{end+1}=sprintf('variable_%s_binding_takes_precedence_over_column',v); endif
  endfor

  params=parse_list(gxtxt_ini_get(d,'parameters.ids',''));
  for i=1:numel(params)
    p=params{i}; if(!valid_id(p)),errors{end+1}=sprintf('invalid_parameter_id:%s',p);endif
    if(any(strcmp(symbols,p))),errors{end+1}=sprintf('duplicate_symbol:%s',p);else symbols{end+1}=p;endif %#ok<AGROW>
    ptyp=lower(strtrim(gxtxt_ini_get(d,['parameter.' p '.type'],'numeric')));
    if(!any(strcmp(ptyp,{'numeric','double','number','bool','boolean','logical','string','text','choice'}))),errors{end+1}=sprintf('unsupported_parameter_type:%s:%s',p,ptyp);endif
    if(strcmp(ptyp,'choice'))
      choices=parse_list(gxtxt_ini_get(d,['parameter.' p '.choices'],''));if(isempty(choices)),errors{end+1}=sprintf('choice_parameter_missing_choices:%s',p);endif
      dv=strtrim(gxtxt_ini_get(d,['parameter.' p '.default'],''));if(!isempty(dv)&&!any(strcmp(choices,dv))),errors{end+1}=sprintf('choice_parameter_default_invalid:%s',p);endif
    endif
    if(any(strcmp(ptyp,{'numeric','double','number'})))
      lo=strtrim(gxtxt_ini_get(d,['parameter.' p '.min'],''));hi=strtrim(gxtxt_ini_get(d,['parameter.' p '.max'],''));dv=strtrim(gxtxt_ini_get(d,['parameter.' p '.default'],''));
      if(!isempty(lo)&&!isfinite(str2double(lo))),errors{end+1}=sprintf('parameter_min_invalid:%s',p);endif
      if(!isempty(hi)&&!isfinite(str2double(hi))),errors{end+1}=sprintf('parameter_max_invalid:%s',p);endif
      if(!isempty(lo)&&!isempty(hi)&&isfinite(str2double(lo))&&isfinite(str2double(hi))&&str2double(lo)>str2double(hi)),errors{end+1}=sprintf('parameter_bounds_invalid:%s',p);endif
      if(!isempty(dv)&&!isfinite(str2double(dv))),errors{end+1}=sprintf('parameter_default_invalid:%s',p);endif
    endif
  endfor

  ops=parse_list(gxtxt_ini_get(d,'operations.ids',''));
  if (numel(unique(ops))!=numel(ops)), errors{end+1}='duplicate_operation_id'; endif
  supported=gxtxt_analysis_operation_registry('all');
  outputs=cell(size(ops));
  for i=1:numel(ops)
    op=ops{i};
    if(!valid_id(op)),errors{end+1}=sprintf('invalid_operation_id:%s',op);continue;endif
    typ=lower(strtrim(gxtxt_ini_get(d,['operation.' op '.type'],'')));
    if(!any(strcmp(typ,supported))),errors{end+1}=sprintf('unsupported_operation:%s:%s',op,typ);endif
    out=strtrim(gxtxt_ini_get(d,['operation.' op '.output'],op)); outputs{i}=out;
    if(!valid_id(out)),errors{end+1}=sprintf('invalid_operation_output:%s:%s',op,out);endif
    if(any(strcmp(symbols,out))),errors{end+1}=sprintf('duplicate_symbol:%s',out);else symbols{end+1}=out;endif %#ok<AGROW>
    if(strcmp(typ,'crossing'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.x'],''))) || isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.y'],'')))),errors{end+1}=sprintf('crossing_missing_xy:%s',op);endif
      it=lower(strtrim(gxtxt_ini_get(d,['operation.' op '.interpolation'],'linear'))); if(!strcmp(it,'linear')),errors{end+1}=sprintf('crossing_interpolation_unsupported:%s:%s',op,it);endif
      ex=lower(strtrim(gxtxt_ini_get(d,['operation.' op '.extrapolation'],'forbid'))); if(!any(strcmp(ex,{'forbid','forbidden','false','0','none'}))),errors{end+1}=sprintf('crossing_extrapolation_unsupported:%s:%s',op,ex);endif
      t=strtrim(gxtxt_ini_get(d,['operation.' op '.target'],'')); tp=strtrim(gxtxt_ini_get(d,['operation.' op '.target_parameter'],''));
      if(isempty(t)&&isempty(tp)),errors{end+1}=sprintf('crossing_missing_target:%s',op);endif
    elseif(strcmp(typ,'mask'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.value'],'')))),errors{end+1}=sprintf('mask_missing_value:%s',op);endif
      t=strtrim(gxtxt_ini_get(d,['operation.' op '.target'],'')); ts=strtrim(gxtxt_ini_get(d,['operation.' op '.target_series'],''));
      if(isempty(t)&&isempty(ts)),errors{end+1}=sprintf('mask_missing_target:%s',op);endif
    elseif(any(strcmp(typ,{'align','resample'})))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.target_x'],gxtxt_ini_get(d,['operation.' op '.reference'],''))))),errors{end+1}=sprintf('%s_missing_target_x:%s',typ,op);endif
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.source_x'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.value'],'')))),errors{end+1}=sprintf('%s_missing_source:%s',typ,op);endif
    elseif(strcmp(typ,'join'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.left_key'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.right_key'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.value'],'')))),errors{end+1}=sprintf('join_missing_fields:%s',op);endif
    elseif(strcmp(typ,'interpolate'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.x'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.y'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.query'],'')))),errors{end+1}=sprintf('interpolate_missing_fields:%s',op);endif
    elseif(any(strcmp(typ,{'peak','extrema','integrate','area','derivative','slope','correlate','regress'})))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.x'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.y'],'')))),errors{end+1}=sprintf('%s_missing_xy:%s',typ,op);endif
    elseif(strcmp(typ,'window'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.value'],'')))),errors{end+1}=sprintf('window_missing_value:%s',op);endif
    elseif(strcmp(typ,'fit'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.x'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.y'],'')))),errors{end+1}=sprintf('fit_missing_xy:%s',op);endif
    elseif(strcmp(typ,'convert_unit'))
      if(isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.value'],'')))||isempty(strtrim(gxtxt_ini_get(d,['operation.' op '.to_unit'],gxtxt_ini_get(d,['operation.' op '.unit'],''))))),errors{end+1}=sprintf('convert_unit_missing_fields:%s',op);endif
    endif
  endfor
  report.operations=struct('ids',{ops},'outputs',{outputs});

  % Dependency integrity and cycle check.
  done={}; pending=ops;
  while(!isempty(pending))
    progressed=false;
    for i=1:numel(pending)
      op=pending{i}; deps=parse_list(gxtxt_ini_get(d,['operation.' op '.depends'],''));
      bad=setdiff(deps,ops);
      if(!isempty(bad)), errors{end+1}=sprintf('unknown_dependency:%s:%s',op,bad{1}); pending(i)=[]; progressed=true; break; endif
      if(all(cellfun(@(x)any(strcmp(done,x)),deps)))
        done{end+1}=op; pending(i)=[]; progressed=true; break; %#ok<AGROW>
      endif
    endfor
    if(!progressed),errors{end+1}='operation_dependency_cycle';break;endif
  endwhile

  exps=parse_list(gxtxt_ini_get(d,'exports.ids',''));
  for i=1:numel(exps)
    et=lower(strtrim(gxtxt_ini_get(d,['export.' exps{i} '.type'],'')));
    if(!any(strcmp(et,{'csv','summary','text_summary','feature_table'}))),errors{end+1}=sprintf('unsupported_export:%s:%s',exps{i},et);endif
  endfor
  plots=parse_list(gxtxt_ini_get(d,'plots.ids',''));
  for i=1:numel(plots)
    pt=lower(strtrim(gxtxt_ini_get(d,['plot.' plots{i} '.type'],'line')));
    if(!any(strcmp(pt,{'bar','line','scatter'}))),errors{end+1}=sprintf('unsupported_plot:%s:%s',plots{i},pt);endif
  endfor

  report.required_bindings=unique(reqb,'stable'); report.optional_bindings=unique(optb,'stable');
  report.errors=unique(errors,'stable'); report.warnings=unique(warnings,'stable'); report.valid=isempty(report.errors);
endfunction

function tf=valid_id(id), tf=!isempty(regexp(id,'^[A-Za-z][A-Za-z0-9_]*$','once')); endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif;endfunction
function b=parse_bool(s,def),q=lower(strtrim(s));if(isempty(q)),b=def;elseif(any(strcmp(q,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(q,{'0','false','no','off'}))),b=false;else b=def;endif;endfunction
