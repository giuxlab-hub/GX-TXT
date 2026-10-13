function stamp=tdfft_source_stamp(path)
% Cheap cache invalidation stamp for a trusted local canonical source path.
% Avoid hashing a very large Dataset merely to decide whether plots can be rerendered.
% SPDX-License-Identifier: GPL-3.0-or-later
  path=strtrim(path);if(isempty(path)),stamp='path:none';return;endif
  try
    st=stat(path);stamp=sprintf('path=%s;size=%.17g;mtime=%.17g',path,st.size,st.mtime);
  catch
    stamp=['path=' path ';stat=unavailable'];
  end_try_catch
endfunction
