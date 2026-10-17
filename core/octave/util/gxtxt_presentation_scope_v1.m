function lifetime=gxtxt_presentation_scope_v1(session)
% Keep the read-only CORE scientific presentation service alive for one caller-owned scope.
% Reuse active Script Jobs without taking ownership of their bridge.
% SPDX-License-Identifier: GPL-3.0-or-later
  global GXTXT_SCRIPT_BRIDGE_STATE;
  if(nargin<1),session='';endif
  if(!ischar(session)||rows(session)>1||any(session==char(10))||any(session==char(13))||any(session==char(0))),error('GXTXT:Coordinates','Session binding must be a single existing directory path');endif
  if(!isempty(session))
    if(exist(session,'dir')!=7),error('GXTXT:Coordinates','Bound coordinate Session is unavailable');endif
    session=canonicalize_file_name(session);
  endif
  lifetime=[];
  if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE)&&isfield(GXTXT_SCRIPT_BRIDGE_STATE,'active')&&GXTXT_SCRIPT_BRIDGE_STATE.active)
    if(!isempty(session)&&(!isfield(GXTXT_SCRIPT_BRIDGE_STATE,'statistics_session')||!strcmp(GXTXT_SCRIPT_BRIDGE_STATE.statistics_session,session)))
      error('GXTXT:Coordinates','Cannot bind an existing Bridge to a different Session; Jobs retain their own Session context');
    endif
    gxtxt_api_require({'DATASET_METADATA_API_v1','STATISTICAL_RESULT_SEMANTICS_API_v1'});
    if(!gxtxt_api_has_operation('DATASET_METADATA_API_v1','coordinate_snapshot_affine_plan'))
      error('GXTXT:Coordinates','Active Bridge does not expose coordinate presentation');
    endif
    return;
  endif
  config=tempname();oldmask=umask(077);fid=fopen(config,'w');umask(oldmask);
  if(fid<0),error('GXTXT:Coordinates','Cannot create private CORE service configuration');endif
  fprintf(fid,'[runtime]\ncore_service=scientific_presentation\n');
  if(!isempty(session)),fprintf(fid,'session=%s\n',session);endif
  fclose(fid);
  try
    gxtxt_script_bridge_start(config,struct('script_name','CORE scientific presentation','script_sha256','not-a-script-job','arguments_raw',''));
  catch err,unlink(config);rethrow(err);end_try_catch
  GXTXT_SCRIPT_BRIDGE_STATE.statistics_session=session;
  owner_pid=GXTXT_SCRIPT_BRIDGE_STATE.pid;owner_scope=GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope;
  lifetime=onCleanup(@() close_owned(config,owner_pid,owner_scope));
endfunction
function close_owned(config,owner_pid,owner_scope)
  global GXTXT_SCRIPT_BRIDGE_STATE;
  unwind_protect
    if(isstruct(GXTXT_SCRIPT_BRIDGE_STATE)&&isfield(GXTXT_SCRIPT_BRIDGE_STATE,'active')&&GXTXT_SCRIPT_BRIDGE_STATE.active&& ...
       GXTXT_SCRIPT_BRIDGE_STATE.pid==owner_pid&&strcmp(GXTXT_SCRIPT_BRIDGE_STATE.buffer_scope,owner_scope))
      gxtxt_script_bridge_stop();
    endif
  unwind_protect_cleanup
    if(exist(config,'file')==2),unlink(config);endif
  end_unwind_protect
endfunction
