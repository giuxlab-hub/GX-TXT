% SPDX-License-Identifier: GPL-3.0-or-later
% Validate the standard cache envelope and optional expected metadata.
% expected may contain module_id, module_version, definition_id,
% definition_version, source_fingerprint, analysis_fingerprint.
function report = gxtxt_render_cache_validate(cache, expected)
  if(nargin<2),expected=struct();endif
  errors={};
  if(!isstruct(cache)),errors{end+1}='cache_not_struct';report=finish(errors);return;endif
  if(!isfield(cache,'meta')||!isstruct(cache.meta)),errors{end+1}='missing_meta';report=finish(errors);return;endif
  if(!isfield(cache.meta,'api_version')||cache.meta.api_version!=1),errors{end+1}='unsupported_api_version';endif
  f=fieldnames(expected);
  for i=1:numel(f)
    k=f{i}; if(!isfield(cache.meta,k)),errors{end+1}=['missing_' k];continue;endif
    if(!same_value(cache.meta.(k),expected.(k))),errors{end+1}=['mismatch_' k];endif
  endfor
  report=finish(errors);
endfunction
function r=finish(e),r=struct('valid',isempty(e),'errors',{e});endfunction
function tf=same_value(a,b),if(isnumeric(a)&&isnumeric(b)),tf=isequal(a,b);else tf=strcmp(char(a),char(b));endif;endfunction
