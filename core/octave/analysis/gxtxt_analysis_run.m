% SPDX-License-Identifier: GPL-3.0-or-later
% Scientific Analysis Definition API v1 generic executor.
%
% result = gxtxt_analysis_run(definition_path, source_map, output_dir, options)
%
% Public options (all optional):
%   runtime_cfg   parsed runtime.ini struct; enables variable binding=...
%   parameters    struct of Analysis Definition parameter overrides
%   render        true/false (default true)
%
% source_map is a struct whose fields are source-role IDs and values are CSV
% paths.  v0.8.4 keeps API v1 additive and supports non-row-aligned
% multi-source inputs through explicit align/join/resample operations, generic
% feature extraction, unit helpers, regression/model-fit bridges, and v0.8.3
% binding/status/mask/feature-table/grouped-plot capabilities.
function result = gxtxt_analysis_run(definition_path, source_map, output_dir, options)
  if (nargin<2 || isempty(source_map)), source_map=struct(); endif
  addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'units'));
  if (nargin<4), options=struct(); endif
  if (exist(definition_path,'file')!=2), error('GXTXT:Analysis','Definition not found: %s',definition_path); endif
  if (exist(output_dir,'dir')!=7), mkdir(output_dir); endif
  def=gxtxt_ini_read(definition_path);
  api=strtrim(gxtxt_ini_get(def,'meta.api_version',''));
  if (!strcmp(api,'1')), error('GXTXT:Analysis','Unsupported Scientific Analysis Definition API version: %s',api); endif
  defid=strtrim(gxtxt_ini_get(def,'meta.id',''));
  if (isempty(defid)), error('GXTXT:Analysis','Definition meta.id is required'); endif

  ctx=empty_context();
  runtime=struct(); if (isfield(options,'runtime_cfg')), runtime=options.runtime_cfg; endif
  if (isempty(fieldnames(source_map)) && !isempty(fieldnames(runtime)))
    source_map=gxtxt_analysis_source_map_from_runtime(runtime);
  endif

  source_roles=parse_list(gxtxt_ini_get(def,'sources.roles','primary'));
  if (isempty(source_roles)), source_roles={'primary'}; endif
  tables=struct();
  ctx.primary_source=source_roles{1};
  for i=1:numel(source_roles)
    role=source_roles{i}; validate_id(role,'source role');
    required=parse_bool(gxtxt_ini_get(def,['source.' role '.required'],'1'),true);
    sk=safe_field(role);
    path=''; if (isfield(source_map,sk)), path=source_map.(sk); endif
    if (isempty(strtrim(path)))
      if (required), error('GXTXT:Analysis','Required source is missing: %s',role); else continue; endif
    endif
    tables.(sk)=gxtxt_read_csv_table(path);
    ctx.source_rows.(sk)=tables.(sk).nrows;
    ctx.source_paths.(sk)=path;
    if(strcmp(role,ctx.primary_source)),ctx.row_count=tables.(sk).nrows;endif
  endfor
  if(ctx.row_count==0)
    fsrc=fieldnames(tables);if(!isempty(fsrc)),ctx.row_count=tables.(fsrc{1}).nrows;ctx.primary_source=fsrc{1};endif
  endif

  vars=parse_list(gxtxt_ini_get(def,'variables.ids',''));
  if (isempty(vars)), error('GXTXT:Analysis','Definition declares no variables'); endif
  for i=1:numel(vars)
    id=vars{i}; validate_id(id,'variable');
    src=strtrim(gxtxt_ini_get(def,['variable.' id '.source'],'primary')); validate_id(src,'source role');
    required=parse_bool(gxtxt_ini_get(def,['variable.' id '.required'],'1'),true);
    sk=safe_field(src);
    if (!isfield(tables,sk))
      if (required), error('GXTXT:Analysis','Variable %s refers to unavailable source %s',id,src); else ctx.optional_missing{end+1}=id; continue; endif
    endif
    binding=strtrim(gxtxt_ini_get(def,['variable.' id '.binding'],''));
    col=strtrim(gxtxt_ini_get(def,['variable.' id '.column'],''));
    if (!isempty(binding))
      validate_id(binding,'binding');
      resolved=strtrim(gxtxt_ini_get(runtime,['bindings.' binding],''));
      if (!isempty(resolved))
        % Standard Module API v1 multi-source bindings use source.variable.
        % Backward compatibility: an unqualified value means primary.variable.
        [resolved_src,resolved_col,is_qualified]=split_runtime_binding(resolved,source_map);
        if (is_qualified)
          src=resolved_src; sk=safe_field(src); col=resolved_col;
          if (!isfield(tables,sk))
            if (required), error('GXTXT:Analysis','Binding %s for variable %s refers to unavailable source %s',binding,id,src); else ctx.optional_missing{end+1}=id; continue; endif
          endif
        else
          src='primary'; sk=safe_field(src); col=resolved_col;
          if (!isfield(tables,sk))
            if (required), error('GXTXT:Analysis','Legacy unqualified binding %s for variable %s requires source primary',binding,id); else ctx.optional_missing{end+1}=id; continue; endif
          endif
        endif
      endif
      if (isempty(resolved) && isempty(col))
        if (required), error('GXTXT:Analysis','Required binding %s for variable %s is unresolved',binding,id); else ctx.optional_missing{end+1}=id; continue; endif
      endif
    endif
    if (isempty(col)), col=id; endif
    if (!any(strcmp(tables.(sk).names,col)))
      if (required), error('GXTXT:Analysis','Column not found for variable %s: %s',id,col); else ctx.optional_missing{end+1}=id; continue; endif
    endif
    typ=lower(strtrim(gxtxt_ini_get(def,['variable.' id '.type'],'auto')));
    v=gxtxt_table_column(tables.(sk),col,typ);
    rolemeta=strtrim(gxtxt_ini_get(def,['variable.' id '.role'],''));
    unit=strtrim(gxtxt_ini_get(def,['variable.' id '.unit'],''));
    % v0.9.1 additive metadata bridge: explicit Analysis Definition metadata
    % remains authoritative; blank role/unit inherit from the Dataset Registry
    % metadata delivered through the Analysis Source Map runtime.
    if(isempty(rolemeta) || isempty(unit))
      [src_unit,src_role]=gxtxt_analysis_source_variable_meta(runtime,src,col);
      if(isempty(unit)),unit=src_unit;endif
      if(isempty(rolemeta)),rolemeta=src_role;endif
    endif
    ctx=set_series(ctx,id,v,series_type(v),src,rolemeta,unit,valid_status(numel(v)),blank_reason(numel(v)));
    ctx.bindings.(id)=struct('source',src,'column',col,'binding',binding,'required',required);
  endfor

  % Declarative parameters are scalar symbols available to expression and
  % operation target_parameter= settings.  They do not change row_count.
  param_ids=parse_list(gxtxt_ini_get(def,'parameters.ids',''));
  for i=1:numel(param_ids)
    id=param_ids{i}; validate_id(id,'parameter');
    if (isfield(ctx.series,id)), error('GXTXT:Analysis','Parameter/series ID collision: %s',id); endif
    required=parse_bool(gxtxt_ini_get(def,['parameter.' id '.required'],'0'),false);
    typ=lower(strtrim(gxtxt_ini_get(def,['parameter.' id '.type'],'numeric')));
    raw=parameter_override(options,runtime,id,gxtxt_ini_get(def,['parameter.' id '.default'],''));
    if (isempty(strtrim(raw)) && required), error('GXTXT:Analysis','Required analysis parameter is missing: %s',id); endif
    if (isempty(strtrim(raw)) && !required), continue; endif
    v=parse_parameter(raw,typ,id);
    validate_parameter_value(def,id,typ,v);
    ctx.parameters.(id)=v;
    ctx=set_series(ctx,id,v,series_type(v),'parameter','parameter',strtrim(gxtxt_ini_get(def,['parameter.' id '.unit'],'')),{'valid'},{''});
  endfor

  ops=parse_list(gxtxt_ini_get(def,'operations.ids',''));
  order=topological_order(def,ops);
  op_output=struct();
  for i=1:numel(ops)
    oid=ops{i}; out=strtrim(gxtxt_ini_get(def,['operation.' oid '.output'],oid)); validate_id(out,'operation output'); op_output.(oid)=out;
  endfor

  for oi=1:numel(order)
    id=order{oi}; typ=lower(strtrim(gxtxt_ini_get(def,['operation.' id '.type'],'')));
    output=op_output.(id);
    deps=parse_list(gxtxt_ini_get(def,['operation.' id '.depends'],''));
    [rolemeta,unit]=operation_meta(def,id);
    if(!gxtxt_analysis_operation_registry('has',typ)),error('GXTXT:Analysis','Unsupported operation type %s in %s',typ,id);endif
    switch typ
      case 'expression'
        expr=gxtxt_ini_get(def,['operation.' id '.expression'],'');
        strict_units=parse_bool(gxtxt_ini_get(def,['operation.' id '.strict_units'],'0'),false);
        if(strict_units)
          [v,inferred_unit]=gxtxt_analysis_expression_strict_units(expr,ctx.series,ctx.units,unit);
          if(isempty(unit)),unit=inferred_unit;endif
        else
          v=gxtxt_analysis_op_expression(expr,ctx.series);
        endif
        require_row_compatible(v,ctx,'expression',id);
        [st,rs,blocked]=dependency_status(ctx,deps,op_output,max(numel(v),1));
        v=apply_blocked_value(v,blocked);
        ctx=set_series(ctx,output,v,'numeric',['operation:' id],rolemeta,unit,st,rs);
      case 'compare'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],''));
        group_id=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));
        require_series(ctx,value_id,id); require_series(ctx,group_id,id);
        if (!isnumeric(ctx.series.(value_id))), error('GXTXT:Analysis','compare value must be numeric: %s',value_id); endif
        ref=gxtxt_ini_get(def,['operation.' id '.reference'],'');
        method=gxtxt_ini_get(def,['operation.' id '.method'],'ratio');
        refagg=gxtxt_ini_get(def,['operation.' id '.reference_aggregate'],'median');
        v=gxtxt_analysis_op_compare(ctx.series.(value_id),ctx.series.(group_id),ref,method,refagg);
        [st,rs,blocked]=dependency_status(ctx,deps,op_output,numel(v)); v=apply_blocked_value(v,blocked);
        ctx=set_series(ctx,output,v,'numeric',['operation:' id],rolemeta,unit,st,rs);
      case 'normalize'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],'')); require_series(ctx,value_id,id);
        if (!isnumeric(ctx.series.(value_id))), error('GXTXT:Analysis','normalize value must be numeric: %s',value_id); endif
        method=gxtxt_ini_get(def,['operation.' id '.method'],'maxabs');
        [v,normalization]=gxtxt_analysis_op_normalize(ctx.series.(value_id),method,struct('y_unit',ctx.units.(value_id)));
        unit=statistical_output_unit(unit,normalization.unit,id);ctx=retain_statistics(ctx,output,normalization.statistical_results);
        [dst,drs,blocked]=dependency_status(ctx,deps,op_output,numel(v));v=apply_blocked_value(v,blocked);
        st=normalization.status;rs=normalization.reason;st(blocked)=dst(blocked);rs(blocked)=drs(blocked);
        ctx=set_series(ctx,output,v,'numeric',['operation:' id],rolemeta,unit,st,rs);
      case 'aggregate'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],'')); require_series(ctx,value_id,id);
        if (!isnumeric(ctx.series.(value_id))), error('GXTXT:Analysis','aggregate value must be numeric: %s',value_id); endif
        method=gxtxt_ini_get(def,['operation.' id '.method'],'mean');
        group_id=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],'')); group=[];
        if (!isempty(group_id)), require_series(ctx,group_id,id); group=ctx.series.(group_id); endif
        [v,aggregate]=gxtxt_analysis_op_aggregate(ctx.series.(value_id),method,group,struct('y_unit',ctx.units.(value_id)));
        unit=statistical_output_unit(unit,aggregate.unit,id);ctx=retain_statistics(ctx,output,aggregate.statistical_results);
        [dst,drs,blocked]=dependency_status(ctx,deps,op_output,numel(v));v=apply_blocked_value(v,blocked);
        st=aggregate.status;rs=aggregate.reason;st(blocked)=dst(blocked);rs(blocked)=drs(blocked);
        ctx=set_series(ctx,output,v,'numeric',['operation:' id],rolemeta,unit,st,rs);
      case 'filter'
        % Historical filter remains destructive.  v0.8.3 additionally accepts
        % target_series/target_parameter but new definitions should use mask
        % when they need reusable domains.
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],'')); require_series(ctx,value_id,id);
        if(numel(ctx.series.(value_id))!=ctx.row_count),error('GXTXT:Analysis','Destructive filter %s requires a primary row-aligned series; use align/mask for foreign-source data',id);endif
        target=resolve_target(def,id,ctx,'');
        mask=gxtxt_analysis_op_filter(ctx.series.(value_id),gxtxt_ini_get(def,['operation.' id '.operator'],'eq'),target);
        ctx=apply_mask(ctx,mask);
        ctx=set_series(ctx,output,true(ctx.row_count,1),'logical',['operation:' id],rolemeta,unit,valid_status(ctx.row_count),blank_reason(ctx.row_count));
      case 'mask'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],'')); require_series(ctx,value_id,id);
        target=resolve_target(def,id,ctx,'');
        v=gxtxt_analysis_op_mask(ctx.series.(value_id),gxtxt_ini_get(def,['operation.' id '.operator'],'eq'),target);
        [st,rs,blocked]=dependency_status(ctx,deps,op_output,numel(v)); v(blocked)=false;
        ctx=set_series(ctx,output,v,'logical',['operation:' id],rolemeta,unit,st,rs);
      case 'crossing'
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],'')); yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));
        require_series(ctx,xid,id); require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],'')); group=[];
        if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        target=resolve_numeric_target(def,id,ctx);
        F=gxtxt_analysis_op_crossing(ctx.series.(xid),ctx.series.(yid),target,group, ...
              gxtxt_ini_get(def,['operation.' id '.interpolation'],'linear'), ...
              gxtxt_ini_get(def,['operation.' id '.extrapolation'],'forbid'));
        % If an explicitly declared dependency is unavailable for a whole
        % group, report dependency_unavailable rather than a misleading local
        % crossing failure.
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,ctx.row_count);
        if(any(dblocked))
          [F]=feature_dependency_overlay(F,group,dblocked);
        endif
        F.group_id=gid; F.output=output; F.operation_id=id; F.target=target;
        ctx.features.(output)=F;
        ctx=set_series(ctx,output,F.broadcast,'numeric',['operation:' id],rolemeta,unit,F.broadcast_status,F.broadcast_reason);
      case 'join'
        left_id=strtrim(gxtxt_ini_get(def,['operation.' id '.left_key'],''));right_id=strtrim(gxtxt_ini_get(def,['operation.' id '.right_key'],''));value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],''));
        require_series(ctx,left_id,id);require_series(ctx,right_id,id);require_series(ctx,value_id,id);
        A=gxtxt_analysis_dispatch_kernel('join',ctx.series.(left_id),ctx.series.(right_id),ctx.series.(value_id));
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(A.values));A.values=apply_blocked_value(A.values,dblocked);A.status(dblocked)={'unavailable'};A.reason(dblocked)={'dependency_unavailable'};
        ctx=set_series(ctx,output,A.values,series_type(A.values),['operation:' id],rolemeta,unit,A.status,A.reason);
        ctx.provenance.(output)=struct('kind','join','left_key',left_id,'right_key',right_id,'value',value_id,'source_indices',A.source_indices,'method','exact');
      case {'align','resample'}
        target_id=strtrim(gxtxt_ini_get(def,['operation.' id '.target_x'],gxtxt_ini_get(def,['operation.' id '.reference'],'')));
        source_x_id=strtrim(gxtxt_ini_get(def,['operation.' id '.source_x'],''));
        if(strcmp(typ,'resample')),default_method='linear';else default_method='exact';endif
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],''));
        require_series(ctx,target_id,id);require_series(ctx,source_x_id,id);require_series(ctx,value_id,id);
        method=lower(strtrim(gxtxt_ini_get(def,['operation.' id '.method'],default_method)));
        tolraw=strtrim(gxtxt_ini_get(def,['operation.' id '.tolerance'],''));tolerance=[];if(!isempty(tolraw)),tolerance=str2double(tolraw);endif
        extrap=gxtxt_ini_get(def,['operation.' id '.extrapolation'],'forbid');
        target_gid=strtrim(gxtxt_ini_get(def,['operation.' id '.target_group'],''));source_gid=strtrim(gxtxt_ini_get(def,['operation.' id '.source_group'],''));target_group=[];source_group=[];
        if(!isempty(target_gid)),require_series(ctx,target_gid,id);target_group=ctx.series.(target_gid);endif
        if(!isempty(source_gid)),require_series(ctx,source_gid,id);source_group=ctx.series.(source_gid);endif
        A=gxtxt_analysis_dispatch_kernel(typ,ctx.series.(target_id),ctx.series.(source_x_id),ctx.series.(value_id),method,tolerance,extrap,target_group,source_group);
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(A.values));
        A.values=apply_blocked_value(A.values,dblocked);A.status(dblocked)={'unavailable'};A.reason(dblocked)={'dependency_unavailable'};
        ctx=set_series(ctx,output,A.values,'numeric',['operation:' id],rolemeta,unit,A.status,A.reason);
        ctx.provenance.(output)=struct('kind',typ,'target_series',target_id,'source_x',source_x_id,'value',value_id,'source_indices',A.source_indices,'method',method,'extrapolation',extrap,'target_group',target_gid,'source_group',source_gid);
      case 'interpolate'
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));qid=strtrim(gxtxt_ini_get(def,['operation.' id '.query'],''));
        require_series(ctx,xid,id);require_series(ctx,yid,id);require_series(ctx,qid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));qgid=strtrim(gxtxt_ini_get(def,['operation.' id '.query_group'],''));group=[];qgroup=[];
        if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        if(!isempty(qgid)),require_series(ctx,qgid,id);qgroup=ctx.series.(qgid);endif
        A=gxtxt_analysis_dispatch_kernel('interpolate',ctx.series.(xid),ctx.series.(yid),ctx.series.(qid),group,qgroup,gxtxt_ini_get(def,['operation.' id '.extrapolation'],'forbid'));
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(A.values));A.values=apply_blocked_value(A.values,dblocked);A.status(dblocked)={'unavailable'};A.reason(dblocked)={'dependency_unavailable'};
        ctx=set_series(ctx,output,A.values,'numeric',['operation:' id],rolemeta,unit,A.status,A.reason);ctx.provenance.(output)=struct('kind','interpolate','source_indices',A.source_indices,'x',xid,'y',yid,'query',qid);
      case {'peak','extrema'}
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));group=[];if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        [xx,yy,domain_mask]=domain_filtered_xy(def,id,ctx,xid,yid);
        mode=lower(strtrim(gxtxt_ini_get(def,['operation.' id '.mode'],'max')));if(strcmp(typ,'peak')&&isempty(mode)),mode='max';endif
        ret=lower(strtrim(gxtxt_ini_get(def,['operation.' id '.return'],'x')));
        F=gxtxt_analysis_dispatch_kernel(typ,xx,yy,group,mode,ret);F.group_id=gid;F.output=output;F.operation_id=id;F.domain=strtrim(gxtxt_ini_get(def,['operation.' id '.domain'],''));
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(F.broadcast));if(any(dblocked)),F=feature_dependency_overlay(F,group,dblocked);endif
        ctx.features.(output)=F;ctx=set_series(ctx,output,F.broadcast,'numeric',['operation:' id],rolemeta,unit,F.broadcast_status,F.broadcast_reason);
      case {'integrate','area'}
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));group=[];if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        [xx,yy,domain_mask]=domain_filtered_xy(def,id,ctx,xid,yid);
        F=gxtxt_analysis_dispatch_kernel(typ,xx,yy,group);F.group_id=gid;F.output=output;F.operation_id=id;F.domain=strtrim(gxtxt_ini_get(def,['operation.' id '.domain'],''));
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(F.broadcast));if(any(dblocked)),F=feature_dependency_overlay(F,group,dblocked);endif
        ctx.features.(output)=F;ctx=set_series(ctx,output,F.broadcast,'numeric',['operation:' id],rolemeta,unit,F.broadcast_status,F.broadcast_reason);
      case {'derivative','slope'}
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));group=[];if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        [xx,yy,domain_mask]=domain_filtered_xy(def,id,ctx,xid,yid);
        A=gxtxt_analysis_dispatch_kernel(typ,xx,yy,group);[dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(A.values));A.values=apply_blocked_value(A.values,dblocked);A.status(dblocked)={'unavailable'};A.reason(dblocked)={'dependency_unavailable'};
        if(!isempty(domain_mask)),outside=!domain_mask(:);A.values(outside)=NaN;A.status(outside)={'unavailable'};A.reason(outside)={'outside_domain'};endif
        ctx=set_series(ctx,output,A.values,'numeric',['operation:' id],rolemeta,unit,A.status,A.reason);
      case 'window'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],''));require_series(ctx,value_id,id);
        lo=resolve_named_bound(def,id,ctx,'min');hi=resolve_named_bound(def,id,ctx,'max');incl=parse_bool(gxtxt_ini_get(def,['operation.' id '.inclusive'],'1'),true);
        v=gxtxt_analysis_dispatch_kernel('window',ctx.series.(value_id),lo,hi,incl);[st,rs,blocked]=dependency_status(ctx,deps,op_output,numel(v));v(blocked)=false;ctx=set_series(ctx,output,v,'logical',['operation:' id],rolemeta,unit,st,rs);
      case 'correlate'
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));group=[];if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        [xx,yy,domain_mask]=domain_filtered_xy(def,id,ctx,xid,yid);
        scientific_context=struct('x_unit',ctx.units.(xid),'y_unit',ctx.units.(yid));
        F=gxtxt_analysis_dispatch_kernel('correlate',xx,yy,group,scientific_context);F.group_id=gid;F.output=output;F.operation_id=id;F.domain=strtrim(gxtxt_ini_get(def,['operation.' id '.domain'],''));
        ctx=retain_statistics(ctx,output,F.statistical_results);
        [dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(F.broadcast));if(any(dblocked)),F=feature_dependency_overlay(F,group,dblocked);endif
        ctx.features.(output)=F;ctx=set_series(ctx,output,F.broadcast,'numeric',['operation:' id],rolemeta,'1',F.broadcast_status,F.broadcast_reason);
      case 'regress'
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        gid=strtrim(gxtxt_ini_get(def,['operation.' id '.group'],''));group=[];if(!isempty(gid)),require_series(ctx,gid,id);group=ctx.series.(gid);endif
        [xx,yy,domain_mask]=domain_filtered_xy(def,id,ctx,xid,yid);
        scientific_context=struct('x_unit',ctx.units.(xid),'y_unit',ctx.units.(yid));
        R=gxtxt_analysis_dispatch_kernel('regress',xx,yy,group,scientific_context);[dst,drs,dblocked]=dependency_status(ctx,deps,op_output,numel(R.predicted));R.predicted=apply_blocked_value(R.predicted,dblocked);R.broadcast_status(dblocked)={'unavailable'};R.broadcast_reason(dblocked)={'dependency_unavailable'};
        ctx=retain_statistics(ctx,output,R.statistical_results);
        if(!isempty(domain_mask)),outside=!domain_mask(:);R.predicted(outside)=NaN;R.broadcast_status(outside)={'unavailable'};R.broadcast_reason(outside)={'outside_domain'};endif
        ctx=set_series(ctx,output,R.predicted,'numeric',['operation:' id],rolemeta,unit,R.broadcast_status,R.broadcast_reason);
        ctx=store_regression_features(ctx,output,id,gid,R);
      case 'fit'
        xid=strtrim(gxtxt_ini_get(def,['operation.' id '.x'],''));yid=strtrim(gxtxt_ini_get(def,['operation.' id '.y'],''));require_series(ctx,xid,id);require_series(ctx,yid,id);
        fid=strtrim(gxtxt_ini_get(def,['operation.' id '.family'],''));family=[];if(!isempty(fid)),require_series(ctx,fid,id);family=ctx.series.(fid);endif
        maxiter=str2double(gxtxt_ini_get(def,['operation.' id '.max_iter'],'400'));tol=str2double(gxtxt_ini_get(def,['operation.' id '.tolerance'],'1e-8'));
        scientific_context=struct('x_unit',ctx.units.(xid),'y_unit',ctx.units.(yid));
        R=gxtxt_analysis_dispatch_kernel('fit',ctx.series.(xid),ctx.series.(yid),family,runtime,maxiter,tol,scientific_context);n=numel(R.predicted);st=repmat({R.status},n,1);rs=repmat({R.reason},n,1);ctx=set_series(ctx,output,R.predicted,'numeric',['operation:' id],rolemeta,unit,st,rs);ctx.fit_results.(output)=R;ctx=store_fit_features(ctx,output,id,R,n);
        ctx=retain_statistics(ctx,output,{R.statistical_results});
      case 'convert_unit'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],''));require_series(ctx,value_id,id);to_unit=strtrim(gxtxt_ini_get(def,['operation.' id '.to_unit'],unit));from_unit=strtrim(gxtxt_ini_get(def,['operation.' id '.from_unit'],ctx.units.(value_id)));
        if(isempty(to_unit)),error('GXTXT:Analysis','convert_unit %s requires to_unit or operation unit metadata',id);endif
        v=gxtxt_analysis_dispatch_kernel('convert_unit',ctx.series.(value_id),from_unit,to_unit);[st,rs,blocked]=dependency_status(ctx,deps,op_output,numel(v));v=apply_blocked_value(v,blocked);ctx=set_series(ctx,output,v,'numeric',['operation:' id],rolemeta,to_unit,st,rs);
      case 'select'
        value_id=strtrim(gxtxt_ini_get(def,['operation.' id '.value'],'')); require_series(ctx,value_id,id);
        ctx=set_series(ctx,output,ctx.series.(value_id),ctx.types.(value_id),['operation:' id],ctx.roles.(value_id),ctx.units.(value_id),ctx.status.(value_id),ctx.reason.(value_id));
      otherwise
        error('GXTXT:Analysis','Unsupported operation type %s in %s',typ,id);
    endswitch
  endfor

  export_ids=parse_list(gxtxt_ini_get(def,'exports.ids',''));
  exported={};
  for i=1:numel(export_ids)
    eid=export_ids{i}; et=lower(strtrim(gxtxt_ini_get(def,['export.' eid '.type'],'')));
    file=strtrim(gxtxt_ini_get(def,['export.' eid '.file'],''));
    if (isempty(file)), error('GXTXT:Analysis','Export %s has no file',eid); endif
    path=fullfile(output_dir,file);
    switch et
      case 'csv'
        cols=parse_list(gxtxt_ini_get(def,['export.' eid '.columns'],''));
        write_csv(path,ctx,cols); exported{end+1}=path; %#ok<AGROW>
      case 'feature_table'
        feats=parse_list(gxtxt_ini_get(def,['export.' eid '.features'],''));
        write_feature_table(path,ctx,feats); exported{end+1}=path; %#ok<AGROW>
      case {'summary','text_summary'}
        write_summary(path,definition_path,defid,ctx,order); exported{end+1}=path; %#ok<AGROW>
      case 'statistical_results'
        named=struct();if(isfield(ctx,'statistical_results')),named=ctx.statistical_results;endif
        text=gxtxt_statistics_v1('publication_metadata',named);
        fid=fopen(path,'w');if(fid<0),error('GXTXT:Analysis','Cannot write %s',path);endif
        unwind_protect,fprintf(fid,'%s\n',text);unwind_protect_cleanup,fclose(fid);end_unwind_protect
        exported{end+1}=path;
      otherwise
        error('GXTXT:Analysis','Unsupported export type %s in %s',et,eid);
    endswitch
  endfor

  render=true; if(isfield(options,'render')),render=logical(options.render);endif
  if(render), plot_files=gxtxt_analysis_render_plots(def,ctx,output_dir,options); else plot_files={}; endif
  result=struct('definition_id',defid,'definition_path',definition_path,'context',ctx,'exports',{exported},'plots',{plot_files},'operation_order',{order});
