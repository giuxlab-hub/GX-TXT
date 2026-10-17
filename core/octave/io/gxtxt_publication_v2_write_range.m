function P=gxtxt_publication_v2_write_range(P,id,start,values)
 b=gxtxt_publication_v2_block(values,numel(values),P.resource_scope);x=[{'RANGE',gxtxt_publication_v2_encode(id),num2str(start)},b];
 [P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
