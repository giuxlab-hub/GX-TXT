function fields=gxtxt_publication_v2_block(values,shape,resource_scope)
% Internal Publication v2 transport block. Public helper signatures remain stable.
 if(nargin<2||isempty(shape)),shape=numel(values);endif
 if(isnumeric(shape)),shape_text=strjoin(arrayfun(@num2str,shape,'uniformoutput',false),';');else shape_text=char(shape);endif
 dims=parse_shape_local(shape_text); expected=prod(dims);
 if(isempty(dims)),expected=1;endif
 if(numel(values)!=expected),error('GXTXT:Publication','Value count mismatch: expected %d, received %d',expected,numel(values));endif
 if(iscell(values)||ischar(values))
   if(iscell(values)),cells=values(:)';else cells={values};endif
   encoded=cellfun(@gxtxt_publication_v2_encode,cells,'uniformoutput',false);
   fields={'TEXT','string','none',shape_text,strjoin(encoded,',')};
   return
 endif
 if(!(isnumeric(values)||islogical(values))),error('GXTXT:Publication','Unsupported publication value type');endif
 dtype=dtype_local(values);
 if(!isreal(values)),error('GXTXT:Publication','Complex Dataset publication requires a supported complex schema');endif
 if(nargin>=3&&!isempty(resource_scope))
   d=gxtxt_binary_resource_v1('write',resource_scope,values);
   physical=strjoin(arrayfun(@num2str,d.shape,'uniformoutput',false),';');
   payload=strjoin({num2str(d.version),d.order,d.resource_id,physical,num2str(d.count),num2str(d.byte_count)},'|');
   fields={'RESOURCE',d.dtype,d.endian,shape_text,gxtxt_publication_v2_encode(payload)};return;
 endif
 flat=values(:);
 if(islogical(flat)),bytes=uint8(flat);else
   [~,~,machine_endian]=computer();
   if(strcmpi(machine_endian,'B')),flat=swapbytes(flat);endif
   bytes=typecast(flat,'uint8');
 endif
 payload=char(matlab.net.base64encode(bytes));payload=payload(:)';
 fields={'BINARY',dtype,'little',shape_text,payload};
endfunction

function dtype=dtype_local(values)
 c=class(values);
 switch(c)
  case 'double',dtype='float64';
  case 'single',dtype='float32';
  case {'int8','int16','int32','int64','uint8','uint16','uint32','uint64'},dtype=c;
  case 'logical',dtype='bool';
  otherwise,error('GXTXT:Publication','Unsupported numeric transport class %s',c);
 endswitch
endfunction

function dims=parse_shape_local(text)
 if(isempty(text)),dims=[];return;endif
 parts=strsplit(text,';');dims=cellfun(@str2double,parts);
 if(any(!isfinite(dims))||any(dims<0)||any(dims!=fix(dims))),error('GXTXT:Publication','Invalid transport shape');endif
endfunction
