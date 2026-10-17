% CORE per-job worker. Public provider functions remain the math authorities.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_scientific_binary_worker_main_v1(args)
  if(numel(args)!=3),error('GXTXT:ScientificTransport:Arguments','expected framework, worker workspace and execution output workspace');endif
  root=args{1};workspace=args{2};
  output_workspace=args{3};
  addpath(fullfile(root,'core','octave','util'));
  addpath(fullfile(root,'core','octave','io'));
  addpath(fullfile(root,'core','octave','analysis'));
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
      values=cell(1,numel(raw));for k=1:numel(raw),values{k}=decode(raw{k},workspace,output_workspace,0);endfor
      decode_seconds=toc(started);compute_started=tic();
      result=feval(fn,values{:});
      compute_seconds=toc(compute_started);encode_started=tic();
      projection=request.projection;
      if(!isempty(projection))
        if(ischar(projection)),projection={projection};endif
        names=fieldnames(result);for k=1:numel(projection),if(!isfield(result,projection{k})),error('GXTXT:ScientificTransport:Projection','unknown requested result field');endif;endfor
        result=rmfield(result,setdiff(names,projection));
      endif
      encoded=encode(result,output_workspace,0);
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
function v=decode(node,workspace,execution_workspace,depth)
  if(depth>32),error('GXTXT:ScientificTransport:Nesting','input nesting exceeds 32');endif
  switch(node.kind)
    case 'text',v=node.value;
    case 'number',v=str2double(node.value);
    case 'binary'
      source=workspace;
      if(isfield(node,'source'))
        if(!strcmp(node.source,'execution')),error('GXTXT:ScientificTransport:Scope','invalid resource scope');endif
        source=execution_workspace;
      endif
      v=gxtxt_binary_resource_v1('read',source,node.descriptor);
    case 'cell'
      raw=node.items;if(!iscell(raw)),raw=num2cell(raw);endif
      v=cell(1,numel(raw));for k=1:numel(raw),v{k}=decode(raw{k},workspace,execution_workspace,depth+1);endfor
    case 'struct'
      v=struct();names=fieldnames(node.fields);for k=1:numel(names),v.(names{k})=decode(node.fields.(names{k}),workspace,execution_workspace,depth+1);endfor
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
  elseif(isa(v,'double')&&isscalar(v)&&isreal(v)),node=struct('kind','number','value',sprintf('%.17g',v));
  elseif(isnumeric(v)||islogical(v))
    node=struct('kind','binary','descriptor',gxtxt_binary_resource_v1('write',workspace,v));
  else,error('GXTXT:ScientificTransport:Result','unsupported scientific result');endif
endfunction
