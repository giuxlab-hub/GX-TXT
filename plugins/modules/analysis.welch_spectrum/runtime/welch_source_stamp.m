function stamp=welch_source_stamp(path)
% SPDX-License-Identifier: GPL-3.0-or-later
  path=strtrim(path);if(isempty(path)),stamp='path:none';return;endif
  try st=stat(path);stamp=sprintf('path=%s;size=%.17g;mtime=%.17g',path,st.size,st.mtime);catch stamp=['path=' path ';stat=unavailable'];end_try_catch
endfunction
