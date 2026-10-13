function domain = gxtxt_read_model_domain(path, expected_inputs, expected_model_id)
% Read a GX-TXT model/training domain CSV.
% The header names model INPUT variables; subsequent numeric rows are vertices
% (or training points whose convex hull defines the valid domain).
% Optional comment metadata: '# model_id=...' and '# domain_kind=convex_hull'.
  if(nargin<2),expected_inputs={};endif
  if(nargin<3),expected_model_id='';endif
  if(exist(path,'file')!=2),error('gxtxt_read_model_domain: file not found: %s',path);endif
  fid=fopen(path,'r');if(fid<0),error('gxtxt_read_model_domain: cannot open %s',path);endif
  unwind_protect
    header='';model_id='';kind='convex_hull';
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      t=strtrim(line);if(isempty(t)),continue;endif
      if(t(1)=='#'||t(1)==';')
        tok=regexp(t,'^[#;]\s*model_id\s*=\s*(.+?)\s*$','tokens','once');if(!isempty(tok)),model_id=strtrim(tok{1});endif
        tok=regexp(t,'^[#;]\s*domain_kind\s*=\s*(.+?)\s*$','tokens','once');if(!isempty(tok)),kind=lower(strtrim(tok{1}));endif
        continue;
      endif
      header=line;break;
    endwhile
    if(isempty(header)),error('gxtxt_read_model_domain: missing CSV header');endif
    delim=detect_delimiter(header); names=split_fields(header,delim); data=[];
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      t=strtrim(line);if(isempty(t)||t(1)=='#'||t(1)==';'),continue;endif
      fields=split_fields(line,delim);
      if(numel(fields)!=numel(names)),error('gxtxt_read_model_domain: row has %d fields; expected %d',numel(fields),numel(names));endif
      row=zeros(1,numel(names));
      for i=1:numel(names),row(i)=str2double(fields{i});if(!isfinite(row(i))),error('gxtxt_read_model_domain: non-numeric domain coordinate');endif;endfor
      data(end+1,:)=row;
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  domain=struct('path',path,'kind',kind,'model_id',model_id,'input_names',{names},'vertices',data);
  domain=gxtxt_validate_model_domain(domain,expected_inputs,expected_model_id);
endfunction

function delim=detect_delimiter(line)
  counts=[numel(strfind(line,',')),numel(strfind(line,';')),numel(strfind(line,sprintf('\t')))];[~,i]=max(counts);
  if(i==2),delim=';';elseif(i==3),delim=sprintf('\t');else delim=',';endif
endfunction
function fields=split_fields(line,delim),fields=strsplit(line,delim);fields=cellfun(@(s) strtrim(strip_quotes(s)),fields,'UniformOutput',false);endfunction
function s=strip_quotes(s),s=strtrim(s);if(numel(s)>=2&&s(1)=='"'&&s(end)=='"'),s=s(2:end-1);endif;endfunction
