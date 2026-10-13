function P=gxtxt_publication_v2_declare_variable(P,id,s)
 fields={'dtype','dimension_ids','name','unit','semantic_role','coordinate_role','axis_kind','axis_origin','axis_step','group_id','component_ids','coordinate_variable_ids','chunks'};x={'VAR',gxtxt_publication_v2_encode(id)};
 for i=1:numel(fields),if(isfield(s,fields{i})),v=s.(fields{i});else v='';endif;if(iscell(v)),v=strjoin(v,';');elseif(isnumeric(v)),v=num2str(v,17);endif;x{end+1}=gxtxt_publication_v2_encode(v);endfor
 [P,~]=gxtxt_publication_v2_call(P,strjoin(x,sprintf('\t')));
endfunction
