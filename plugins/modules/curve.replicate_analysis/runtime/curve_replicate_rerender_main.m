function curve_replicate_rerender_main(args)
% GX-TXT Replicate Curve Analysis - cache-only rerender.
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');
  if(isempty(config_path)),error('curve.replicate_analysis rerender: --config is required');endif
  cfg=read_ini(config_path); outdir=strtrim(ini_get(cfg,'runtime.output_dir',''));
  if(isempty(outdir)),error('curve.replicate_analysis rerender: runtime.output_dir missing');endif
  progress_start_safe('loading_cache','Loading replicate-analysis render cache','indeterminate',0);
  try
    cache_path=strtrim(ini_get(cfg,'render_cache_api.path',''));
    if(isempty(cache_path)),cache_path=fullfile(outdir,'render_cache.mat');endif
    if(exist(cache_path,'file')!=2),error('curve.replicate_analysis rerender: render_cache.mat not found: %s',cache_path);endif
    c=load(cache_path);
    required={'render_traces','render_results','D','has_family','x_name','family_name','y_name'};
    for i=1:numel(required),if(!isfield(c,required{i})),error('curve.replicate_analysis rerender: cache missing %s',required{i});endif;endfor
    if(!isempty(strtrim(ini_get(cfg,'runtime.session',''))))
      curve_replicate_render_public(outdir,c.render_traces,c.render_results,c.D,c.has_family,c.x_name,c.family_name,c.y_name,cfg,config_path,'rerender');
    endif
    progress_complete_safe('completed','Replicate curve rerender completed');
  catch err
    progress_fail_safe('failed','Replicate curve rerender failed; see log for details'); rethrow(err);
  end_try_catch
endfunction
function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function d=read_ini(path)
  d=struct();sec='';fid=fopen(path,'r');if(fid<0),error('Cannot open INI: %s',path);endif
  unwind_protect
    while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif
      tok=regexp(line,'^\[(.+)\]$','tokens','once');if(!isempty(tok)),sec=tok{1};continue;endif
      eq=find(line=='=',1);if(isempty(eq)),continue;endif;key=strtrim(line(1:eq-1));val=line(eq+1:end);d.(make_key([sec '.' key]))=ini_unescape(val);
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function s=ini_unescape(s),s=strrep(s,'\\n',sprintf('\n'));s=strrep(s,'\\r',sprintf('\r'));s=strrep(s,'\\\\','\\');endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
function progress_start_safe(stage,message,mode,total)
  if(exist('gxtxt_progress_start','file')!=2),return;endif
  try if(strcmp(mode,'determinate')),gxtxt_progress_start(stage,message,mode,total);else gxtxt_progress_start(stage,message,mode);endif;catch;end_try_catch
endfunction
function progress_complete_safe(stage,message),if(exist('gxtxt_progress_complete','file')!=2),return;endif;try gxtxt_progress_complete(stage,message);catch;end_try_catch;endfunction
function progress_fail_safe(stage,message),if(exist('gxtxt_progress_fail','file')!=2),return;endif;try gxtxt_progress_fail(stage,message);catch;end_try_catch;endfunction
