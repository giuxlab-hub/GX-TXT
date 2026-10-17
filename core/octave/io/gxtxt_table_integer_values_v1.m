function values=gxtxt_table_integer_values_v1(raw,dtype)
% Exact decimal integer conversion shared by Table Stream and row predicates.
% Floating input outside its exact integer range is never guessed.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!any(strcmp(dtype,{'int8','uint8','int16','uint16','int32','uint32','int64','uint64','bool'})))
    error('GXTXT:TableStream','Expected an integer scientific dtype');
  endif
  boolean=strcmp(dtype,'bool');if(boolean),target='uint8';else target=dtype;endif
  if(ischar(raw)),raw={raw};endif
  if(isnumeric(raw)||islogical(raw))
    if(isfloat(raw)&&any(!isfinite(raw(:))|raw(:)!=fix(raw(:))|abs(raw(:))>flintmax(class(raw))))
      error('GXTXT:TableStream','Ambiguous floating integer identity; supply exact decimal text or a typed integer');
    endif
    if(boolean),low=0;high=1;else low=intmin(dtype);high=intmax(dtype);endif
    if(any(raw(:)<low|raw(:)>high)),error('GXTXT:TableStream','Integer value is outside dtype %s',dtype);endif
    values=cast(raw,target);
  elseif(iscell(raw))
    values=zeros(size(raw),target);
    for i=1:numel(raw)
      text=raw{i};if(!ischar(text)||isempty(text)),error('GXTXT:TableStream','Integer identity needs decimal text');endif
      negative=text(1)=='-';if(negative||text(1)=='+'),text=text(2:end);endif
      if(isempty(text)||any(text<'0'|text>'9')),error('GXTXT:TableStream','Integer identity needs exact decimal digits');endif
      if(boolean),limit=uint64(1);unsigned=true;else limit=uint64(intmax(target));unsigned=strncmp(target,'uint',4);endif
      if(negative&&unsigned),error('GXTXT:TableStream','Negative unsigned integer identity');endif
      if(negative),limit+=uint64(1);endif
      magnitude=uint64(0);ten=uint64(10);
      for k=1:numel(text)
        digit=uint64(text(k)-'0');
        if(digit>limit||magnitude>idivide(limit-digit,ten,'floor')),error('GXTXT:TableStream','Integer value is outside dtype %s',dtype);endif
        magnitude=magnitude*ten+digit;
      endfor
      if(negative&&magnitude==limit),values(i)=intmin(target);
      elseif(negative),values(i)=-cast(magnitude,target);
      else values(i)=cast(magnitude,target);endif
    endfor
  else error('GXTXT:TableStream','Unsupported integer representation');endif
  if(boolean),values=logical(values);endif
endfunction
