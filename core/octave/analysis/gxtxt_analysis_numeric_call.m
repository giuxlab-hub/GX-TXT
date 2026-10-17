% Resolve the protected public numerical binding for shared analysis code.
% SPDX-License-Identifier: GPL-3.0-or-later
function result=gxtxt_analysis_numeric_call(varargin)
  persistent entry fn;
  if(isempty(entry))
    root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    owner=fullfile(root,'plugins','modules','math.numeric');
    descriptor=gxtxt_ini_read(fullfile(owner,'module.ini'));
    if(!strcmp(gxtxt_ini_get(descriptor,'meta.id',''),'math.numeric')||!strcmp(gxtxt_ini_get(descriptor,'public_api.NUMERIC_API_v1.api_version',''),'1'))
      error('GXTXT:AnalysisExpression','Protected NUMERIC_API_v1 provider descriptor is invalid');
    endif
    relative=gxtxt_ini_get(descriptor,'public_api.NUMERIC_API_v1.octave_entrypoint','');
    fn=gxtxt_ini_get(descriptor,'public_api.NUMERIC_API_v1.octave_function','');
    entry=canonicalize_file_name(fullfile(owner,relative));
    if(isempty(entry)||isempty(regexp(fn,'^[A-Za-z][A-Za-z0-9_]*$','once'))||!strncmp(entry,[canonicalize_file_name(owner) filesep],length(canonicalize_file_name(owner))+1))
      error('GXTXT:AnalysisExpression','NUMERIC_API_v1 public Octave binding is unavailable or outside its owner');
    endif
    addpath(fileparts(entry));
  endif
  if(!strcmp(canonicalize_file_name(which(fn)),entry)),error('GXTXT:AnalysisExpression','NUMERIC_API_v1 binding is shadowed on the Octave path');endif
  result=feval(fn,varargin{:});
endfunction
