function d = gxtxt_spice_read_ini(path)
% Read a simple GX-TXT INI file into flattened section_key fields.
  d=struct(); sec='';
  fid=fopen(path,'r');
  if(fid<0), error('Cannot open INI: %s',path); endif
  unwind_protect
    while(true)
      line=fgetl(fid); if(!ischar(line)), break; endif
      line=strtrim(line);
      if(isempty(line) || line(1)==';' || line(1)=='#'), continue; endif
      tok=regexp(line,'^\[(.+)\]$','tokens','once');
      if(!isempty(tok)), sec=tok{1}; continue; endif
      eq=find(line=='=',1); if(isempty(eq)), continue; endif
      key=strtrim(line(1:eq-1)); val=line(eq+1:end);
      d.(make_key([sec '.' key]))=ini_unescape(val);
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
endfunction

function k=make_key(s)
  k=regexprep(s,'[^A-Za-z0-9_]','_');
  if(isempty(k) || !isletter(k(1))), k=['k_' k]; endif
endfunction

function s=ini_unescape(s)
  s=strrep(s,'\\n',sprintf('\n'));
  s=strrep(s,'\\r',sprintf('\r'));
  s=strrep(s,'\\\\','\\');
endfunction
