function [x,f,y] = gxtxt_spice_read_named_csv3(path,xname,fname,yname)
% Read three named numeric columns from a canonical CSV/TSV/semicolon table.
  fid=fopen(path,'r'); if(fid<0), error('Cannot open validation dataset: %s',path); endif
  unwind_protect
    header=fgetl(fid);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  if(!ischar(header)), error('Validation dataset is empty: %s',path); endif
  counts=[numel(strfind(header,',')), numel(strfind(header,';')), numel(strfind(header,sprintf('\t')))];
  [~,di]=max(counts);
  if(di==2), delim=';'; elseif(di==3), delim=sprintf('\t'); else delim=','; endif
  names=strsplit(strtrim(header),delim);
  names=cellfun(@strip_token,names,'UniformOutput',false);
  ix=find(strcmp(names,xname),1); iff=find(strcmp(names,fname),1); iy=find(strcmp(names,yname),1);
  if(isempty(ix)||isempty(iff)||isempty(iy))
    error('Validation dataset missing required columns: %s, %s, %s',xname,fname,yname);
  endif
  data=dlmread(path,delim,1,0);
  if(columns(data)<max([ix iff iy])), error('Validation dataset row width does not match header'); endif
  x=data(:,ix); f=data(:,iff); y=data(:,iy);
endfunction

function s=strip_token(s)
  s=strtrim(s);
  if(numel(s)>=2 && s(1)=='"' && s(end)=='"'), s=s(2:end-1); endif
endfunction
