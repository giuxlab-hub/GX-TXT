function P=gxtxt_publication_v2_declare_dimension(P,id,size,extendible)
 if(nargin<4),extendible=false;endif; [P,~]=gxtxt_publication_v2_call(P,sprintf('DIM\t%s\t%d\t%d',gxtxt_publication_v2_encode(id),size,logical(extendible)));
endfunction
