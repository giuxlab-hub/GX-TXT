% Generic typed transport for provider-owned scientific APIs.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_scientific_provider_worker_main_v1(args)
if(numel(args)!=4),fprintf(2,'usage: worker function module-path request response\n');exit(2);endif
function_name=args{1};module_path=args{2};request_path=args{3};response_path=args{4};
addpath(fullfile(module_path,'api','octave'));
addpath(fullfile(fileparts(module_path),'math.numeric','api','octave'));
try
  request=jsondecode(fileread(request_path));
  a=decode_node(request.a);b=decode_node(request.b);c=decode_node(request.c);opts=decode_node(request.options);
  projection={};
  if(isfield(opts,'result_fields')),projection=opts.result_fields;opts=rmfield(opts,'result_fields');endif
  result=feval(function_name,request.family,request.action,a,b,c,opts);
  if(!isempty(projection))
    if(ischar(projection)),projection=strsplit(projection,',');endif
    for k=1:numel(projection),if(!isfield(result,projection{k})),error('GXTXT:ScientificTransport:Projection','unknown requested result field');endif;endfor
    result=rmfield(result,setdiff(fieldnames(result),projection));
  endif
  write_result(response_path,result);
catch err
  write_error(response_path,err);fprintf(2,'%s\n',err.message);exit(1);
end_try_catch
endfunction
function value=decode_node(node)
  switch(node.kind)
    case 'empty',value=[];
    case 'text',value=node.value;
    case 'array'
      dims=double(node.shape(:).');raw=double(node.real(:))+1i*double(node.imaginary(:));
      if(prod(dims)!=numel(raw)),error('GXTXT:ScientificTransport:Shape','array shape does not match values');endif
      value=reshape(raw,dims);
      if(all(imag(value(:))==0)),value=real(value);endif
    case 'uniform'
      if(!isscalar(node.count)||node.count<1||node.count>67108864||node.count!=fix(node.count)||!isfinite(node.start)||!isfinite(node.step)||node.step<=0),error('GXTXT:ScientificTransport:Grid','invalid uniform grid');endif
      value=node.start+(0:node.count-1)'*node.step;
    case 'cell'
      value=cell(numel(node.items),1);
      for j=1:numel(node.items)
        if(iscell(node.items)),item=node.items{j};else,item=node.items(j);endif
        value{j}=decode_node(item);
      endfor
    case 'struct'
      value=struct();keys=fieldnames(node.fields);for j=1:numel(keys),key=keys{j};value.(key)=decode_node(node.fields.(key));endfor
    otherwise,error('GXTXT:ScientificTransport:Kind','unknown typed input kind');
  endswitch
endfunction
function write_result(path,S)
  if(!isstruct(S)||numel(S)!=1),error('GXTXT:ScientificTransport:Result','provider result must be a scalar struct');endif
  fd=fopen(path,'w');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot write response');endif
  unwind_protect
    names=fieldnames(S);fprintf(fd,'[result]\nok=1\nfields=%s\n\n',strjoin(names,';'));
    for j=1:numel(names)
      name=names{j};write_node(fd,['result.' name],S.(name),0);
    endfor
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
endfunction
function write_node(fd,section,v,depth)
  if(depth>16),error('GXTXT:ScientificTransport:Result','result nesting exceeds 16 levels');endif
  fprintf(fd,'[%s]\n',section);
  if(isstruct(v)&&isscalar(v))
    names=fieldnames(v);fprintf(fd,'type=struct\nfields=%s\n\n',strjoin(names,';'));
    for j=1:numel(names),write_node(fd,[section '.' names{j}],v.(names{j}),depth+1);endfor
  elseif(iscell(v))
    fprintf(fd,'type=cell\ncount=%d\n\n',numel(v));
    for j=1:numel(v),write_node(fd,sprintf('%s.item%d',section,j),v{j},depth+1);endfor
  elseif(ischar(v)),fprintf(fd,'type=string\nvalue=%s\n\n',single_line(v));
  elseif(islogical(v)&&isscalar(v)),fprintf(fd,'type=boolean\nvalue=%d\n\n',v);
  elseif((isnumeric(v)||islogical(v))&&isscalar(v)&&isreal(v)),fprintf(fd,'type=number\nvalue=%s\n\n',numtext(v));
  elseif((isnumeric(v)||islogical(v))&&isscalar(v)),fprintf(fd,'type=complex_number\nreal=%s\nimaginary=%s\n\n',numtext(real(v)),numtext(imag(v)));
  elseif((isnumeric(v)||islogical(v))&&isempty(v)),fprintf(fd,'type=vector\nvalue=\n\n');
  elseif((isnumeric(v)||islogical(v))&&isvector(v)&&isreal(v)),fprintf(fd,'type=vector\nvalue=%s\n\n',numbers(v(:)));
  elseif((isnumeric(v)||islogical(v))&&isvector(v)),fprintf(fd,'type=complex_vector\nreal=%s\nimaginary=%s\n\n',numbers(real(v(:))),numbers(imag(v(:))));
  elseif((isnumeric(v)||islogical(v))&&ismatrix(v)&&isreal(v)),fprintf(fd,'type=matrix\nrows=%d\ncols=%d\nvalue=%s\n\n',rows(v),columns(v),numbers(reshape(v.',[],1)));
  elseif((isnumeric(v)||islogical(v))&&ismatrix(v)),fprintf(fd,'type=complex_matrix\nrows=%d\ncols=%d\nreal=%s\nimaginary=%s\n\n',rows(v),columns(v),numbers(reshape(real(v).',[],1)),numbers(reshape(imag(v).',[],1)));
  elseif((isnumeric(v)||islogical(v))&&isreal(v)),fprintf(fd,'type=tensor\ndimensions=%s\nvalue=%s\n\n',numbers(size(v)),numbers(v(:)));
  elseif(isnumeric(v)||islogical(v)),fprintf(fd,'type=complex_tensor\ndimensions=%s\nreal=%s\nimaginary=%s\n\n',numbers(size(v)),numbers(real(v(:))),numbers(imag(v(:))));
  else error('GXTXT:ScientificTransport:Result','unsupported result field %s',section);endif
endfunction
function write_error(path,err)
  fd=fopen(path,'w');if(fd<0),return;endif
  id='GXTXT:ScientificTransport:Remote';if(isfield(err,'identifier')&&!isempty(err.identifier)),id=err.identifier;endif
  fprintf(fd,'[result]\nok=0\nfields=\n\n[error]\nidentifier=%s\nmessage=%s\n',single_line(id),single_line(err.message));fclose(fd);
endfunction
function s=numbers(v)
  parts=cell(numel(v),1);for k=1:numel(v),parts{k}=numtext(v(k));endfor;s=strjoin(parts,';');
endfunction
function s=numtext(v)
  if(!isreal(v)),error('GXTXT:ScientificTransport:ComplexOutput','provider must return split complex fields');endif
  if(isnan(v)),s='NaN';elseif(isinf(v)&&v>0),s='Inf';elseif(isinf(v)),s='-Inf';else s=sprintf('%.17g',double(v));endif
endfunction
function s=single_line(s),s=strrep(s,sprintf('\r'),' ');s=strrep(s,sprintf('\n'),' ');endfunction
