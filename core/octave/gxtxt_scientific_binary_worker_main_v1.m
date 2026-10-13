% CORE per-job worker. Public provider functions remain the math authorities.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_scientific_binary_worker_main_v1(args)
  if(numel(args)!=2),error('GXTXT:ScientificTransport:Arguments','expected framework and owned workspace');endif
  root=args{1};workspace=args{2};
  addpath(fullfile(root,'core','octave','util'));
  addpath(fullfile(root,'plugins','modules','math.numeric','api','octave'));
  addpath(fullfile(root,'plugins','modules','math.signal','api','octave'));
  parent_pid=getppid();
  budget=str2double(getenv('OMP_NUM_THREADS'));if(isfinite(budget)&&budget>=1),fftw('threads',budget);endif
  while(true)
    request_path=fullfile(workspace,'request.json');
    while(exist(request_path,'file')!=2)
      if(getppid()!=parent_pid||exist(fullfile(workspace,'stop'),'file')==2),return;endif
      pause(0.005);
    endwhile
    line=fileread(request_path);unlink(request_path);
    started=tic();
    try
      request=jsondecode(line,'makeValidName',false);fn=request.('function');
      if(!any(strcmp(fn,{'gxtxt_signal_v1','gxtxt_numeric_v1'}))),error('GXTXT:ScientificTransport:Function','provider function is not registered');endif
      raw=request.args;if(!iscell(raw)),raw=num2cell(raw);endif
      values=cell(1,numel(raw));for k=1:numel(raw),values{k}=decode(raw{k},workspace,0);endfor
      decode_seconds=toc(started);compute_started=tic();
      result=feval(fn,values{:});
      compute_seconds=toc(compute_started);encode_started=tic();
      projection=request.projection;
      if(!isempty(projection))
        if(ischar(projection)),projection={projection};endif
        names=fieldnames(result);for k=1:numel(projection),if(!isfield(result,projection{k})),error('GXTXT:ScientificTransport:Projection','unknown requested result field');endif;endfor
        result=rmfield(result,setdiff(names,projection));
      endif
      encoded=encode(result,workspace,0);
      response=struct('ok',true,'value',encoded,'seconds',toc(started),'decode_seconds',decode_seconds,'compute_seconds',compute_seconds,'encode_seconds',toc(encode_started));
    catch err
      response=struct('ok',false,'identifier',err.identifier,'message',err.message,'seconds',toc(started));
    end_try_catch
    fd=fopen(fullfile(workspace,'response.partial'),'w');
    fprintf(fd,'%s\n',jsonencode(response));fclose(fd);
    [status,message]=rename(fullfile(workspace,'response.partial'),fullfile(workspace,'response.json'));
    if(status!=0),error('GXTXT:ScientificTransport:IO',message);endif
  endwhile
endfunction
function v=decode(node,workspace,depth)
  if(depth>32),error('GXTXT:ScientificTransport:Nesting','input nesting exceeds 32');endif
  switch(node.kind)
    case 'text',v=node.value;
    case 'number',v=str2double(node.value);
    case 'binary'
      d=node.descriptor;shape=double(d.shape(:).');
      if(d.version!=1||!strcmp(d.dtype,'float64')||!strcmp(d.endian,'little')||!strcmp(d.order,'F')||numel(shape)>16||any(shape<0)||any(shape!=fix(shape))||prod(shape)!=d.count||d.byte_count!=8*d.count||d.byte_count>512*1024*1024)
        error('GXTXT:ScientificTransport:Descriptor','invalid binary descriptor');
      endif
      if(isempty(regexp(d.resource_id,'^[a-f0-9]{32}\.bin$','once'))),error('GXTXT:ScientificTransport:Resource','invalid resource ID');endif
      path=fullfile(workspace,d.resource_id);[st,err]=lstat(path);
      if(err||!S_ISREG(st.mode)||st.size!=d.byte_count),error('GXTXT:ScientificTransport:Size','binary resource size/type mismatch');endif
      fd=fopen(path,'rb','ieee-le');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot open binary resource');endif
      unwind_protect,v=fread(fd,d.count,'*double');unwind_protect_cleanup,fclose(fd);end_unwind_protect
      if(numel(v)!=d.count),error('GXTXT:ScientificTransport:Size','short binary resource');endif
      v=reshape(v,shape);
    case 'cell'
      raw=node.items;if(!iscell(raw)),raw=num2cell(raw);endif
      v=cell(1,numel(raw));for k=1:numel(raw),v{k}=decode(raw{k},workspace,depth+1);endfor
    case 'struct'
      v=struct();names=fieldnames(node.fields);for k=1:numel(names),v.(names{k})=decode(node.fields.(names{k}),workspace,depth+1);endfor
      if(isfield(v,'__gxtxt_complex__')),v=complex(v.real,v.imaginary);
      elseif(isfield(v,'__gxtxt_uniform__')),v=v.start+(0:v.count-1)'*v.step;endif
    otherwise,error('GXTXT:ScientificTransport:Kind','unsupported typed node');
  endswitch
endfunction
function node=encode(v,workspace,depth)
  if(depth>32),error('GXTXT:ScientificTransport:Nesting','result nesting exceeds 32');endif
  if(isstruct(v)&&isscalar(v))
    fields=struct();names=fieldnames(v);for k=1:numel(names),fields.(names{k})=encode(v.(names{k}),workspace,depth+1);endfor
    node=struct('kind','struct','fields',fields);
  elseif(iscell(v))
    items=cell(1,numel(v));for k=1:numel(v),items{k}=encode(v{k},workspace,depth+1);endfor;node=struct('kind','cell','items',{items});
  elseif(ischar(v)),node=struct('kind','text','value',v);
  elseif(islogical(v)&&isscalar(v)),node=struct('kind','logical','value',v);
  elseif((isnumeric(v)||islogical(v))&&isscalar(v)&&isreal(v)),node=struct('kind','number','value',sprintf('%.17g',double(v)));
  elseif((isnumeric(v)||islogical(v))&&isreal(v))
    if(numel(v)*8>512*1024*1024),error('GXTXT:ScientificTransport:Size','result exceeds binary limit');endif
    % Tempname is reduced to a CORE generated UUID-style opaque resource ID.
    [~,base]=fileparts(tempname(workspace));id=hash('md5',base);id=[id '.bin'];path=fullfile(workspace,id);
    fd=fopen(path,'wb','ieee-le');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot create result resource');endif
    unwind_protect,count=fwrite(fd,double(v(:)),'double');unwind_protect_cleanup,fclose(fd);end_unwind_protect
    if(count!=numel(v)),error('GXTXT:ScientificTransport:IO','short result write');endif
    shape=size(v);if(isvector(v)),shape=[numel(v),1];endif
    d=struct('version',1,'dtype','float64','endian','little','order','F','shape',shape,'count',numel(v),'byte_count',numel(v)*8,'resource_id',id);
    node=struct('kind','binary','descriptor',d);
  else,error('GXTXT:ScientificTransport:Result','unsupported scientific result');endif
endfunction
