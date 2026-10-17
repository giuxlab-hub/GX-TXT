% Public typed bounded-result transport; no statistical policy.
% SPDX-License-Identifier: GPL-3.0-or-later
function gxtxt_scientific_result_write_v1(path,S,exact_strings=false)
  if(!isstruct(S)||numel(S)!=1),error('GXTXT:ScientificTransport:Result','provider result must be a scalar struct');endif
  fd=fopen(path,'w');if(fd<0),error('GXTXT:ScientificTransport:IO','cannot write response');endif
  unwind_protect
    names=fieldnames(S);fprintf(fd,'[result]\nok=1\nfields=%s\n\n',strjoin(names,';'));
    for j=1:numel(names)
      name=names{j};write_node(fd,['result.' name],S.(name),0,exact_strings);
    endfor
  unwind_protect_cleanup
    fclose(fd);
  end_unwind_protect
endfunction
function write_node(fd,section,v,depth,exact_strings)
  if(depth>16),error('GXTXT:ScientificTransport:Result','result nesting exceeds 16 levels');endif
  fprintf(fd,'[%s]\n',section);
  if(isstruct(v)&&isscalar(v))
    names=fieldnames(v);fprintf(fd,'type=struct\nfields=%s\n\n',strjoin(names,';'));
    for j=1:numel(names),write_node(fd,[section '.' names{j}],v.(names{j}),depth+1,exact_strings);endfor
  elseif(iscell(v))
    fprintf(fd,'type=cell\ncount=%d\n\n',numel(v));
    for j=1:numel(v),write_node(fd,sprintf('%s.item%d',section,j),v{j},depth+1,exact_strings);endfor
  elseif(ischar(v))
    if(exact_strings)
      encoded='';if(!isempty(v)),encoded=char(matlab.net.base64encode(unicode2native(v,'UTF-8')));encoded=encoded(:)';endif
      fprintf(fd,'type=string\nencoding=base64_utf8\nvalue=%s\n\n',encoded);
    else,fprintf(fd,'type=string\nvalue=%s\n\n',single_line(v));endif
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
function s=numbers(v)
  parts=cell(numel(v),1);for k=1:numel(v),parts{k}=numtext(v(k));endfor;s=strjoin(parts,';');
endfunction
function s=numtext(v)
  if(!isreal(v)),error('GXTXT:ScientificTransport:ComplexOutput','provider must return split complex fields');endif
  if(isnan(v)),s='NaN';elseif(isinf(v)&&v>0),s='Inf';elseif(isinf(v)),s='-Inf';elseif(v==0&&signbit(v)),s='-0.0';else s=sprintf('%.17g',double(v));endif
endfunction
function s=single_line(s),s=strrep(s,sprintf('\r'),' ');s=strrep(s,sprintf('\n'),' ');endfunction
