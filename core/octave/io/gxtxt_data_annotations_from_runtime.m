% GX-TXT Computed Data Annotation API v1 runtime reader.
% SPDX-License-Identifier: GPL-3.0-or-later
function A = gxtxt_data_annotations_from_runtime(cfg, source_id)
  if(nargin<2||isempty(source_id)),source_id='primary';endif
  base=['analysis_source.' source_id '.computed_annotations.'];
  path=strtrim(gxtxt_ini_get(cfg,[base 'file'],''));
  A=struct('id',{},'type',{},'x',{},'x_variable',{},'x_unit',{},'y',{},'y_variable',{},'y_unit',{},'label',{},'style_hint',{});
  if(isempty(path)||exist(path,'file')!=2),return;endif
  d=gxtxt_ini_read(path); n=str2double(gxtxt_ini_get(d,'annotations.count','0')); if(!isfinite(n)||n<0),return;endif
  for i=1:round(n)
    p=sprintf('annotation.%d.',i); type=lower(strtrim(gxtxt_ini_get(d,[p 'type'],''))); id=strtrim(gxtxt_ini_get(d,[p 'id'],''));
    if(isempty(id)||!any(strcmp(type,{'vline','hline','point','text'}))),continue;endif
    q=struct('id',id,'type',type,'x',NaN,'x_variable','','x_unit','','y',NaN,'y_variable','','y_unit','','label','','style_hint','');
    for f={'x_variable','x_unit','y_variable','y_unit','label','style_hint'},name=f{1};q.(name)=strtrim(gxtxt_ini_get(d,[p name],''));endfor
    sx=strtrim(gxtxt_ini_get(d,[p 'x'],''));if(!isempty(sx)),q.x=str2double(sx);endif
    sy=strtrim(gxtxt_ini_get(d,[p 'y'],''));if(!isempty(sy)),q.y=str2double(sy);endif
    A(end+1)=q; %#ok<AGROW>
  endfor
endfunction
