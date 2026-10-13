% SPDX-License-Identifier: GPL-3.0-or-later
% Fingerprint a trusted local source file for cache provenance.
function fp = gxtxt_render_cache_file_fingerprint(path)
  if(exist(path,'file')!=2),error('GXTXT:RenderCache','source file not found: %s',path);endif
  fid=fopen(path,'rb');if(fid<0),error('GXTXT:RenderCache','cannot open source file: %s',path);endif
  unwind_protect
    b=fread(fid,Inf,'uint8=>uint8')';
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  try
    fp=hash('sha256',char(b));
  catch
    % Binary NUL handling differs between Octave builds.  Hex encoding keeps
    % the hash deterministic at the cost of temporary expansion.
    fp=hash('sha256',reshape(dec2hex(b,2).',1,[]));
  end_try_catch
endfunction
