% SPDX-License-Identifier: GPL-3.0-or-later
% Public RFC4180-ish single-line CSV splitter used by table streaming helpers.
function fields=gxtxt_csv_split_line(line,delimiter)
  if(nargin<2||isempty(delimiter)),delimiter=',';endif
  if(numel(delimiter)!=1),error('GXTXT:CSV','Delimiter must be one character');endif
  % Most scientific tables are unquoted numeric rows. Use Octave's native
  % splitter for them; retain the quoted-field parser for RFC4180 cases.
  if(isempty(strfind(line,'"')))
    fields=strsplit(line,delimiter,'collapsedelimiters',false);
    return;
  endif
  fields={};buf='';quoted=false;i=1;
  while(i<=length(line))
    c=line(i);
    if(quoted)
      if(c=='"')
        if(i<length(line)&&line(i+1)=='"'),buf(end+1)='"';i+=2;continue;else quoted=false;i+=1;continue;endif
      else buf(end+1)=c;i+=1;continue;endif
    else
      if(c==delimiter),fields{end+1}=buf;buf='';i+=1;continue;
      elseif(c=='"'&&isempty(buf)),quoted=true;i+=1;continue;
      else buf(end+1)=c;i+=1;continue;endif
    endif
  endwhile
  if(quoted),error('GXTXT:CSV','Unterminated quoted CSV field');endif
  fields{end+1}=buf;
endfunction
