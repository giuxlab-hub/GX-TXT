% CORE implementation detail shared by existing Bridge and scientific worker.
% Descriptor v2 preserves dtype/shape; v1 float32/float64 reads remain supported.
% SPDX-License-Identifier: GPL-3.0-or-later
function value=gxtxt_binary_resource_v1(action,workspace,input)
  if(strcmp(action,'write'))
    v=input;dtype=class(v);
    if(strcmp(dtype,'double')),dtype='float64';elseif(strcmp(dtype,'single')),dtype='float32';elseif(strcmp(dtype,'logical')),dtype='bool';endif
    if(!isreal(v))
      if(strcmp(dtype,'float32')),dtype='complex64';elseif(strcmp(dtype,'float64')),dtype='complex128';else error('GXTXT:ScientificTransport:Dtype','unsupported complex storage class');endif
    endif
    [precision,width,lanes]=dtype_info(dtype);shape=size(v);count=numel(v);
    if(count*width>512*1024*1024),error('GXTXT:ScientificTransport:Size','binary resource exceeds 512 MiB');endif
    [~,base]=fileparts(tempname(workspace));id=[hash('md5',base) '.bin'];path=fullfile(workspace,id);
    fd=fopen(path,'wb','ieee-le');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot create binary resource');endif
    unwind_protect
      if(lanes==2)
        data=zeros(2,count,precision);data(1,:)=real(v(:));data(2,:)=imag(v(:));written=fwrite(fd,data(:),precision);
      else,written=fwrite(fd,v(:),precision);endif
    unwind_protect_cleanup,fclose(fd);end_unwind_protect
    if(written!=count*lanes),unlink(path);error('GXTXT:ScientificTransport:IO','short binary write');endif
    value=struct('version',2,'dtype',dtype,'endian','little','order','F','shape',shape,'count',count,'byte_count',count*width,'resource_id',id);
  elseif(strcmp(action,'read'))
    d=input;required={'version','dtype','endian','order','shape','count','byte_count','resource_id'};
    for k=1:numel(required),if(!isfield(d,required{k})),error('GXTXT:ScientificTransport:Descriptor','incomplete binary descriptor');endif;endfor
    [precision,width,lanes]=dtype_info(d.dtype);shape=double(d.shape(:).');
    if(!any(d.version==[1 2])||(d.version==1&&!any(strcmp(d.dtype,{'float32','float64'})))||!strcmp(d.endian,'little')||!strcmp(d.order,'F')||isempty(shape)||numel(shape)>16||any(!isfinite(shape))||any(shape<0)||any(shape!=fix(shape))||prod(shape)!=d.count||d.byte_count!=width*d.count||d.byte_count>512*1024*1024)
      error('GXTXT:ScientificTransport:Descriptor','invalid binary descriptor');
    endif
    if(isempty(regexp(d.resource_id,'^[a-f0-9]{32}\.bin$','once'))),error('GXTXT:ScientificTransport:Resource','invalid binary resource ID');endif
    path=fullfile(workspace,d.resource_id);[st,err]=lstat(path);
    if(err||!S_ISREG(st.mode)||st.size!=d.byte_count),error('GXTXT:ScientificTransport:Size','binary resource size/type mismatch');endif
    if(!ispc()&&st.uid!=getuid()),error('GXTXT:ScientificTransport:Owner','binary resource owner mismatch');endif
    fd=fopen(path,'rb','ieee-le');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot open binary resource');endif
    unwind_protect,data=fread(fd,d.count*lanes,['*' precision]);extra=fread(fd,1,'*uint8');unwind_protect_cleanup,fclose(fd);end_unwind_protect
    if(numel(data)!=d.count*lanes||!isempty(extra)),error('GXTXT:ScientificTransport:Size','binary resource length changed');endif
    if(lanes==2),data=complex(data(1:2:end),data(2:2:end));elseif(strcmp(d.dtype,'bool')),data=logical(data);endif
    if(numel(shape)==1),shape=[shape 1];endif
    value=reshape(data,shape);
  else,error('GXTXT:ScientificTransport:Operation','invalid internal resource operation');endif
endfunction
function [precision,width,lanes]=dtype_info(dtype)
  lanes=1;
  switch(dtype)
    case 'float32',precision='single';width=4;
    case 'float64',precision='double';width=8;
    case 'complex64',precision='single';width=8;lanes=2;
    case 'complex128',precision='double';width=16;lanes=2;
    case {'int8','uint8'},precision=dtype;width=1;
    case {'int16','uint16'},precision=dtype;width=2;
    case {'int32','uint32'},precision=dtype;width=4;
    case {'int64','uint64'},precision=dtype;width=8;
    case 'bool',precision='uint8';width=1;
    otherwise,error('GXTXT:ScientificTransport:Dtype','unsupported binary dtype');
  endswitch
endfunction
