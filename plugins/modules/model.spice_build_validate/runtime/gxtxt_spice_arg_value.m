function v = gxtxt_spice_arg_value(args,key,def)
  v=def;
  for k=1:max(0,numel(args)-1)
    if(strcmp(args{k},key)), v=args{k+1}; return; endif
  endfor
endfunction
