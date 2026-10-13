% Public data-only NUMERIC_API_v1 operation discovery for GNU Octave.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_operation_catalog_v1(query,id)
  persistent catalog;
  if(isempty(catalog)),catalog=read_catalog();endif
  if(nargin<1||strcmp(query,'list'))
    out=sort({catalog.id});return;
  endif
  if(nargin<2),error('GXTXT:Numeric','operation ID or expression name is required');endif
  if(strcmp(query,'metadata'))
    index=find(strcmp({catalog.id},id));
  elseif(strcmp(query,'expression_name'))
    index=[];
    for k=1:numel(catalog)
      if(strcmp(catalog(k).expression_name,id)&&any(strcmp(catalog(k).flags,'expression'))),index(end+1)=k;endif
    endfor
  else
    error('GXTXT:Numeric','unknown operation catalog query: %s',query);
  endif
  if(numel(index)!=1),error('GXTXT:Numeric','unknown or ambiguous numerical operation: %s',id);endif
  out=catalog(index);
endfunction

function catalog=read_catalog()
  path=fullfile(fileparts(fileparts(mfilename('fullpath'))),'operations_v1.tsv');
  fid=fopen(path,'r');if(fid<0),error('GXTXT:Numeric','operation catalog is unavailable');endif
  catalog=struct('id',{},'expression_name',{},'category',{},'bindings',{},'arity_min',{},'arity_max',{},'arguments',{},'accepted_kinds',{},'shape_semantics',{},'broadcast_semantics',{},'options',{},'result_kind',{},'result_shape',{},'nonfinite_policies',{},'unit_behavior',{},'summary',{},'capability',{},'flags',{},'expression_result_field',{},'expression_option_argument',{},'api_id',{},'api_version',{});
  unwind_protect
    while(true)
      line=fgetl(fid);if(!ischar(line)),break;endif
      line=strtrim(line);if(isempty(line)||line(1)=='#'),continue;endif
      fields=strsplit(line,'|');if(numel(fields)!=17),error('GXTXT:Numeric','invalid operation catalog record');endif
      ids=strsplit(fields{1},',');arity=strsplit(fields{5},'..');
      if(numel(arity)==1),minarity=str2double(arity{1});maxarity=minarity;
      elseif(numel(arity)==2),minarity=str2double(arity{1});maxarity=str2double(arity{2});
      else error('GXTXT:Numeric','invalid catalog arity');endif
      option_specs=struct();
      if(!strcmp(fields{10},'none'))
        specs=strsplit(fields{10},';');
        for j=1:numel(specs)
          pair=strsplit(specs{j},'=');if(numel(pair)!=2),error('GXTXT:Numeric','invalid catalog option');endif
          option_specs.(pair{1})=strsplit(pair{2},',');
        endfor
      endif
      for j=1:numel(ids)
        name=fields{2};
        if(strcmp(name,'auto')),pieces=strsplit(ids{j},'.');name=pieces{end};endif
        if(strcmp(name,'none')),name='';endif
        flags=strsplit(fields{17},',');result_field='values';option_argument='';
        for k=1:numel(flags)
          if(strncmp(flags{k},'result=',7)),result_field=flags{k}(8:end);endif
          if(strncmp(flags{k},'option_arg=',11)),option_argument=flags{k}(12:end);endif
        endfor
        entry=struct('id',ids{j},'expression_name',name,'category',fields{3}, ...
          'bindings',{strsplit(fields{4},',')},'arity_min',minarity,'arity_max',maxarity, ...
          'arguments',{strsplit(fields{6},',')},'accepted_kinds',{strsplit(fields{7},',')}, ...
          'shape_semantics',fields{8},'broadcast_semantics',fields{9},'options',option_specs, ...
          'result_kind',fields{11},'result_shape',fields{12}, ...
          'nonfinite_policies',{strsplit(fields{13},',')},'unit_behavior',fields{14}, ...
          'summary',fields{15},'capability',fields{16},'flags',{flags}, ...
          'expression_result_field',result_field,'expression_option_argument',option_argument, ...
          'api_id','NUMERIC_API_v1','api_version',1);
        catalog(end+1)=entry;
      endfor
    endwhile
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  if(numel(unique({catalog.id}))!=numel(catalog)),error('GXTXT:Numeric','duplicate numerical operation ID');endif
endfunction
