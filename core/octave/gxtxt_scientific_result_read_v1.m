% Bounded binary64 control/result envelope, paired with the public writer.
% Bulk scientific arrays and exact integers use managed binary transport v2.
% SPDX-License-Identifier: GPL-3.0-or-later
function result=gxtxt_scientific_result_read_v1(path)
  st=dir(path);if(numel(st)!=1||st.bytes>8*1024*1024),error('GXTXT:ScientificTransport:Size','Bounded result exceeds 8 MiB');endif
  addpath(fullfile(fileparts(mfilename('fullpath')),'io'));
  d=gxtxt_ini_read(path,true);
  if(!strcmp(get(d,'result.ok'),'1')),error('GXTXT:ScientificTransport:Result','Input is not a successful result envelope');endif
  count=0;result=read_struct(d,'result',0);
  function value=read_struct(d,section,depth)
    names=split_names(get(d,[section '.fields']));value=struct();
    for k=1:numel(names),value.(names{k})=read_node(d,[section '.' names{k}],depth+1);endfor
  endfunction
  function value=read_node(d,section,depth)
    count+=1;if(depth>16||count>65536),error('GXTXT:ScientificTransport:Size','Bounded result nesting/element limit exceeded');endif
    kind=get(d,[section '.type']);
    switch(kind)
      case 'struct',value=read_struct(d,section,depth);
      case 'cell'
        n=dimension(get(d,[section '.count']));value=cell(n,1);
        for k=1:n,value{k}=read_node(d,sprintf('%s.item%d',section,k),depth+1);endfor
      case 'string'
        raw=get(d,[section '.value']);encoding='plain';if(isKey(d,[section '.encoding'])),encoding=d([section '.encoding']);endif
        if(strcmp(encoding,'base64_utf8'))
          if(isempty(regexp(raw,'^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$','once'))&&!isempty(raw)),error('GXTXT:ScientificTransport:Encoding','Malformed Base64 string');endif
          % Java-free Octave core decoder accepts a byte vector shape.
          value='';if(!isempty(raw)),bytes=matlab.net.base64decode(raw);value=native2unicode(uint8(bytes),'UTF-8');endif
        elseif(strcmp(encoding,'plain')),value=raw;
        else,error('GXTXT:ScientificTransport:Encoding','Unknown string encoding');endif
      case 'boolean'
        raw=get(d,[section '.value']);if(!any(strcmp(raw,{'0','1'}))),error('GXTXT:ScientificTransport:Type','Invalid boolean');endif;value=strcmp(raw,'1');
      case 'number',value=number(get(d,[section '.value']));
      case {'vector','matrix'}
        raw=get(d,[section '.value']);parts={};if(!isempty(raw)),parts=strsplit(raw,';','collapsedelimiters',false);endif
        count+=numel(parts);if(count>65536),error('GXTXT:ScientificTransport:Size','Bounded result has too many elements');endif
        value=zeros(numel(parts),1);for k=1:numel(parts),value(k)=number(parts{k});endfor
        if(strcmp(kind,'matrix'))
          nr=dimension(get(d,[section '.rows']));nc=dimension(get(d,[section '.cols']));
          if(nr*nc!=numel(value)),error('GXTXT:ScientificTransport:Shape','Matrix dimensions differ from payload');endif
          value=reshape(value,nc,nr).';
        endif
      otherwise,error('GXTXT:ScientificTransport:Type','Unsupported bounded input node: %s',kind);
    endswitch
  endfunction
endfunction
function value=get(d,key)
  if(!isKey(d,key)),error('GXTXT:ScientificTransport:Descriptor','Missing bounded field %s',key);endif;value=d(key);
endfunction
function names=split_names(raw)
  names={};if(isempty(raw)),return;endif;names=strsplit(raw,';','collapsedelimiters',false);
  if(numel(names)>65536||numel(unique(names))!=numel(names)),error('GXTXT:ScientificTransport:Descriptor','Invalid bounded field list');endif
  for k=1:numel(names),if(isempty(regexp(names{k},'^[A-Za-z][A-Za-z0-9_]*$','once'))),error('GXTXT:ScientificTransport:Descriptor','Invalid bounded field identifier');endif;endfor
endfunction
function v=number(raw)
  if(isempty(regexp(raw,'^([+-]?(([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?|Inf)|NaN)$','once'))),error('GXTXT:ScientificTransport:Number','Malformed binary64 number');endif
  v=str2double(raw);
  if(!isfinite(v)&&!any(strcmp(raw,{'Inf','+Inf','-Inf','NaN'}))),error('GXTXT:ScientificTransport:Number','Numeric literal overflow');endif
endfunction
function v=dimension(raw)
  v=number(raw);if(!isfinite(v)||v<0||v!=fix(v)||v>65536),error('GXTXT:ScientificTransport:Shape','Invalid bounded dimension');endif
endfunction
