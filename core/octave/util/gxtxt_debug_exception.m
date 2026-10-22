function gxtxt_debug_exception(native_error, snapshot, source_sha)
% Preserve the actual caught Octave error before unwind/rethrow alters context.
% Existing managed Debug Job sideband only; not a second execution/error engine.
% SPDX-License-Identifier: GPL-3.0-or-later
  directory = getenv('GXTXT_DEBUG_DIRECTORY');
  token = getenv('GXTXT_DEBUG_TOKEN');
  if (isempty(directory) || isempty(token)), return; endif
  if (!isstruct(native_error) || !isfield(native_error,'message') || !isfield(native_error,'stack')), return; endif
  frames = native_error.stack;
  if (numel(frames)>32), frames=frames(1:32); endif
  identifier='';if (isfield(native_error,'identifier')),identifier=native_error.identifier;endif
  record=struct('schema','gxtxt.native_octave_exception.v1','token',token, ...
    'source',snapshot,'source_sha256',source_sha,'message',native_error.message, ...
    'identifier',identifier,'stack',frames,'origin','native_caught_error');
  temporary=fullfile(directory,'exception.pending');
  destination=fullfile(directory,'exception.json');
  fd=fopen(temporary,'w');
  if (fd<0),error('Cannot preserve managed native exception');endif
  unwind_protect
    fputs(fd,jsonencode(record));
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
  [ok,message]=movefile(temporary,destination,'f');if (!ok),error(message);endif
endfunction
