function ps = gxtxt_validate_parameter_set(ps, expected_names, expected_model_id)
% Validate names/values, duplicate/missing/unexpected parameters, model id,
% and reorder according to the mathematical model's declared parameter order.
  if(nargin<2),expected_names={};endif
  if(nargin<3),expected_model_id='';endif
  if(!isstruct(ps)||!isfield(ps,'names')||!isfield(ps,'values'))
    error('gxtxt_validate_parameter_set: invalid parameter-set structure');
  endif
  names=normalize_names(ps.names); values=ps.values(:)';
  if(numel(names)!=numel(values)),error('gxtxt_validate_parameter_set: names/value count mismatch');endif
  if(any(!isfinite(values))),error('gxtxt_validate_parameter_set: values must be finite numeric scalars');endif
  if(numel(unique(names))!=numel(names)),error('gxtxt_validate_parameter_set: duplicate parameter names are not allowed');endif

  expected=normalize_names(expected_names);
  if(!isempty(expected))
    if(numel(unique(expected))!=numel(expected)),error('gxtxt_validate_parameter_set: expected parameter order contains duplicates');endif
    missing=setdiff(expected,names,'stable'); unexpected=setdiff(names,expected,'stable');
    if(!isempty(missing)),error('gxtxt_validate_parameter_set: missing parameter(s): %s',strjoin(missing,', '));endif
    if(!isempty(unexpected)),error('gxtxt_validate_parameter_set: unexpected parameter(s): %s',strjoin(unexpected,', '));endif
    order=zeros(1,numel(expected));
    for i=1:numel(expected),order(i)=find(strcmp(names,expected{i}),1);endfor
    names=names(order); values=values(order);
  endif

  if(!isfield(ps,'model_id')),ps.model_id='';endif
  if(!isempty(expected_model_id)&&!isempty(ps.model_id)&&!strcmp(strtrim(ps.model_id),strtrim(expected_model_id)))
    error('gxtxt_validate_parameter_set: model_id mismatch: file=%s expected=%s',ps.model_id,expected_model_id);
  endif
  ps.names=names; ps.values=values;
endfunction

function names=normalize_names(v)
  if(isempty(v)),names={};return;endif
  if(ischar(v)), names=strsplit(strrep(v,',',';'),';'); else names=v; endif
  names=cellfun(@strtrim,names,'UniformOutput',false);
  names=names(!cellfun(@isempty,names));
endfunction
