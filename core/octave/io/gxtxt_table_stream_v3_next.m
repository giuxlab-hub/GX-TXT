% SPDX-License-Identifier: GPL-3.0-or-later
function [S,chunk]=gxtxt_table_stream_v3_next(S)
  if(!isstruct(S)||!isfield(S,'bridge_in')||S.bridge_in<0||S.closed),error('GXTXT:TableStream','Invalid/closed stream');endif
  fputs(S.bridge_in,"NEXT\n");fflush(S.bridge_in);
  head=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid));bridge_error(head);
  if(numel(head)!=5||!strcmp(head{1},'CHUNK')),error('GXTXT:TableStream','Invalid Table Stream v3 chunk response');endif
  offset=str2double(head{2});nrows=str2double(head{3});eof=logical(str2double(head{4}));nvars=str2double(head{5});
  values=cell(1,nvars);names=cell(1,nvars);ids=cell(1,nvars);dtypes=cell(1,nvars);transports=cell(1,nvars);resources={};
  missing_masks=cell(1,nvars);
  % Consume the bounded frame before converting values. A rejected CSV value
  % must not leave END queued as the acknowledgement of a later CLOSE/NEXT.
  items=cell(1,nvars);
  for c=1:nvars
    items{c}=gxtxt_table_stream_v3_parts(gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid));bridge_error(items{c});
    if(numel(items{c})==15&&strcmp(items{c}{1},'RCOL')),resources{end+1}=items{c}{14};endif
  endfor
  ending=gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid);if(!strcmp(ending,'END')),error('GXTXT:TableStream','Invalid Table Stream v3 chunk terminator');endif
  unwind_protect
  for c=1:nvars
    item=items{c};
    if(numel(item)<1||!any(strcmp(item{1},{'COL','NCOL','BCOL','RCOL'}))),error('GXTXT:TableStream','Invalid Table Stream v3 column response');endif
    ids{c}=gxtxt_table_stream_v3_decode(item{2});names{c}=gxtxt_table_stream_v3_decode(item{3});dtypes{c}=gxtxt_table_stream_v3_decode(item{4});
    if(strcmp(item{1},'RCOL'))
      if(numel(item)!=15),error('GXTXT:TableStream','Invalid managed binary Table Stream column');endif
      d=struct('version',str2double(item{8}),'dtype',dtypes{c},'endian',item{9},'order',item{10},'shape',parse_shape(gxtxt_table_stream_v3_decode(item{11})),'count',str2double(item{12}),'byte_count',str2double(item{13}),'resource_id',item{14});
      if(d.count!=nrows),error('GXTXT:TableStream','Managed binary column length mismatch');endif
      values{c}=gxtxt_binary_resource_v1('read',gxtxt_table_stream_v3_decode(item{15}),d);
      transports{c}='managed_binary';
    elseif(strcmp(item{1},'BCOL'))
      if(numel(item)!=11),error('GXTXT:TableStream','Invalid typed binary Table Stream column response');endif
      endian=item{8};shape_text=gxtxt_table_stream_v3_decode(item{9});block_count=str2double(item{10});
      if(block_count!=nrows),error('GXTXT:TableStream','Typed binary Table Stream column length mismatch');endif
      values{c}=binary_values(item{11},dtypes{c},endian,shape_text,nrows);
      transports{c}='typed_binary';
    else
      if(numel(item)!=8),error('GXTXT:TableStream','Invalid value Table Stream column response');endif
      encoded=item{8};raw=cell(0,1);
      if(nrows>0)
        pieces=strsplit(encoded,',','collapsedelimiters',false);
        if(numel(pieces)!=nrows),error('GXTXT:TableStream','Table Stream v3 column length mismatch');endif
        if(strcmp(item{1},'NCOL')),raw=pieces(:);
        else raw=cellfun(@gxtxt_table_stream_v3_decode,pieces(:),'uniformoutput',false);endif
      endif
      [values{c},missing_masks{c}]=typed_values(raw,dtypes{c});
      transports{c}='values';
    endif
  endfor
  unwind_protect_cleanup
  for k=1:numel(resources)
    fputs(S.bridge_in,['RELEASE' sprintf('\t') resources{k} sprintf('\n')]);fflush(S.bridge_in);
    released=gxtxt_table_stream_v3_readline(S.bridge_out,S.bridge_pid);
    if(!strcmp(released,'RELEASED')),bridge_error(gxtxt_table_stream_v3_parts(released));error('GXTXT:TableStream','Invalid resource release response');endif
  endfor
  end_unwind_protect
  if(!isequal(ids,S.selected_variable_ids)),error('GXTXT:TableStream','Table Stream v3 variable order changed');endif
  S.row_number=offset+nrows;S.eof=eof;
  chunk=struct('api_version',3,'dataset_id',S.dataset_id,'names',{names},'variable_ids',{ids},'dtypes',{dtypes},'transports',{transports},'values',{values},'nrows',nrows,'row_count',nrows,'offset',offset,'start',offset,'first_row',offset+1,'last_row',offset+nrows,'eof',eof,'schema',S.schema);
  chunk.missing_masks=missing_masks;
