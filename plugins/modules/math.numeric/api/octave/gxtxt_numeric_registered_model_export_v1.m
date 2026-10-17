% Source-preserving adaptation for independent registered model functions.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_registered_model_export_v1(model,options)
  required={'source','source_sha256','binding_sha256','language','entrypoint','parameters','parameter_ids'};
  if(!all(isfield(model,required))||!ischar(model.source)||isempty(model.source)||numel(unicode2native(model.source,'UTF-8'))>1048576)
    error('GXTXT:Numeric:Export','Registered export needs its bounded exact UTF-8 executable source');
  endif
  bytes=unicode2native(model.source,'UTF-8');
  if(!strcmp(hash('sha256',char(bytes)),model.source_sha256)||isempty(regexp(model.binding_sha256,'^[0-9a-f]{64}$','once')))
    error('GXTXT:Numeric:Export','Registered source or declaration identity differs from its saved receipt');
  endif
  if(!any(strcmp(model.language,{'Python','Octave'}))||isempty(regexp(model.entrypoint,'^[A-Za-z][A-Za-z0-9_]{0,63}$','once')))
    error('GXTXT:Numeric:Export','Registered export needs the original language and valid entrypoint');
  endif
  if(!isnumeric(model.parameters)||!isreal(model.parameters)||isempty(model.parameters)||numel(model.parameters)>128||any(!isfinite(model.parameters(:)))|| ...
     !iscellstr(model.parameter_ids)||numel(model.parameter_ids)!=numel(model.parameters)||numel(unique(model.parameter_ids))!=numel(model.parameters))
    error('GXTXT:Numeric:Export','Registered parameter values and canonical identities differ');
  endif
  if(!isfield(options,'parameter_ids')||!isfield(options,'parameter_values')||!isequal(model.parameters(:),options.parameter_values(:))|| ...
     !isequal(reshape(model.parameter_ids,1,[]),reshape(options.parameter_ids,1,[])))
    error('GXTXT:Numeric:Export','Accepted parameter identities or values differ from the frozen registered model');
  endif
  if(!isfield(options,'parameter_units')||!iscellstr(options.parameter_units)||numel(options.parameter_units)!=numel(model.parameters))
    error('GXTXT:Numeric:Export','Registered export needs one declared unit per canonical parameter');
  endif
  if(!isempty(regexpi(model.source,'\<gxtxt\>|\<gxtxt_[A-Za-z_]|::GX::','once')))
    error('GXTXT:Numeric:Export','Independent registered export refuses explicit GX-TXT runtime dependencies in the saved source');
  endif
  spec=struct('language',model.language,'entrypoint',model.entrypoint,'source_sha256',model.source_sha256,'source_hex',lower(reshape(dec2hex(bytes,2).',1,[])));
  dependencies=[model.language,' runtime and all imports/packages used by the saved executable source'];
  metadata=struct('executable_language',model.language,'executable_entrypoint',model.entrypoint,'executable_source_sha256',model.source_sha256, ...
    'declaration_sha256',model.binding_sha256,'evaluation_adapter','Exact original source in an isolated external process on each batched call; no language translation', ...
    'python_dependencies',['Python3, NumPy; ',dependencies,'; octave-cli on PATH for Octave models'], ...
    'octave_dependencies',['GNU Octave, Debian timeout utility; ',dependencies,'; python3 and NumPy on PATH for Python models'], ...
    'source_dependency_policy','Source imports, external files, environment and nondeterministic state are not captured; independent evaluation requires a deterministic model of parameters and predictors', ...
    'execution_policy','Caller explicitly executes its trusted retained model source; 120 second runtime bound; private temporary binary64 input/output files are removed', ...
    'equation_note','Registered executable function notation references the exact source SHA; no unverified symbolic translation is claimed', ...
    'original_source_license','Original source notices are preserved verbatim; generated adapter license does not relicense user model source');
  out=struct('spec_json',jsonencode(spec),'metadata',metadata);
endfunction