endfunction

function ctx=empty_context()
  ctx=struct(); ctx.series=struct(); ctx.types=struct(); ctx.origins=struct(); ctx.roles=struct(); ctx.units=struct();
  ctx.status=struct(); ctx.reason=struct(); ctx.features=struct(); ctx.parameters=struct(); ctx.bindings=struct();
  ctx.lengths=struct();ctx.row_aligned=struct();ctx.provenance=struct();ctx.fit_results=struct();
  ctx.source_rows=struct();ctx.source_paths=struct();ctx.primary_source='primary';
  ctx.optional_missing={}; ctx.row_count=0;
endfunction

function ctx=set_series(ctx,id,v,typ,origin,role,unit,status,reason)
  ctx.series.(id)=v; ctx.types.(id)=typ; ctx.origins.(id)=origin; ctx.roles.(id)=role; ctx.units.(id)=unit;
  ctx.status.(id)=status; ctx.reason.(id)=reason;ctx.lengths.(id)=numel(v);
  ctx.row_aligned.(id)=(isscalar(v)||ctx.row_count==0||numel(v)==ctx.row_count);
endfunction

function unit=statistical_output_unit(declared,actual,operation)
  unit=actual;
  if(isempty(declared)||strcmp(declared,actual)),return;endif
  % Unit labels cannot rescale an aggregate or a dimensionless transform.
  % Explicit convert_unit is the operation that changes numerical units.
  same=false;
  if(!isempty(actual))
    try converted=gxtxt_unit_convert([0;1],actual,declared);same=isequal(converted,[0;1]);catch;end_try_catch
  endif
  if(!same),error('GXTXT:Analysis','Operation %s declares unit %s but its actual output unit is %s; use explicit variable metadata or convert_unit',operation,declared,actual);endif
  unit=declared;
