function ps = gxtxt_read_parameter_set(path, expected_names, expected_model_id)
% Read and validate a GX-TXT parameter set CSV.
% Required columns: parameter,value
% Optional metadata: comment '# model_id=...' / '; model_id=...' or model_id column.
% If expected_names is supplied, output is reordered to that model parameter order.

  if (nargin < 2), expected_names={}; endif
  if (nargin < 3), expected_model_id=''; endif
  if (exist(path,'file') != 2), error('gxtxt_read_parameter_set: file not found: %s',path); endif

  fid=fopen(path,'r'); if(fid<0), error('gxtxt_read_parameter_set: cannot open %s',path); endif
  unwind_protect
    header=''; model_meta=''; delim=',';
    while (true)
      line=fgetl(fid); if(!ischar(line)), break; endif
      t=strtrim(line); if(isempty(t)), continue; endif
      if (t(1)=='#' || t(1)==';')
        tok=regexp(t,'^[#;]\s*model_id\s*=\s*(.+?)\s*$','tokens','once');
        if(!isempty(tok)), model_meta=strtrim(tok{1}); endif
        continue;
      endif
      header=line; break;
    endwhile
    if(isempty(header)), error('gxtxt_read_parameter_set: missing CSV header'); endif
    delim=detect_delimiter(header);
    cols=split_fields(header,delim);
    low=cellfun(@lower,cols,'UniformOutput',false);
    ip=find(strcmp(low,'parameter'),1); iv=find(strcmp(low,'value'),1); im=find(strcmp(low,'model_id'),1);
    if(isempty(ip)||isempty(iv)), error('gxtxt_read_parameter_set: required columns are parameter,value'); endif

    names={}; values=[]; model_values={};
    while (true)
      line=fgetl(fid); if(!ischar(line)), break; endif
      t=strtrim(line); if(isempty(t)), continue; endif
      if(t(1)=='#' || t(1)==';')
        tok=regexp(t,'^[#;]\s*model_id\s*=\s*(.+?)\s*$','tokens','once');
        if(!isempty(tok) && isempty(model_meta)), model_meta=strtrim(tok{1}); endif
        continue;
      endif
      fields=split_fields(line,delim);
      if(numel(fields)<max([ip iv im 0])), error('gxtxt_read_parameter_set: malformed row: %s',line); endif
      name=strtrim(fields{ip}); if(isempty(name)), error('gxtxt_read_parameter_set: empty parameter name'); endif
      val=str2double(strtrim(fields{iv}));
      if(!isfinite(val)), error('gxtxt_read_parameter_set: non-numeric value for parameter %s',name); endif
      names{end+1}=name; values(end+1)=val;
      if(!isempty(im)), model_values{end+1}=strtrim(fields{im}); endif
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect

  if(isempty(names)), error('gxtxt_read_parameter_set: parameter set is empty'); endif
  model_id=model_meta;
  if(!isempty(model_values))
    nonempty=model_values(!cellfun(@isempty,model_values));
    if(!isempty(nonempty))
      u=unique(nonempty);
      if(numel(u)>1), error('gxtxt_read_parameter_set: inconsistent model_id values'); endif
      if(!isempty(model_id) && !strcmp(model_id,u{1})), error('gxtxt_read_parameter_set: conflicting model_id metadata'); endif
      model_id=u{1};
    endif
  endif

  ps=struct('path',path,'names',{names},'values',values,'model_id',model_id);
  ps=gxtxt_validate_parameter_set(ps,expected_names,expected_model_id);
endfunction

function delim=detect_delimiter(line)
  counts=[numel(strfind(line,',')),numel(strfind(line,';')),numel(strfind(line,sprintf('\t')))];
  [~,i]=max(counts); if(i==2),delim=';';elseif(i==3),delim=sprintf('\t');else delim=',';endif
endfunction

function fields=split_fields(line,delim)
  fields=strsplit(line,delim);
  fields=cellfun(@(s) strtrim(strip_quotes(s)),fields,'UniformOutput',false);
endfunction

function s=strip_quotes(s)
  s=strtrim(s);
  if(numel(s)>=2 && s(1)=='"' && s(end)=='"'), s=s(2:end-1); endif
endfunction
