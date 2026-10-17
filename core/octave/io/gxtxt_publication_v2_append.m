function P=gxtxt_publication_v2_append(P,dim,items)
 x={'APPEND',gxtxt_publication_v2_encode(dim),num2str(rows(items))};
 for i=1:rows(items)
   id=items{i,1};v=items{i,2};
   if(columns(items)>=3&&!isempty(items{i,3})),shape=strjoin(arrayfun(@num2str,items{i,3},'uniformoutput',false),';');else shape=num2str(numel(v));endif
   b=gxtxt_publication_v2_block(v,shape,P.resource_scope);x=[x,{gxtxt_publication_v2_encode(id),gxtxt_publication_v2_encode(shape)},b];
 endfor
 [P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
