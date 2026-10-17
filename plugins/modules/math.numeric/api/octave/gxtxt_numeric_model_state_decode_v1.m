% Decode saved model JSON without RapidJSON's approximate decimal conversion.
% JSON still owns all syntax/structure; numeric slots are small exact indices.
% SPDX-License-Identifier: GPL-3.0-or-later
function model=gxtxt_numeric_model_state_decode_v1(text)
  if(!(ischar(text)||isa(text,'uint8'))||!isvector(text)||isempty(text)),error('GXTXT:Numeric:ModelState','Saved model requires JSON text or exact uint8 bytes');endif
  if(exist('gxtxt_numeric_ceres_native','file')==3)
    indexed=gxtxt_numeric_ceres_native('model_json_tokens',text);
    model=restore(jsondecode(indexed.syntax),indexed.numbers,0);return;
  endif
  if(isa(text,'uint8')),text=native2unicode(text(:).','UTF-8');endif
  if(!ischar(text)||numel(text)>2*1024*1024),error('GXTXT:Numeric:Export','Saved model JSON exceeds 2 MiB');endif
  pattern='"(?:[^"\\]|\\.)*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|[{}\[\],:]|true|false|null';
  [starts,ends,tokens]=regexp(text,pattern,'start','end','match');
  values=zeros(1,numel(tokens));count=0;last=0;
  for k=1:numel(tokens)
    prefix=text(last+1:starts(k)-1);
    if(!isempty(strtrim(prefix))),error('GXTXT:Numeric:Export','Malformed saved model JSON');endif
    last=ends(k);token=tokens{k};
    if(token(1)=='-'||(token(1)>='0'&&token(1)<='9'))
      value=sscanf(token,'%f');
      if(!isscalar(value)||!isfinite(value)),error('GXTXT:Numeric:Export','Saved model number is outside binary64');endif
      count+=1;values(count)=value;tokens{k}=sprintf('%d',count);
    endif
    tokens{k}=[prefix,tokens{k}];
  endfor
  if(!isempty(strtrim(text(last+1:end)))),error('GXTXT:Numeric:Export','Malformed saved model JSON');endif
  model=restore(jsondecode(strjoin(tokens,'')),values(1:count),0);
endfunction
function value=restore(value,numbers,depth)
  if(depth>16),error('GXTXT:Numeric:Export','Saved model JSON nesting exceeds 16');endif
  if(isstruct(value))
    fields=fieldnames(value);
    for k=1:numel(value),for j=1:numel(fields),key=fields{j};value(k).(key)=restore(value(k).(key),numbers,depth+1);endfor;endfor
  elseif(iscell(value))
    for k=1:numel(value),value{k}=restore(value{k},numbers,depth+1);endfor
  elseif(isnumeric(value)&&!isempty(value))
    finite=isfinite(value);indices=value(finite);
    if(any(indices<1)||any(indices>numel(numbers))||any(indices!=fix(indices))),error('GXTXT:Numeric:Export','Invalid saved number slot');endif
    value(finite)=numbers(indices);
  endif
endfunction
