function P=gxtxt_publication_v2_declare_uniform(P,id,dim,origin,step,s)
 if(nargin<6),s=struct();endif;fields={'name','unit','dtype','semantic_role'};x={'UNIFORM',gxtxt_publication_v2_encode(id),gxtxt_publication_v2_encode(dim),gxtxt_publication_v2_encode(origin),gxtxt_publication_v2_encode(step)};
 for i=1:4,if(isfield(s,fields{i})),v=s.(fields{i});else v='';endif;x{end+1}=gxtxt_publication_v2_encode(v);endfor;[P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