endfunction

function target=resolve_target(def,id,ctx,default)
  ts=strtrim(gxtxt_ini_get(def,['operation.' id '.target_series'],''));
  tp=strtrim(gxtxt_ini_get(def,['operation.' id '.target_parameter'],''));
  if(!isempty(ts)),require_series(ctx,ts,id);target=ctx.series.(ts);return;endif
  if(!isempty(tp))
    if(!isfield(ctx.parameters,tp)),error('GXTXT:Analysis','Operation %s references missing parameter %s',id,tp);endif
    target=ctx.parameters.(tp);return;
  endif
  target=gxtxt_ini_get(def,['operation.' id '.target'],default);
endfunction

function target=resolve_numeric_target(def,id,ctx)
  q=resolve_target(def,id,ctx,'');
  if(ischar(q)),target=str2double(q);else target=q;endif
  if(!isnumeric(target)||!isscalar(target)||!isfinite(target)),error('GXTXT:Analysis','Operation %s requires one finite numeric target',id);endif
endfunction

function [st,rs,blocked]=dependency_status(ctx,deps,op_output,n)
  st=valid_status(n); rs=blank_reason(n); blocked=false(n,1);
  if(isempty(deps)),return;endif
  for i=1:numel(deps)
    out=op_output.(deps{i});
    if(!isfield(ctx.status,out)),continue;endif
    q=ctx.status.(out); if(isscalar(q)),q=repmat(q,n,1);endif
    if(numel(q)!=n)
      if(numel(q)==1),q=repmat(q,n,1);else error('GXTXT:Analysis','Dependency status length mismatch for %s',deps{i});endif
    endif
    for r=1:n
      if(any(strcmp(q{r},{'unavailable','failed'}))),blocked(r)=true;endif
    endfor
  endfor
  st(blocked)={'unavailable'}; rs(blocked)={'dependency_unavailable'};
