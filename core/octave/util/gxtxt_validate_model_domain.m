function domain = gxtxt_validate_model_domain(domain, expected_inputs, expected_model_id)
% Validate and, when expected_inputs is supplied, reorder a convex-hull model
% domain into the mathematical model's declared input order.
  if(nargin<2),expected_inputs={};endif
  if(nargin<3),expected_model_id='';endif
  if(!isstruct(domain)||!isfield(domain,'input_names')||!isfield(domain,'vertices'))
    error('gxtxt_validate_model_domain: invalid domain structure');
  endif
  names=normalize_names(domain.input_names); V=domain.vertices;
  if(isempty(names)),error('gxtxt_validate_model_domain: no input variables declared');endif
  if(numel(unique(names))!=numel(names)),error('gxtxt_validate_model_domain: duplicate input variable names');endif
  if(!isnumeric(V)||ndims(V)!=2||columns(V)!=numel(names)),error('gxtxt_validate_model_domain: vertex matrix shape does not match input names');endif
  if(any(!isfinite(V(:)))),error('gxtxt_validate_model_domain: domain coordinates must be finite');endif
  d=columns(V); if(rows(V)<d+1),error('gxtxt_validate_model_domain: at least %d points are required for a %d-D convex hull',d+1,d);endif

  expected=normalize_names(expected_inputs);
  if(!isempty(expected))
    missing=setdiff(expected,names,'stable');unexpected=setdiff(names,expected,'stable');
    if(!isempty(missing)),error('gxtxt_validate_model_domain: missing input(s): %s',strjoin(missing,', '));endif
    if(!isempty(unexpected)),error('gxtxt_validate_model_domain: unexpected input(s): %s',strjoin(unexpected,', '));endif
    order=zeros(1,numel(expected));for i=1:numel(expected),order(i)=find(strcmp(names,expected{i}),1);endfor
    names=names(order);V=V(:,order);
  endif

  if(!isfield(domain,'kind')||isempty(domain.kind)),domain.kind='convex_hull';endif
  if(!strcmpi(strtrim(domain.kind),'convex_hull')),error('gxtxt_validate_model_domain: unsupported domain kind: %s',domain.kind);endif
  if(!isfield(domain,'model_id')),domain.model_id='';endif
  if(!isempty(expected_model_id)&&!isempty(domain.model_id)&&!strcmp(strtrim(domain.model_id),strtrim(expected_model_id)))
    error('gxtxt_validate_model_domain: model_id mismatch: file=%s expected=%s',domain.model_id,expected_model_id);
  endif
  centered=V-mean(V,1);if(rank(centered)<d),error('gxtxt_validate_model_domain: convex hull is dimensionally degenerate');endif
  domain.input_names=names;domain.vertices=V;domain.kind='convex_hull';
endfunction
function names=normalize_names(v),if(isempty(v)),names={};return;endif;if(ischar(v)),names=strsplit(strrep(v,',',';'),';');else names=v;endif;names=cellfun(@strtrim,names,'UniformOutput',false);names=names(!cellfun(@isempty,names));endfunction
