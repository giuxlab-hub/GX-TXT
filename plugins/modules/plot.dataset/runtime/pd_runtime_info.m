function info=pd_runtime_info(cfg)
% Resolve the dedicated 3D source/bindings/metadata for plot.dataset.
% 2D scientific bindings are resolved exclusively through Graph Series API v1.
% SPDX-License-Identifier: GPL-3.0-or-later
  info=struct();
  info.source_path=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.path',''));
  if(isempty(info.source_path)),info.source_path=strtrim(gxtxt_ini_get(cfg,'dataset.path',''));endif
  info.dataset_id=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.dataset_id',''));
  if(isempty(info.dataset_id)),info.dataset_id=strtrim(gxtxt_ini_get(cfg,'dataset.id',''));endif
  info.dataset_kind=strtrim(gxtxt_ini_get(cfg,'analysis_source.primary.kind',''));
  if(isempty(info.dataset_kind)),info.dataset_kind=strtrim(gxtxt_ini_get(cfg,'dataset.kind',''));endif
  % CORE 0.9.7.22 still requires a primary Analysis Source for the Standard
  % Module lifecycle. It is used here only by the current 3D binding model;
  % 2D data loading is driven by Graph Series Dataset IDs and Variable IDs.
  if(!isempty(info.source_path)&&exist(info.source_path,'file')!=2)
    error('plot.dataset: canonical primary source file is missing: %s',info.source_path);
  endif
  info.x=pd_binding(cfg,'x');info.y=pd_binding(cfg,'y');info.z=pd_binding(cfg,'z');
  info.family=pd_binding(cfg,'family');info.color=pd_binding(cfg,'color');
  info.x_meta=pd_meta(cfg,info.x);info.y_meta=pd_meta(cfg,info.y);info.z_meta=pd_meta(cfg,info.z);
  info.family_meta=pd_meta(cfg,info.family);info.color_meta=pd_meta(cfg,info.color);
endfunction

function v=pd_binding(cfg,role)
  q=strtrim(gxtxt_ini_get(cfg,['bindings.' role],''));
  if(isempty(q)||strcmpi(q,'auto')||strcmpi(q,'none')),v='';return;endif
  dot=find(q=='.',1);
  if(!isempty(dot))
    src=q(1:dot-1);if(!strcmp(src,'primary')),error('plot.dataset: 3D binding %s must use primary source, got %s',role,q);endif
    v=q(dot+1:end);
  else v=q;endif
endfunction

function m=pd_meta(cfg,varname)
  m=struct('found',false,'source_id','primary','dataset_id','','name',varname,'unit','','semantic_role','','value_kind','','value_format','','time_reference','','time_origin','','original_header','','source_column','');
  if(isempty(varname)),return;endif
  try
    [u,r,q]=gxtxt_analysis_source_variable_meta(cfg,'primary',varname);m=q;m.unit=strtrim(u);m.semantic_role=strtrim(r);
  catch;m.name=varname;end_try_catch
endfunction