endfunction

function values=binary_values(payload,dtype,endian,shape_text,expected)
  try bytes=uint8(matlab.net.base64decode(payload));catch err,error('GXTXT:TableStream','Invalid typed binary Base64 payload: %s',err.message);end_try_catch
  bytes=bytes(:)';
  switch(dtype)
    case 'bool',width=1;values=logical(bytes);
    case 'uint8',width=1;values=bytes;
    case 'int8',width=1;values=typecast(bytes,'int8');
    case 'uint16',width=2;values=typecast(bytes,'uint16');
    case 'int16',width=2;values=typecast(bytes,'int16');
    case 'uint32',width=4;values=typecast(bytes,'uint32');
    case 'int32',width=4;values=typecast(bytes,'int32');
    case 'uint64',width=8;values=typecast(bytes,'uint64');
    case 'int64',width=8;values=typecast(bytes,'int64');
    case 'float32',width=4;values=typecast(bytes,'single');
    case 'float64',width=8;values=typecast(bytes,'double');
    otherwise,error('GXTXT:TableStream','Unsupported typed binary dtype %s',dtype);
  endswitch
  if(numel(bytes)!=expected*width),error('GXTXT:TableStream','Typed binary byte count mismatch for dtype %s',dtype);endif
  [~,~,machine_endian]=computer();
  swap=(width>1)&&((strcmpi(machine_endian,'L')&&strcmp(endian,'big'))||(strcmpi(machine_endian,'B')&&strcmp(endian,'little')));
  if(swap),values=swapbytes(values);endif
  dims=parse_shape(shape_text);
  if(numel(dims)!=1||dims(1)!=expected),error('GXTXT:TableStream','Typed binary shape/count mismatch');endif
  values=values(:);
endfunction

function dims=parse_shape(text)
  if(isempty(text)),dims=[];return;endif
  parts=strsplit(text,';','collapsedelimiters',false);dims=cellfun(@str2double,parts);
  if(any(!isfinite(dims))||any(dims<0)||any(dims!=fix(dims))),error('GXTXT:TableStream','Invalid typed binary shape');endif
endfunction

function [values,missing]=typed_values(raw,dtype)
  missing=[];
  if(strcmp(dtype,'string')),values=raw;return;endif
  if(isempty(raw))
    if(strcmp(dtype,'bool')),values=false(0,1);elseif(strcmp(dtype,'float32')),values=single(zeros(0,1));elseif(any(strcmp(dtype,{'float16','float64'}))),values=zeros(0,1);else values=cast(zeros(0,1),dtype);endif
    return;
  endif
  if(any(strcmp(dtype,{'uint64','int64'}))),values=gxtxt_table_integer_values_v1(raw,dtype);values=values(:);return;endif
  numeric=str2double(raw);
  absent=cellfun('isempty',raw); % Canonical CSV tokens are already trimmed.
  float=any(strcmp(dtype,{'float16','float32','float64'}));
  nan_token=strcmpi(raw,'nan')|strcmpi(raw,'+nan')|strcmpi(raw,'-nan');
  if(any(isnan(numeric)&!nan_token&!(absent&float))),error('GXTXT:TableStream','Provider value is incompatible with dtype %s',dtype);endif
  if(any(absent)),missing=logical(absent(:));endif
  if(strcmp(dtype,'bool'))
    if(any(!isfinite(numeric)|!(numeric==0|numeric==1))),error('GXTXT:TableStream','Provider value is incompatible with dtype bool');endif
    values=logical(numeric);
  elseif(strcmp(dtype,'float64')||strcmp(dtype,'float16')),values=double(numeric);
  elseif(strcmp(dtype,'float32')),values=single(numeric);
  else
    if(any(!isfinite(numeric)|numeric!=fix(numeric)|numeric<double(intmin(dtype))|numeric>double(intmax(dtype)))),error('GXTXT:TableStream','Provider value is outside dtype %s',dtype);endif
    values=cast(numeric,dtype);
  endif
endfunction
function bridge_error(parts),if(numel(parts)>=2&&strcmp(parts{1},'ERROR')),error('GXTXT:TableStream','%s',gxtxt_table_stream_v3_decode(parts{2}));endif;endfunction
