function P=gxtxt_publication_v2_write(P,id,values,shape)
 if(nargin<4),shape=numel(values);endif;if(isnumeric(shape)),shape=strjoin(arrayfun(@num2str,shape,'uniformoutput',false),';');endif
 b=gxtxt_publication_v2_block(values,shape,P.resource_scope);x=[{'WRITE',gxtxt_publication_v2_encode(id),gxtxt_publication_v2_encode(shape)},b];
 [P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
