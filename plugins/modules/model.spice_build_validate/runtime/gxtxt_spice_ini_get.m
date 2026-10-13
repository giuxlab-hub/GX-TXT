function v = gxtxt_spice_ini_get(d,key,def)
  k=regexprep(key,'[^A-Za-z0-9_]','_');
  if(isempty(k) || !isletter(k(1))), k=['k_' k]; endif
  if(isfield(d,k)), v=d.(k); else v=def; endif
endfunction
