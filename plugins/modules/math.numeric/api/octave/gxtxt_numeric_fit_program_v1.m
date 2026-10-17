% Internal adapter for the existing CORE controlled expression grammar.
% SPDX-License-Identifier: GPL-3.0-or-later
function [programs,model]=gxtxt_numeric_fit_program_v1(model,predictors,parameters)
  model=gxtxt_numeric_fit_model_v1(model,parameters);
  if(!isstruct(model)||numel(model)!=1||!isfield(model,'expression')||!isfield(model,'parameter_ids'))
    error('GXTXT:Numeric:Model','Declared fit model requires expression and parameter_ids');
  endif
  ids=model.parameter_ids;if(ischar(ids)),ids={ids};endif
  if(!iscellstr(ids)||numel(ids)!=parameters||numel(unique(ids))!=parameters),error('GXTXT:Numeric:Model','Parameter identities must be unique and match initial parameters');endif
  if(isfield(model,'parameter_units')&&(!iscellstr(model.parameter_units)||numel(model.parameter_units)!=parameters)),error('GXTXT:Numeric:Model','Parameter units must match declared parameter order');endif
  if(!isfield(model,'predictor_ids')),model.predictor_ids={'x'};endif
  inputs=model.predictor_ids;if(ischar(inputs)),inputs={inputs};endif
  if(!iscellstr(inputs)||numel(inputs)!=predictors||numel(unique(inputs))!=predictors||!isempty(intersect(ids,inputs)))
    error('GXTXT:Numeric:Model','Predictor identities must be unique and independent of parameters');
  endif
  names=[ids(:);inputs(:)];
  for k=1:numel(names)
    if(isempty(regexp(names{k},'^[A-Za-z_][A-Za-z0-9_]*$','once'))||any(strcmp(names{k},{'pi','e'})))
      error('GXTXT:Numeric:Model','Invalid or reserved model symbol');
    endif
  endfor
  expression=model.expression;if(ischar(expression)),expression={expression};endif
  if(!iscellstr(expression)||isempty(expression)||numel(expression)>32),error('GXTXT:Numeric:Model','Expression must contain 1..32 response formulas');endif
  here=fileparts(mfilename('fullpath'));
  addpath(fullfile(here,'..','..','..','..','..','core','octave','analysis'));
  programs=cell(1,numel(expression));functions={'exp','log','sqrt','sin','cos','tan','sinh','cosh','tanh','abs','atan','erf','log10'};
  for response=1:numel(expression)
    formula=expression{response};if(numel(formula)>32768),error('GXTXT:Numeric:Model','Expression exceeds 32768 characters');endif
    tokens=gxtxt_analysis_expression_parse(formula);code=zeros(0,2);
    for k=1:numel(tokens)
      token=tokens{k};v=0;
      switch(token.kind)
        case 'num',op=0;v=str2double(token.text);if(!isfinite(v)),error('GXTXT:Numeric:Model','Nonfinite expression constant');endif
        case 'id'
          input=find(strcmp(token.text,inputs));parameter=find(strcmp(token.text,ids));
          if(!isempty(input)),op=1;v=input-1;
          elseif(!isempty(parameter)),op=2;v=parameter-1;
          elseif(strcmp(token.text,'pi')),op=0;v=pi;
          elseif(strcmp(token.text,'e')),op=0;v=exp(1);
          else error('GXTXT:Numeric:Model','Undeclared model symbol %s',token.text);endif
        case 'op'
          ops={'+','-','*','/','^','u-','u+'};index=find(strcmp(token.text,ops));
          if(isempty(index)),error('GXTXT:Numeric:Model','Unsupported expression operator');endif;op=index+2;
          if(op==7&&!isempty(code)&&code(end,1)==0),v=code(end,2);code(end,:)=[];op=23;endif
        case 'func'
          if(strcmp(token.text,'voigt_profile'))
            if(token.argc!=3),error('GXTXT:Numeric:Model','voigt_profile needs x, sigma and gamma');endif
            code(end+1,:)=[24,0];continue;
          elseif(strcmp(token.text,'logistic'))
            if(token.argc!=1),error('GXTXT:Numeric:Model','logistic needs one argument');endif
            code(end+1,:)=[25,0];continue;
          elseif(strcmp(token.text,'shockley_series'))
            if(token.argc!=4),error('GXTXT:Numeric:Model','shockley_series needs voltage, saturation current, effective thermal voltage and resistance');endif
            code(end+1,:)=[26,0];continue;
          elseif(strcmp(token.text,'minimum'))
            if(token.argc!=2),error('GXTXT:Numeric:Model','minimum needs two arguments');endif
            code(end+1,:)=[29,0];continue;
          elseif(any(strcmp(token.text,{'positive_part','exprel'})))
            if(token.argc!=1),error('GXTXT:Numeric:Model','%s needs one argument',token.text);endif
            op=27;if(strcmp(token.text,'exprel')),op=28;endif
            code(end+1,:)=[op,0];continue;
          endif
          index=find(strcmp(token.text,functions));
          if(isempty(index)||token.argc!=1),error('GXTXT:Numeric:Model','Unsupported model function or arity: %s',token.text);endif
          op=index+9;
        otherwise,error('GXTXT:Numeric:Model','Unsupported expression token');
      endswitch
      code(end+1,:)=[op,v];
    endfor
    programs{response}=code;
  endfor
  model.parameter_ids=ids(:).';model.predictor_ids=inputs(:).';model.expression=expression;
  model.expression_grammar='CORE controlled expression v1';model.compiler_version=1;
  model.source_sha256=hash('sha256',strjoin(expression,sprintf('\n')));
  model.binding_sha256=hash('sha256',jsonencode(struct('expression',{expression},'parameter_ids',{model.parameter_ids},'predictor_ids',{model.predictor_ids})));
endfunction
