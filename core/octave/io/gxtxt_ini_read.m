% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT shared INI reader for trusted framework/plugin descriptors and runtime files.
function d = gxtxt_ini_read(path,exact_keys=false)
  if(exact_keys),d=containers.Map('KeyType','char','ValueType','char');else,d=struct();endif
  sec = '';
  fid = fopen(path,'r');
  if (fid < 0), error('GXTXT:INI','Cannot open INI file: %s',path); endif
  unwind_protect
    while (true)
      line = fgetl(fid);
      if (!ischar(line)), break; endif
      line = strtrim(line);
      if (isempty(line) || line(1)==';' || line(1)=='#'), continue; endif
      tok = regexp(line,'^\[(.+)\]$','tokens','once');
      if (!isempty(tok)), sec = strtrim(tok{1}); continue; endif
      eq = find(line=='=',1);
      if (isempty(eq)), continue; endif
      key = strtrim(line(1:eq-1));
      val = line(eq+1:end);
      fullkey = key;
      if (!isempty(sec)), fullkey = [sec '.' key]; endif
      if(exact_keys)
        if(isKey(d,fullkey)),error('GXTXT:INI','Duplicate exact INI key: %s',fullkey);endif
        d(fullkey)=gxtxt_ini_unescape(val);
      else,d.(gxtxt_ini_key(fullkey)) = gxtxt_ini_unescape(val);endif
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function k = gxtxt_ini_key(s)
  k = regexprep(s,'[^A-Za-z0-9_]','_');
  if (isempty(k) || !isletter(k(1))), k = ['k_' k]; endif
endfunction

function s = gxtxt_ini_unescape(s)
  % Protect escaped backslashes before decoding control sequences. Otherwise a
  % literal "\\n" value is indistinguishable from an encoded newline.
  slash = char(92);
  placeholder = char(1);
  s = strrep(s,[slash slash],placeholder);
  s = strrep(s,[slash 'n'],sprintf('\n'));
  s = strrep(s,[slash 'r'],sprintf('\r'));
  s = strrep(s,placeholder,slash);
endfunction