endfunction

function v=apply_blocked_value(v,blocked)
  if(isempty(blocked)||!any(blocked)),return;endif
  if(isscalar(v))
    if(any(blocked)), if(isnumeric(v)||islogical(v)),v=NaN;elseif(iscell(v)),v={''};endif; endif
    return;
  endif
  if(isnumeric(v)||islogical(v)),v=v(:);v(blocked)=NaN;elseif(iscell(v)),v=v(:);v(blocked)={''};endif
endfunction

function F=feature_dependency_overlay(F,group,blocked)
  n=numel(blocked);
  for gi=1:numel(F.values)
    if(strcmp(F.group_kind,'global'))
      idx=true(n,1);
    elseif(strcmp(F.group_kind,'string'))
      idx=strcmp(group,F.group_values{gi});
    else
      idx=(group(:)==F.group_values{gi});
    endif
    if(any(blocked(idx)))
      F.values(gi)=NaN;F.status{gi}='unavailable';F.reason{gi}='dependency_unavailable';
      F.broadcast(idx)=NaN;F.broadcast_status(idx)={'unavailable'};F.broadcast_reason(idx)={'dependency_unavailable'};
    endif
  endfor
endfunction

function order=topological_order(def,ops)
  pending=ops; order={}; done={};
  while (!isempty(pending))
    progressed=false;
    for i=1:numel(pending)
      id=pending{i}; deps=parse_list(gxtxt_ini_get(def,['operation.' id '.depends'],''));
      unknown=setdiff(deps,ops);
      if (!isempty(unknown)), error('GXTXT:Analysis','Operation %s depends on unknown operation %s',id,unknown{1}); endif
      if (all(cellfun(@(x) any(strcmp(done,x)),deps)))
        order{end+1}=id; done{end+1}=id; pending(i)=[]; progressed=true; break; %#ok<AGROW>
      endif
    endfor
    if (!progressed), error('GXTXT:Analysis','Operation dependency cycle detected'); endif
  endwhile
