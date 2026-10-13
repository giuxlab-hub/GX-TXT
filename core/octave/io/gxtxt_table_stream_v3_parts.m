% SPDX-License-Identifier: GPL-3.0-or-later
function parts=gxtxt_table_stream_v3_parts(line)
  parts=strsplit(line,sprintf('\t'),'collapsedelimiters',false);
endfunction
