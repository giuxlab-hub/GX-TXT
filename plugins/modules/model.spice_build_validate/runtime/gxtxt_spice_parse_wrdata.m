function values = gxtxt_spice_parse_wrdata(path,expected_count)
% Parse a one-operating-point ngspice wrdata file.
% Supports wr_singlescale output (scale + N values) and the default paired
% scale/value form (2*N values).
  if(exist(path,'file')!=2), error('ngspice data file not found: %s',path); endif
  fid=fopen(path,'r'); if(fid<0), error('Cannot open ngspice data file: %s',path); endif
  best=[];
  unwind_protect
    while(true)
      line=fgetl(fid); if(!ischar(line)), break; endif
      nums=sscanf(line,'%f');
      if(numel(nums)>=expected_count), best=nums(:).'; endif
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  if(isempty(best)), error('No numeric ngspice data row found in %s',path); endif
  n=numel(best);
  if(n==expected_count)
    values=best;
  elseif(n==expected_count+1)
    values=best(2:end);
  elseif(n==2*expected_count)
    values=best(2:2:end);
  else
    error('Unexpected ngspice wrdata column count in %s: got %d, expected %d (+ optional scale)',path,n,expected_count);
  endif
  values=values(:);
  if(any(!isfinite(values))), error('Non-finite ngspice result in %s',path); endif
endfunction
