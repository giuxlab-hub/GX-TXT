% Verify queued scientific dependencies in the actual runtime process.
% SPDX-License-Identifier: GPL-3.0-or-later
function curvefit_family_recipe_guard(cfg,audit)
  if(nargin<2),audit=struct();endif
  for item={'source','descriptor'}
    name=item{1};expected=gxtxt_ini_get(cfg,['family_recipe.model_' name '_sha256'],'');
    if(isempty(expected)),continue;endif
    field='model.script';if(strcmp(name,'descriptor')),field='model.descriptor_path';endif
    path=gxtxt_ini_get(cfg,field,'');
    if(exist(path,'file')!=2||!strcmp(hash('sha256',fileread(path)),expected))
      error('curvefit.family_global: queued mathematical model %s changed before publication',name);
    endif
  endfor
  if(isfield(audit,'source_identity'))
    for item={'sha256','schema_identity'}
      key=item{1};expected=gxtxt_ini_get(cfg,['family_recipe.source_' key],'');
      if(!isempty(expected)&&(!isstruct(audit.source_identity)||!strcmp(audit.source_identity.(key),expected)))
        error('curvefit.family_global: queued scientific Dataset identity changed before fitting');
      endif
    endfor
  endif
  for item={'parameters','domain'}
    name=item{1};path=gxtxt_ini_get(cfg,['family_recipe.' name '_path'],'');
    if(isempty(path)),continue;endif
    expected=str2double(gxtxt_ini_get(cfg,['family_recipe.' name '_exists'],''));
    present=exist(path,'file')==2;
    if(!ismember(expected,[0,1])||present!=expected||(present&&!strcmp(hash('sha256',fileread(path)),gxtxt_ini_get(cfg,['family_recipe.' name '_sha256'],''))))
      error('curvefit.family_global: queued frozen %s file changed before publication',name);
    endif
  endfor
endfunction
