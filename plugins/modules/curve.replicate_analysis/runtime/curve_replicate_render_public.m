function curve_replicate_render_public(outdir,traces,results,D,has_family,x_name,family_name,y_name,cfg,config_path,operation)
% Replicate Curve Analysis v15.2 - public Plot Dataset delegation only.
% SPDX-License-Identifier: GPL-3.0-or-later
%
% No scientific result graphics are drawn in this module. The producer owns
% graph identity and Graph Series; plot.dataset owns all rendering.

  if(nargin<10 || isempty(config_path)),error('curve.replicate.analysis v15.2: runtime config path is required');endif
  if(nargin<11 || isempty(operation)),operation='render';endif
  if(!any(strcmp(operation,{'render','rerender'}))),error('curve.replicate.analysis v15.2: operation must be render or rerender');endif
  session=strtrim(ini_get(cfg,'runtime.session',''));
  if(isempty(session)),error('curve.replicate.analysis v15.2: Session path missing');endif
  ids={'curve.replicate.overlay','curve.replicate.consensus_uncertainty', ...
       'curve.replicate.uncertainty_components','curve.replicate.family_summary'};
  files={'01_replicate_overlay.png','02_consensus_uncertainty.png', ...
         '03_uncertainty_components.png','04_family_uncertainty_summary.png'};
  enabled=split_list(ini_get(cfg,'graph_provider.enabled',strjoin(ids,';')));
  for i=1:numel(ids)
    if(any(strcmp(enabled,ids{i})))
      provider_render(session,config_path,outdir,ids{i},files{i},operation);
    endif
  endfor
endfunction

function provider_render(session,config_path,outdir,graph_id,alias_file,operation)
  here=fileparts(mfilename('fullpath'));
  bridge=fullfile(here,'curve_replicate_plot_v152_bridge.tcl');
  if(exist(bridge,'file')!=2),error('curve.replicate.analysis v15.2: graphics bridge missing: %s',bridge);endif
  args={bridge,char(session),char(config_path),char(outdir),char(graph_id),char(alias_file),char(operation)};
  [in_fid,out_fid,pid]=popen2('tclsh',args);
  fclose(in_fid);
  response=gxtxt_persistent_bridge_readline(out_fid,pid);
  fclose(out_fid);
  [~,status]=waitpid(pid);
  if(!ischar(response) || isempty(strtrim(response)))
    error('curve.replicate.analysis v15.2: empty Plot Dataset bridge response for %s',graph_id);
  endif
  response=strtrim(response);
  parts=strsplit(response,sprintf('\t'),'collapsedelimiters',false);
  if(status!=0 || isempty(parts) || strcmp(parts{1},'ERROR'))
    msg=response;
    if(numel(parts)>1 && strcmp(parts{1},'ERROR')),msg=decode_b64(parts{2});endif
    error('curve.replicate.analysis v15.2: %s',msg);
  endif
  if(!strcmp(parts{1},'RESULT') || numel(parts)<2)
    error('curve.replicate.analysis v15.2: invalid Plot Dataset bridge response: %s',response);
  endif
  artifact=decode_b64(parts{2});
  if(exist(artifact,'file')!=2),error('curve.replicate.analysis v15.2: producer graph artifact missing: %s',artifact);endif
endfunction

function s=decode_b64(v)
  if(isempty(v)),s='';return;endif
  s=char(matlab.net.base64decode(v));s=s(:)';
endfunction
function a=split_list(raw),raw=strrep(raw,',',';');if(isempty(strtrim(raw))),a={};return;endif;a=strsplit(raw,';');a=cellfun(@strtrim,a,'UniformOutput',false);a=a(!cellfun(@isempty,a));endfunction
function k=make_key(s),k=regexprep(s,'[^A-Za-z0-9_]','_');if(isempty(k)||!isletter(k(1))),k=['k_' k];endif;endfunction
function v=ini_get(d,key,def),k=make_key(key);if(isfield(d,k)),v=d.(k);else v=def;endif;endfunction
