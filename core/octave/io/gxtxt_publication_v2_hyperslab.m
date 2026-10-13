function P=gxtxt_publication_v2_hyperslab(P,id,starts,counts,values)
 a=strjoin(arrayfun(@num2str,starts,'uniformoutput',false),';');b=strjoin(arrayfun(@num2str,counts,'uniformoutput',false),';');block=gxtxt_publication_v2_block(values,b);
 x=[{'HYPER',gxtxt_publication_v2_encode(id),gxtxt_publication_v2_encode(a),gxtxt_publication_v2_encode(b)},block];
 [P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
