function curvefit_family_rerender_main(args)
% GX-TXT Standard Module API v1 - cache-only curve family rerender
% GX-TXT Pipeline v0.7.8 Progress API integration
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% This entry point performs presentation only. It does not load the model and
% does not run fitting or scientific evaluation.

  config_path=arg_value(args,'--config','');
  if (isempty(config_path)), error('curvefit.family_global rerender: --config is required'); endif
  cfg=read_ini(config_path);
  numeric_fn=curvefit_numeric_api(cfg,{'residual_metrics'});
  outdir=ini_get(cfg,'runtime.output_dir','');
  if (isempty(outdir)), error('curvefit.family_global rerender: runtime.output_dir missing'); endif

  progress_start_safe('loading_cache','Loading render cache','indeterminate',0);
  try
    cache_path=fullfile(outdir,'render_cache.mat');
    if (exist(cache_path,'file') != 2), error('curvefit.family_global rerender: render_cache.mat not found: %s',cache_path); endif
    cache=load(cache_path);

    % Legacy cache variables remain authoritative for physical model inputs.
    x=cache_required(cache,'x'); family=cache_required(cache,'family');
    y=cache_required(cache,'y'); pred=cache_required(cache,'pred');
    x=x(:); family=family(:); y=y(:); pred=pred(:);
    if (numel(x)!=numel(family) || numel(x)!=numel(y) || numel(x)!=numel(pred))
      error('curvefit.family_global rerender: inconsistent cache vector lengths');
    endif

    x_name=cache_text(cache,'x_name',resolved_binding(cfg,'x','model.x_column','X'));
    fam_name=cache_text(cache,'fam_name',resolved_binding(cfg,'family','model.family_column','family'));
    y_name=cache_text(cache,'y_name',resolved_binding(cfg,'y','model.y_column','Y'));

    operation_mode=lower(strtrim(ini_get(cfg,'config.operation_mode','')));
    if (isempty(operation_mode)), operation_mode=lower(cache_text(cache,'operation_mode','fit')); endif
    if (!any(strcmp(operation_mode,{'fit','evaluate'}))), operation_mode='fit'; endif

    presentation_orientation=lower(strtrim(ini_get(cfg,'config.presentation_orientation','')));
    if (isempty(presentation_orientation)), presentation_orientation=lower(cache_text(cache,'presentation_orientation','x_by_family')); endif
    if (!any(strcmp(presentation_orientation,{'x_by_family','family_by_x'}))), presentation_orientation='x_by_family'; endif

    [horizontal,group,horizontal_name,group_name]=presentation_view(x,family,x_name,fam_name,presentation_orientation);
    residual=pred-y;
    group_metrics=compute_group_metrics(group,y,pred,numeric_fn);

    minimum_abs_y_for_relative_error=str2double(ini_get(cfg,'config.minimum_abs_y_for_relative_error',''));
    if (!isfinite(minimum_abs_y_for_relative_error) || minimum_abs_y_for_relative_error < 0)
      if (isfield(cache,'minimum_abs_y_for_relative_error'))
        minimum_abs_y_for_relative_error=cache.minimum_abs_y_for_relative_error;
      else
        minimum_abs_y_for_relative_error=1e-12;
      endif
    endif
    relative_error_mask=(abs(y)>=minimum_abs_y_for_relative_error) & (y!=0);
    relative_residual_percent=NaN(size(y));
    relative_residual_percent(relative_error_mask)=100.*residual(relative_error_mask)./y(relative_error_mask);

    session=strtrim(ini_get(cfg,'runtime.session',''));
    if(!isempty(session))
      progress_stage_safe('rendering','Rendering public Plot Variants','indeterminate',0);
      source_id=cache_text(cache,'dataset_id','');
      graph_data=curvefit_family_publish(session,source_id,horizontal,group,y,pred,residual,relative_residual_percent,group_metrics);
      curvefit_family_render_public(outdir,cfg,graph_data,horizontal_name,group_name,y_name,operation_mode);
    endif

    enabled_raw=ini_get(cfg,'graph_provider.enabled','curvefit.family.overlay');
    fprintf('[curvefit.family_global] rerender complete; mode=%s orientation=%s enabled=%s\n', ...
            operation_mode,presentation_orientation,enabled_raw);
    progress_complete_safe('completed','Curve fitting rerender completed');
  catch err
    progress_fail_safe('failed','Curve fitting rerender failed; see log for details');
    rethrow(err);
  end_try_catch
