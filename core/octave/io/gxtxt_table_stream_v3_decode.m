% SPDX-License-Identifier: GPL-3.0-or-later
function text=gxtxt_table_stream_v3_decode(encoded)
  if(isempty(encoded)),text='';return;endif
  text=char(matlab.net.base64decode(encoded));
  text=text(:)';
endfunction