endfunction

function ctx=apply_mask(ctx,mask)
  n=numel(mask);
  f=fieldnames(ctx.series);
  for i=1:numel(f)
    v=ctx.series.(f{i}); if(numel(v)==n),ctx.series.(f{i})=v(mask);endif
    if(isfield(ctx.status,f{i})),q=ctx.status.(f{i});if(numel(q)==n),ctx.status.(f{i})=q(mask);endif;endif
    if(isfield(ctx.reason,f{i})),q=ctx.reason.(f{i});if(numel(q)==n),ctx.reason.(f{i})=q(mask);endif;endif
  endfor
  ff=fieldnames(ctx.features);
  for i=1:numel(ff)
    F=ctx.features.(ff{i});
    if(isfield(F,'broadcast')&&numel(F.broadcast)==n),F.broadcast=F.broadcast(mask);F.broadcast_status=F.broadcast_status(mask);F.broadcast_reason=F.broadcast_reason(mask);ctx.features.(ff{i})=F;endif
  endfor
  ctx.row_count=sum(mask);
endfunction

function require_row_compatible(v,ctx,kind,id)
  if (!(isscalar(v) || numel(v)==ctx.row_count)), error('GXTXT:Analysis','%s %s produced %d values for %d rows',kind,id,numel(v),ctx.row_count); endif
