% Generic typed transport for provider-owned scientific APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_scientific_provider_worker_main_v1(args)
if(numel(args)!=4),fprintf(2,'usage: worker function module-path request response\n');exit(2);endif
function_name=args{1};module_path=args{2};request_path=args{3};response_path=args{4};
framework_root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(framework_root,'core','octave','util'));
addpath(fullfile(framework_root,'core','octave','io'));
addpath(fullfile(framework_root,'core','octave','analysis'));
addpath(fullfile(module_path,'api','octave'));
addpath(fullfile(fileparts(module_path),'math.numeric','api','octave'));
try
  request=jsondecode(fileread(request_path));
  workspace='';if(isfield(request,'binary_workspace')),workspace=request.binary_workspace;endif
  a=decode_node(request.a,workspace);b=decode_node(request.b,workspace);c=decode_node(request.c,workspace);opts=decode_node(request.options,workspace);
  projection={};
  if(isfield(opts,'result_fields')),projection=opts.result_fields;opts=rmfield(opts,'result_fields');endif
  result=feval(function_name,request.family,request.action,a,b,c,opts);
  if(!isempty(projection))
    if(ischar(projection)),projection=strsplit(projection,',');endif
    for k=1:numel(projection),if(!isfield(result,projection{k})),error('GXTXT:ScientificTransport:Projection','unknown requested result field');endif;endfor
    result=rmfield(result,setdiff(fieldnames(result),projection));
  endif
  if(isfield(request,'capture_fields'))
    if(isempty(workspace)),error('GXTXT:ScientificTransport:Scope','captured columns require an owned workspace');endif
    result=capture_columns(result,request.capture_fields,workspace);
  endif
  % Public typed strings preserve line endings, Unicode and surrounding spaces.
  gxtxt_scientific_result_write_v1(response_path,result,true);
catch err
  write_error(response_path,err);fprintf(2,'%s\n',err.message);exit(1);
end_try_catch
endfunction
function value=decode_node(node,workspace)
  switch(node.kind)
    case 'empty',value=[];
    case 'text',value=node.value;
    case 'binary'
      if(isempty(workspace)),error('GXTXT:ScientificTransport:Scope','binary input requires an owned workspace');endif
      value=gxtxt_binary_resource_v1('read',workspace,node.descriptor);
    case 'array'
      dims=double(node.shape(:).');re=number_values(node,node.real);im=number_values(node,node.imaginary);
      if(numel(re)!=numel(im)),error('GXTXT:ScientificTransport:Shape','real and imaginary lengths differ');endif
      if(all(im==0)),raw=re;else raw=complex(re,im);endif
      if(prod(dims)!=numel(raw)),error('GXTXT:ScientificTransport:Shape','array shape does not match values');endif
      value=reshape(raw,dims);
      if(all(imag(value(:))==0)),value=real(value);endif
    case 'uniform'
      start=number_values(node,node.start);step=number_values(node,node.step);
      if(!isscalar(node.count)||node.count<1||node.count>67108864||node.count!=fix(node.count)||!isscalar(start)||!isscalar(step)||!isfinite(start)||!isfinite(step)||step<=0),error('GXTXT:ScientificTransport:Grid','invalid uniform grid');endif
      value=start+(0:node.count-1)'*step;
    case 'cell'
      value=cell(numel(node.items),1);
      for j=1:numel(node.items)
        if(iscell(node.items)),item=node.items{j};else,item=node.items(j);endif
        value{j}=decode_node(item,workspace);
      endfor
    case 'struct'
      value=struct();keys=fieldnames(node.fields);for j=1:numel(keys),key=keys{j};value.(key)=decode_node(node.fields.(key),workspace);endfor
    otherwise,error('GXTXT:ScientificTransport:Kind','unknown typed input kind');
  endswitch
endfunction
function values=number_values(node,raw)
  if(!isfield(node,'number_encoding')),values=double(raw(:));return;endif
  if(!strcmp(node.number_encoding,'float64_hex_be')),error('GXTXT:ScientificTransport:Number','unknown bounded number encoding');endif
  if(ischar(raw)),raw={raw};endif
  if(!iscellstr(raw)||any(cellfun(@(s) isempty(regexp(s,'^[0-9a-f]{16}$','once')),raw)))
    error('GXTXT:ScientificTransport:Number','malformed binary64 word');
  endif
  values=hex2num(char(raw(:)));
  policy='finite';if(isfield(node,'nonfinite_policy')),policy=node.nonfinite_policy;endif
  if(!ischar(policy)||!any(strcmp(policy,{'finite','allow_infinity'}))),error('GXTXT:ScientificTransport:Number','unknown bounded number policy');endif
  if(any(isnan(values))||strcmp(policy,'finite')&&any(!isfinite(values))),error('GXTXT:ScientificTransport:Number','nonfinite bounded input is not accepted by this policy');endif
endfunction
function output=capture_columns(result,fields,workspace)
  if(ischar(fields)),fields={fields};endif
  if(!iscellstr(fields)||isempty(fields)||numel(fields)>128||numel(unique(fields))!=numel(fields)),error('GXTXT:ScientificTransport:Capture','invalid captured field map');endif
  names={};shapes={};row_count=0;sample=result;
  for k=1:numel(fields)
    name=fields{k};if(!isfield(result,name)),continue;endif
    v=result.(name);
    if(numel(v)<=1),continue;endif
    if(!isa(v,'double')||!isreal(v)||!isvector(v)),error('GXTXT:ScientificTransport:Capture','captured facts require explicit real double vectors');endif
    if(row_count&&row_count!=numel(v)),error('GXTXT:ScientificTransport:Capture','captured columns must share a row count');endif
    row_count=numel(v);names{end+1}=name;shapes{end+1}=size(v);sample.(name)=v(1);
  endfor
  if(row_count*numel(names)*8>512*1024*1024),error('GXTXT:ScientificTransport:Capture','captured columns exceed 512 MiB');endif
  if(!isempty(names))
    fd=fopen(fullfile(workspace,'captured-columns.bin'),'wb','ieee-le');
    if(fd<0),error('GXTXT:ScientificTransport:IO','cannot create captured column artifact');endif
    unwind_protect
      for k=1:numel(names)
        if(fwrite(fd,result.(names{k})(:),'double')!=row_count),error('GXTXT:ScientificTransport:IO','short captured column write');endif
      endfor
    unwind_protect_cleanup,fclose(fd);end_unwind_protect
  endif
  output=struct('sample',sample,'capture',struct('fields',{names},'shapes',{shapes},'row_count',row_count));
endfunction
function write_error(path,err)
  fd=fopen(path,'w');if(fd<0),return;endif
  id='GXTXT:ScientificTransport:Remote';if(isfield(err,'identifier')&&!isempty(err.identifier)),id=err.identifier;endif
  fprintf(fd,'[result]\nok=0\nfields=\n\n[error]\nidentifier=%s\nmessage=%s\n',single_line(id),single_line(err.message));fclose(fd);
endfunction
function s=single_line(s),s=strrep(s,sprintf('\r'),' ');s=strrep(s,sprintf('\n'),' ');endfunction