endfunction

function v=arg_value(args,key,def)
  v=def; for k=1:numel(args)-1, if(strcmp(args{k},key)),v=args{k+1};return;endif; endfor
endfunction

function d=read_ini(path)
  d=struct();sec='';fid=fopen(path,'r');if(fid<0),error('Cannot open INI: %s',path);endif
  unwind_protect
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif
      tok=regexp(line,'^\[(.+)\]$','tokens','once');if(!isempty(tok)),sec=tok{1};continue;endif
      eq=find(line=='=',1);if(isempty(eq)),continue;endif
      key=strtrim(line(1:eq-1));val=line(eq+1:end);d.(make_key([sec '.' key]))=ini_unescape(val);
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function s=ini_unescape(s),s=strrep(s,'\\n',sprintf('\n'));s=strrep(s,'\\r',sprintf('\r'));s=strrep(s,'\\\\','\\');endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction

function v=cache_required(cache,name)
  if(!isfield(cache,name)),error('curvefit.family_global rerender: render_cache.mat missing variable %s',name);endif
  v=cache.(name);
endfunction

function s=cache_text(cache,name,def)
  if(!isfield(cache,name)),s=def;return;endif
  v=cache.(name);if(ischar(v)),s=strtrim(v);else s=def;endif
  if(isempty(s)),s=def;endif
endfunction

function name=resolved_binding(cfg,role,model_key,def)
  name=strtrim(ini_get(cfg,['bindings.' role],''));
  if(isempty(name)),name=strtrim(ini_get(cfg,model_key,def));endif
  if(isempty(name)),name=def;endif
endfunction

function [h,g,hname,gname]=presentation_view(x,f,xname,fname,orientation)
  if(strcmp(orientation,'family_by_x')),h=f;g=x;hname=fname;gname=xname;
  else h=x;g=f;hname=xname;gname=fname;endif
endfunction

function metrics=compute_group_metrics(g,y,pred,numeric_fn)
  groups=unique(g);n_group=numel(groups);
  metrics=struct('family_value',groups(:),'group_value',groups(:),'n',zeros(n_group,1),'sse',zeros(n_group,1), ...
                 'rmse',zeros(n_group,1),'mae',zeros(n_group,1),'max_abs_error',zeros(n_group,1),'r2',NaN(n_group,1));
  for k=1:n_group
    idx=find(g==groups(k));m=feval(numeric_fn,'residual_metrics',y(idx),pred(idx),struct());
    metrics.n(k)=m.n;metrics.sse(k)=m.sse;metrics.rmse(k)=m.rmse;
    metrics.mae(k)=m.mae;metrics.max_abs_error(k)=m.max_abs_error;metrics.r2(k)=m.r2;
  endfor
endfunction

function progress_start_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_start','file')!=2),return;endif
  try
    if(strcmp(mode,'determinate'))
      gxtxt_progress_start(stage,message,mode,total);
    else
      gxtxt_progress_start(stage,message,mode);
    endif
  catch
  end_try_catch
endfunction

function progress_stage_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_stage','file')!=2),return;endif
  try
    if(strcmp(mode,'determinate'))
      gxtxt_progress_stage(stage,message,mode,total);
    else
      gxtxt_progress_stage(stage,message,mode);
    endif
  catch
  end_try_catch
endfunction

function progress_update_safe(current,total,stage,message)
  if(exist('gxtxt_progress_update','file')!=2 || total<=0),return;endif
  try
    gxtxt_progress_update(current,total,stage,message);
  catch
  end_try_catch
endfunction

function progress_complete_safe(stage,message)
  if(exist('gxtxt_progress_complete','file')!=2),return;endif
  try
    gxtxt_progress_complete(stage,message);
  catch
  end_try_catch
endfunction

function progress_fail_safe(stage,message)
  if(exist('gxtxt_progress_fail','file')!=2),return;endif
  try
    gxtxt_progress_fail(stage,message);
  catch
  end_try_catch
endfunction