endfunction
function require_series(ctx,id,op)
  if (isempty(id) || !isfield(ctx.series,id)), error('GXTXT:Analysis','Operation %s references missing series %s',op,id); endif
endfunction
function t=series_type(v), if(islogical(v)),t='logical';elseif(isnumeric(v)),t='numeric';elseif(iscell(v)||ischar(v)),t='string';else t='other';endif; endfunction
function [src,col,isq]=split_runtime_binding(value,source_map)
  src='primary'; col=strtrim(value); isq=false;
  p=find(col=='.',1,'first');
  if(isempty(p)),return;endif
  candidate=col(1:p-1); rest=col(p+1:end);
  if(isempty(candidate)||isempty(rest)),return;endif
  sk=safe_field(candidate);
  if(isfield(source_map,sk))
    src=candidate; col=rest; isq=true;
  endif
endfunction

function validate_id(id,what), if(isempty(regexp(id,'^[A-Za-z][A-Za-z0-9_]*$','once'))),error('GXTXT:Analysis','Invalid %s ID: %s',what,id);endif; endfunction
function k=safe_field(id), k=regexprep(id,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif; endfunction
function a=parse_list(s), s=strrep(s,',',';'); if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endif; endfunction
function b=parse_bool(s,def), q=lower(strtrim(s)); if(isempty(q)),b=def;elseif(any(strcmp(q,{'1','true','yes','on'}))),b=true;elseif(any(strcmp(q,{'0','false','no','off'}))),b=false;else b=def;endif; endfunction
function s=valid_status(n),s=repmat({'valid'},max(1,n),1);endfunction
function s=blank_reason(n),s=repmat({''},max(1,n),1);endfunction

function [role,unit]=operation_meta(def,id)
  role=strtrim(gxtxt_ini_get(def,['operation.' id '.role'],''));
  unit=strtrim(gxtxt_ini_get(def,['operation.' id '.unit'],''));
endfunction

function raw=parameter_override(options,runtime,id,defval)
  raw=defval;
  if(isfield(runtime,'analysis_parameters') && isstruct(runtime.analysis_parameters) && isfield(runtime.analysis_parameters,id)),raw=runtime.analysis_parameters.(id);endif
  q=gxtxt_ini_get(runtime,['analysis_parameters.' id],''); if(!isempty(strtrim(q))),raw=q;endif
  if(isfield(options,'parameters') && isstruct(options.parameters) && isfield(options.parameters,id)),raw=options.parameters.(id);endif
  if(isnumeric(raw)||islogical(raw)),raw=sprintf('%.17g',raw);endif
endfunction
function v=parse_parameter(raw,typ,id)
  switch typ
    case {'numeric','double','number'},v=str2double(raw);if(!isfinite(v)),error('GXTXT:Analysis','Parameter %s is not finite numeric',id);endif
    case {'bool','boolean','logical'},v=parse_bool(raw,false);
    case {'string','text','choice'},v=char(raw);
    otherwise,error('GXTXT:Analysis','Unsupported parameter type %s for %s',typ,id);
  endswitch
endfunction
function validate_parameter_value(def,id,typ,v)
  if(any(strcmp(typ,{'numeric','double','number'})))
    lo=strtrim(gxtxt_ini_get(def,['parameter.' id '.min'],''));hi=strtrim(gxtxt_ini_get(def,['parameter.' id '.max'],''));
    if(!isempty(lo)),q=str2double(lo);if(!isfinite(q)),error('GXTXT:Analysis','Parameter %s has invalid min=',id);endif;if(v<q),error('GXTXT:Analysis','Parameter %s is below minimum %.17g',id,q);endif;endif
    if(!isempty(hi)),q=str2double(hi);if(!isfinite(q)),error('GXTXT:Analysis','Parameter %s has invalid max=',id);endif;if(v>q),error('GXTXT:Analysis','Parameter %s is above maximum %.17g',id,q);endif;endif
  elseif(strcmp(typ,'choice'))
    choices=parse_list(gxtxt_ini_get(def,['parameter.' id '.choices'],''));if(isempty(choices)),error('GXTXT:Analysis','Choice parameter %s declares no choices',id);endif
    if(!any(strcmp(choices,v))),error('GXTXT:Analysis','Parameter %s is not one of the declared choices',id);endif
  endif
endfunction

function q=resolve_named_bound(def,id,ctx,name)
  sid=strtrim(gxtxt_ini_get(def,['operation.' id '.' name '_series'],''));pid=strtrim(gxtxt_ini_get(def,['operation.' id '.' name '_parameter'],''));lit=strtrim(gxtxt_ini_get(def,['operation.' id '.' name],''));
  if(!isempty(sid)),require_series(ctx,sid,id);q=ctx.series.(sid);return;endif
  if(!isempty(pid)),if(!isfield(ctx.parameters,pid)),error('GXTXT:Analysis','Operation %s references missing parameter %s',id,pid);endif;q=ctx.parameters.(pid);return;endif
  if(isempty(lit)),q=[];else q=str2double(lit);if(!isfinite(q)),error('GXTXT:Analysis','Operation %s has invalid %s bound',id,name);endif;endif
endfunction

function [x,y,mask]=domain_filtered_xy(def,id,ctx,xid,yid)
  x=ctx.series.(xid);y=ctx.series.(yid);mask=[];did=strtrim(gxtxt_ini_get(def,['operation.' id '.domain'],''));
  if(isempty(did)),return;endif
  require_series(ctx,did,id);mask=ctx.series.(did);if(!islogical(mask)),mask=logical(mask);endif
  if(numel(mask)!=numel(x)||numel(mask)!=numel(y)),error('GXTXT:Analysis','Operation %s domain %s is not aligned to x/y',id,did);endif
  mask=mask(:);x=x(:);y=y(:);x(!mask)=NaN;y(!mask)=NaN;
endfunction

function ctx=retain_statistics(ctx,output,results)
  if(!isfield(ctx,'statistical_results')),ctx.statistical_results=struct();endif
  for k=1:numel(results)
    if(!isempty(results{k})),ctx.statistical_results.(sprintf('%s_group%d',output,k))=results{k};endif
  endfor
endfunction
function ctx=store_regression_features(ctx,output,opid,gid,R)
  n=ctx.row_count; names={'slope','intercept','r2'};group=[];if(!isempty(gid)&&isfield(ctx.series,gid)),group=ctx.series.(gid);endif
  for j=1:numel(names)
    nm=names{j};fid=[output '_' nm];vals=R.(nm);status=R.status;reason=R.reason;
    if(strcmp(nm,'r2')),status=R.r2_status;reason=R.r2_reason;endif
    F=feature_from_group_values(R.group_values,R.group_kind,vals,status,reason,gid,n,group);F.output=fid;F.operation_id=opid;ctx.features.(fid)=F;ctx=set_series(ctx,fid,F.broadcast,'numeric',['operation:' opid],['regression_' nm],'',F.broadcast_status,F.broadcast_reason);
  endfor
endfunction

function ctx=store_fit_features(ctx,output,opid,R,n)
  names=R.parameter_names;if(isempty(names)),names=arrayfun(@(i)sprintf('p%d',i),1:numel(R.theta),'UniformOutput',false);endif
  for i=1:numel(R.theta)
    fid=[output '_' safe_field(names{i})];F=global_feature(R.theta(i),R.status,R.reason,n);F.output=fid;F.operation_id=opid;ctx.features.(fid)=F;ctx=set_series(ctx,fid,F.broadcast,'numeric',['operation:' opid],'fit_parameter','',F.broadcast_status,F.broadcast_reason);
  endfor
  for spec={'rmse','mae','r2'}
    nm=spec{1};fid=[output '_' nm];meaning=R.diagnostic_features.(nm);
    F=global_feature(R.(nm),meaning.status,meaning.reason,n);F.output=fid;F.operation_id=opid;ctx.features.(fid)=F;ctx=set_series(ctx,fid,F.broadcast,'numeric',['operation:' opid],'fit_diagnostic',meaning.unit,F.broadcast_status,F.broadcast_reason);
  endfor
endfunction

function F=feature_from_group_values(gvals,gkind,vals,st,rs,gid,n,group)
  bc=NaN(n,1);bs=repmat({'unavailable'},n,1);br=repmat({'group_not_found'},n,1);
  if(strcmp(gkind,'global')),bc(:)=vals(1);bs(:)=st(1);br(:)=rs(1);
  elseif(!isempty(group))
    for i=1:numel(vals),if(strcmp(gkind,'string')),idx=strcmp(group,gvals{i});else idx=(group(:)==gvals{i});endif;bc(idx)=vals(i);bs(idx)=st(i);br(idx)=rs(i);endfor
  endif
  F=struct('group_values',{gvals},'group_kind',gkind,'values',vals(:),'status',{st},'reason',{rs},'broadcast',bc,'broadcast_status',{bs},'broadcast_reason',{br},'group_id',gid);
endfunction

function F=global_feature(value,status,reason,n)
  F=struct();F.group_values={'__global__'};F.group_kind='global';F.values=value;F.status={status};F.reason={reason};F.broadcast=repmat(value,n,1);F.broadcast_status=repmat({status},n,1);F.broadcast_reason=repmat({reason},n,1);F.group_id='';
endfunction

function write_csv(path,ctx,cols)
  if (isempty(cols)), cols=fieldnames(ctx.series)'; endif
  for i=1:numel(cols)
    require_series(ctx,cols{i},'export');v=ctx.series.(cols{i});
    if(!(isscalar(v)||numel(v)==ctx.row_count)),error('GXTXT:Analysis','CSV export column %s is not aligned to the primary row set; align/resample it first',cols{i});endif
  endfor
  fid=fopen(path,'w');if(fid<0),error('GXTXT:Analysis','Cannot write %s',path);endif
  unwind_protect
    fprintf(fid,'%s\n',join_csv(cols)); n=ctx.row_count;
    for r=1:n
      cells=cell(1,numel(cols));
      for c=1:numel(cols)
        v=ctx.series.(cols{c});
        if (isscalar(v) && n>1), q=v; elseif (iscell(v)), q=v{r}; else q=v(r); endif
        cells{c}=csv_value(q);
      endfor
      fprintf(fid,'%s\n',join_csv(cells));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function write_feature_table(path,ctx,feats)
  if(isempty(feats)),feats=fieldnames(ctx.features)';endif
  if(isempty(feats)),error('GXTXT:Analysis','feature_table export requested but no features exist');endif
  for i=1:numel(feats),if(!isfield(ctx.features,feats{i})),error('GXTXT:Analysis','Unknown feature in feature_table export: %s',feats{i});endif;endfor
  base=ctx.features.(feats{1}); ng=numel(base.values); gid=base.group_id; if(isempty(gid)),gid='scope';endif
  for i=2:numel(feats)
    F=ctx.features.(feats{i}); if(numel(F.values)!=ng || !strcmp(F.group_id,base.group_id)),error('GXTXT:Analysis','feature_table features must share one grouping');endif
    for k=1:ng,if(!group_equal(F.group_values{k},base.group_values{k})),error('GXTXT:Analysis','feature_table group ordering mismatch');endif;endfor
  endfor
  head={gid};
  for i=1:numel(feats),head{end+1}=feats{i};head{end+1}=[feats{i} '_status'];head{end+1}=[feats{i} '_reason'];endfor
  fid=fopen(path,'w');if(fid<0),error('GXTXT:Analysis','Cannot write %s',path);endif
  unwind_protect
    fprintf(fid,'%s\n',join_csv(head));
    for r=1:ng
      row={base.group_values{r}};
      for i=1:numel(feats),F=ctx.features.(feats{i});row{end+1}=F.values(r);row{end+1}=F.status{r};row{end+1}=F.reason{r};endfor
      fprintf(fid,'%s\n',join_csv(row));
    endfor
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function tf=group_equal(a,b),if(isnumeric(a)&&isnumeric(b)),tf=(a==b);else tf=strcmp(char(a),char(b));endif;endfunction
function s=csv_value(q)
  if (isnumeric(q) || islogical(q)), s=sprintf('%.12g',q); return; endif
  s=char(q); if(any(s==',')||any(s=='"')||any(s==sprintf('\n'))),s=['"' strrep(s,'"','""') '"'];endif
endfunction
function s=join_csv(c), s='';for i=1:numel(c),if(i>1),s=[s ','];endif;s=[s csv_value(c{i})];endfor;endfunction

function write_summary(path,definition_path,defid,ctx,order)
  fid=fopen(path,'w');if(fid<0),error('GXTXT:Analysis','Cannot write %s',path);endif
  unwind_protect
    fprintf(fid,'GX-TXT Scientific Analysis API v1\n');
    fprintf(fid,'Definition: %s\nDescriptor: %s\nRows: %d\n',defid,definition_path,ctx.row_count);
    fprintf(fid,'Operations: %s\n',strjoin(order,', '));
    if(!isempty(ctx.optional_missing)),fprintf(fid,'Optional variables unavailable: %s\n',strjoin(ctx.optional_missing,', '));endif
    fprintf(fid,'Series:\n'); f=fieldnames(ctx.series);
    for i=1:numel(f)
      counts=status_counts(ctx.status.(f{i}));
      fprintf(fid,'  %s [%s] role=%s unit=%s <- %s status(valid=%d warning=%d unavailable=%d failed=%d)\n',f{i},ctx.types.(f{i}),ctx.roles.(f{i}),ctx.units.(f{i}),ctx.origins.(f{i}),counts(1),counts(2),counts(3),counts(4));
    endfor
    pf=fieldnames(ctx.provenance);if(!isempty(pf)),fprintf(fid,'Provenance:\n');endif
    for i=1:numel(pf)
      P=ctx.provenance.(pf{i});kind='';if(isfield(P,'kind')),kind=P.kind;endif
      fprintf(fid,'  %s kind=%s\n',pf{i},kind);
    endfor
    ff=fieldnames(ctx.features); if(!isempty(ff)),fprintf(fid,'Features:\n');endif
    for i=1:numel(ff)
      F=ctx.features.(ff{i});
      for k=1:numel(F.values),fprintf(fid,'  %s group=%s value=%s status=%s reason=%s\n',ff{i},csv_value(F.group_values{k}),csv_value(F.values(k)),F.status{k},F.reason{k});endfor
    endfor
    if(isfield(ctx,'statistical_results'))
      names=fieldnames(ctx.statistical_results);
      for k=1:numel(names),fprintf(fid,'\n%s\n%s\n',names{k},gxtxt_statistics_v1('report',ctx.statistical_results.(names{k})));endfor
    endif
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function c=status_counts(s),c=zeros(1,4);names={'valid','warning','unavailable','failed'};for i=1:4,c(i)=sum(strcmp(s,names{i}));endfor;endfunction
