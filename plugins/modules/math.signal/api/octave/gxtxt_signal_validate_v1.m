function [count,opts]=gxtxt_signal_validate_v1(operation,a,b,c,opts)
% One provider contract governs both guided-field discovery and basic input
% admission. The operation implementation remains the oracle for relational,
% model, conditioning and sample-dependent scientific requirements.
% SPDX-License-Identifier: GPL-3.0-or-later
  persistent rows;
  if(isempty(rows))
    path=fullfile(fileparts(fileparts(mfilename('fullpath'))),'operation_fields_v1.tsv');
    lines=strsplit(fileread(path),'\n');rows={};
    for k=1:numel(lines)
      line=lines{k};if(isempty(line)||line(1)=='#'),continue;endif
      fields=strsplit(line,'|','collapsedelimiters',false);
      if(numel(fields)!=13),error('GXTXT:Signal:InvalidContract','invalid provider field contract');endif
      rows{end+1}=fields;
    endfor
  endif
  count=0;
  for k=1:numel(rows)
    spec=rows{k};if(!strcmp(spec{1},operation)),continue;endif
    count+=1;name=spec{2};present=true;
    if(strcmp(spec{4},'empty')),continue;endif
    switch(name)
      case 'a',value=a;
      case 'b',value=b;
      case 'c',value=c;
      otherwise
        key=name(9:end);present=isfield(opts,key);
        % Literal defaults are owned by this same schema. Source-dependent
        % expressions stay with the numerical routine that owns those inputs.
        if(!present&&!isempty(spec{6}))
          literal=spec{6};candidate=str2double(literal);known=false;
          if(any(strcmp(spec{4},{'number','integer'}))&&isfinite(candidate)),value=candidate;known=true;
          elseif(strcmp(spec{4},'choice')),value=literal;known=true;
          elseif(strcmp(spec{4},'boolean')&&any(strcmp(literal,{'true','false'}))),value=strcmp(literal,'true');known=true;endif
          if(known),opts.(key)=value;present=true;endif
        endif
        if(present),value=opts.(key);else value=[];endif
    endswitch
    required=strcmp(spec{5},'1');
    % Omitted optional values deliberately retain the numerical owner's
    % defaults. An explicitly empty operand has the existing empty semantics.
    if(!present||isempty(value))
      if(required),error(['GXTXT:Signal:' spec{13}],'%s is required',spec{3});endif
      continue;
    endif
    type=spec{4};valid=true;
    switch(type)
      case 'choice',valid=ischar(value)&&any(strcmp(value,strsplit(spec{10},';')));
      case 'struct',valid=isstruct(value)&&isscalar(value);
      case 'boolean',valid=(islogical(value)||isnumeric(value))&&isscalar(value)&&isreal(value)&&any(value==[0 1]);
      otherwise
        valid=isnumeric(value)&&all(isfinite(real(value(:))))&&all(isfinite(imag(value(:))));
        if(any(strcmp(type,{'number','integer'}))),valid=valid&&isreal(value)&&isscalar(value);endif
        if(strcmp(type,'integer')),valid=valid&&value==fix(value);endif
    endswitch
    if(!valid),error(['GXTXT:Signal:' spec{13}],'%s has invalid %s value',spec{3},type);endif
    for bound_index=[8,9]
      text=spec{bound_index};if(isempty(text)),continue;endif
      strict=any(text(1)==['<','>']);if(strict),text=text(2:end);endif
      bound=str2double(text);
      if(!isreal(value)||!isfinite(bound)),error('GXTXT:Signal:InvalidContract','invalid real bound contract');endif
      if(bound_index==8)
        invalid=any(value(:)<bound)||(strict&&any(value(:)==bound));
      else
        invalid=any(value(:)>bound)||(strict&&any(value(:)==bound));
      endif
      if(invalid),error(['GXTXT:Signal:' spec{13}],'%s is outside its valid range',spec{3});endif
    endfor
  endfor
  if(count==0),error('GXTXT:Signal:UnknownOperation','unknown Signal operation');endif
  % These are the existing design validator's exact conditional rules. Keeping
  % them here lets discovery and preflight consult the actual execution oracle.
  contract=gxtxt_signal_constraints_v1(operation);
  if(isfield(contract,'cutoff_length_by_band'))
    band='low';if(isfield(opts,'band')),band=opts.band;endif
    domain='discrete';if(isfield(opts,'domain')),domain=opts.domain;endif
    expected=str2double(contract.cutoff_length_by_band.(band));
    if(numel(b)!=expected)
      error('GXTXT:Signal:InvalidCutoff','low/high need one edge; bandpass/stop need two');
    endif
    lower=str2double(contract.discrete_cutoff_range.exclusive_lower);upper=str2double(contract.discrete_cutoff_range.exclusive_upper);
    if(any(b(:)<=lower)||(strcmp(domain,'discrete')&&any(b(:)>=upper))||(strcmp(contract.cutoff_order,'strictly_increasing')&&any(diff(b(:))<=0)))
      error('GXTXT:Signal:InvalidCutoff','cutoff must be positive and digital cutoff below one');
    endif
    if(isfield(contract,'supported_domain'))
      if(!strcmp(domain,contract.supported_domain)),error('GXTXT:Signal:InvalidModel','FIR window design is discrete only');endif
    endif
    if(isfield(contract,'even_order_bands'))
      if(any(strcmp(band,contract.even_order_bands))&&mod(a,2)!=0),error('GXTXT:Signal:InvalidOrder','high-pass and band-stop FIR window design require even order');endif
    endif
  endif
endfunction
