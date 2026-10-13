function gxtxt_ir_waveform_rerender_main(args)
  try
    gxtxt_ir_waveform_rerender_main_impl(args);
  catch err
    try, gxtxt_progress_fail('failed','IR waveform rerender failed; see log for details'); catch, end_try_catch
    rethrow(err);
  end_try_catch
endfunction

function gxtxt_ir_waveform_rerender_main_impl(args)
% SPDX-License-Identifier: GPL-3.0-or-later
  config_path=arg_value(args,'--config','');cache_path=arg_value(args,'--cache','');
  if(isempty(config_path)||isempty(cache_path)),error('--config and --cache are required');endif
  cfg=read_ini(config_path);outdir=ini_get(cfg,'runtime.output_dir','');if(isempty(outdir)),error('runtime.output_dir missing');endif
  gxtxt_progress_start('loading_cache','Loading IR render cache','indeterminate');
  S=load(cache_path);
  req={'overview_t_ms','overview_vMin','overview_vMax','carrier_t_us','carrier_v','logic_t_ms','logic_y','burstDuration','spaceDuration','nBursts','Fcarrier','signal_name'};
  for k=1:numel(req),if(!isfield(S,req{k})),error('render cache missing %s',req{k});endif;endfor
  if(isfield(S,'analog_chain')),A=S.analog_chain;else A=struct('name',{});endif
  gxtxt_progress_stage('rendering','Rendering configured IR graphs','indeterminate');
  session=strtrim(ini_get(cfg,'runtime.session',''));
  if(!isempty(session)&&exist(fullfile(session,'metadata','manifest.ini'),'file')==2)
    S.analog_chain=A;
    D=gxtxt_ir_publish_plots(session,ini_get(cfg,'dataset.id',''),S);
    gxtxt_ir_render_public(outdir,cfg,S,D);
  endif
  gxtxt_progress_complete('done','IR waveform rerender completed');fprintf('[gxtxt.ir_waveform] rerender completed\n');
endfunction

function v=arg_value(args,key,def),v=def;for k=1:numel(args)-1,if(strcmp(args{k},key)),v=args{k+1};return;endif;endfor;endfunction
function d=read_ini(path),d=struct();sec='';fid=fopen(path,'r');if(fid<0),error('Cannot open INI: %s',path);endif;unwind_protect;while(true),line=fgetl(fid);if(!ischar(line)),break;endif;line=strtrim(line);if(isempty(line)||line(1)==';'||line(1)=='#'),continue;endif;tok=regexp(line,'^\[(.+)\]$','tokens','once');if(!isempty(tok)),sec=tok{1};continue;endif;eq=find(line=='=',1);if(isempty(eq)),continue;endif;key=strtrim(line(1:eq-1));val=line(eq+1:end);d.(make_key([sec '.' key]))=ini_unescape(val);endwhile;unwind_protect_cleanup;fclose(fid);end_unwind_protect;endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function s=ini_unescape(s),s=strrep(s,'\\n',sprintf('\n'));s=strrep(s,'\\r',sprintf('\r'));s=strrep(s,'\\\\','\\');endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
function a=parse_list(s),s=strrep(s,',',';');if(isempty(strtrim(s))),a={};else a=strsplit(s,';');a=cellfun(@strtrim,a,'UniformOutput',false);endif;endfunction
