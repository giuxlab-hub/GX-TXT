function P=gxtxt_publication_v2_open(session,module_id,dataset_id,contract,options)
 if(nargin<5),options=struct();endif
 storage=f(options,'storage','auto');req=f(options,'capabilities_required',{});pref=f(options,'capabilities_preferred',{});
 if(ischar(req)),req={req};endif;if(ischar(pref)),pref={pref};endif
 source_dataset_ids=cellstr_local(f(options,'source_dataset_ids',{}));
 source_variable_ids=cellstr_local(f(options,'source_variable_ids',{}));
 producer_version=char_local(f(options,'producer_version',''));
 source=char_local(f(options,'source',''));
 provenance=char_local(f(options,'provenance',''));
 notes=char_local(f(options,'notes',''));
 replace_owned=bool_local(f(options,'replace_owned',false),'replace_owned');
 here=fileparts(mfilename('fullpath'));root=fileparts(fileparts(fileparts(here)));bridge=fullfile(root,'core','tcl','dataset_publication_v2_bridge.tcl');
 args={bridge,session,module_id,dataset_id,contract,storage,strjoin(req,';'),strjoin(pref,';'), ...
       producer_version,strjoin(source_dataset_ids,';'),strjoin(source_variable_ids,';'),source,provenance,notes,num2str(replace_owned)};
 [in,out,pid]=popen2('tclsh',args);
 parts=gxtxt_table_stream_v3_parts(gxtxt_publication_v2_readline(out,pid));if(strcmp(parts{1},'ERROR')),error('GXTXT:Publication','%s',gxtxt_table_stream_v3_decode(parts{2}));endif
 if(numel(parts)!=5||!strcmp(parts{1},'READY')),error('GXTXT:Publication','Invalid bridge response');endif
 P=struct('api_version',2,'bridge_in',in,'bridge_out',out,'bridge_pid',pid,'core_pid',str2double(parts{2}),'provider',gxtxt_table_stream_v3_decode(parts{5}),'closed',false,'finalized',false);
endfunction
function out=bool_local(v,name)
 if((islogical(v)||isnumeric(v))&&isscalar(v)),out=logical(v);else error('GXTXT:Publication','%s must be a scalar boolean',name);endif
endfunction
function v=f(s,n,d),if(isfield(s,n)),v=s.(n);else v=d;endif;endfunction
function out=cellstr_local(v)
 if(isempty(v)),out={};elseif(ischar(v)),out={v};elseif(iscell(v)),out=cellfun(@char_local,v,'UniformOutput',false);else error('GXTXT:Publication','source ID options must be strings or cell arrays of strings');endif
endfunction
function out=char_local(v)
 if(ischar(v)),out=v;elseif(isstring(v)&&isscalar(v)),out=char(v);else error('GXTXT:Publication','publication provenance options must be scalar strings');endif
endfunction
