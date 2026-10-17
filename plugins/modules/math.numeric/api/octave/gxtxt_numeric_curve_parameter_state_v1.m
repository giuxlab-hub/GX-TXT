% Compact editable direct-model state; all curve evaluation stays at its owner.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_curve_parameter_state_v1(model,values)
  if(!isstruct(model)||numel(model)!=1||!isfield(model,'model')||!ischar(model.model))
    error('GXTXT:Numeric','A declared curve model state is required');
  endif
  kind=model.model;ids={};units={};lower=[];upper=[];
  if(strcmp(kind,'circular_arc'))
    fields={'center_x','center_y','radius','angle_start','angle_end'};
    initial=zeros(5,1);for k=1:5,initial(k)=model.(fields{k});endfor
    ids=fields;units={'coordinate','coordinate','coordinate','rad','rad'};
    state=struct('model',kind,'parametric',true);
  elseif(any(strcmp(kind,{'quadratic_bezier','cubic_bezier'})))
    degree=2;if(strcmp(kind,'cubic_bezier')),degree=3;endif
    if(!isequal(size(model.control_points),[degree+1,2])),error('GXTXT:Numeric','Control-point shape differs from the declared Bezier degree');endif
    initial=model.control_points(:);state=struct('model',kind,'parametric',true,'degree',degree,'parameter_start',0,'parameter_end',1);
    for axis={'x','y'},for k=0:degree,ids{end+1}=sprintf('%s_control_%d',axis{1},k);units{end+1}='coordinate';endfor;endfor
  elseif(strcmp(kind,'parametric_polynomial'))
    degree=model.degree;
    if(!isscalar(degree)||degree<1||degree>12||degree!=fix(degree)||!isequal(size(model.coefficients),[degree+1,2])||!strcmp(model.topology,'open'))
      error('GXTXT:Numeric','Open parametric polynomial declaration is invalid');
    endif
    initial=model.coefficients(:);state=struct('model',kind,'parametric',true,'degree',degree,'topology','open','parameter_start',0,'parameter_end',1);
    for axis={'x','y'},for k=degree:-1:0,ids{end+1}=sprintf('%s_power_%d',axis{1},k);units{end+1}='coordinate';endfor;endfor
    for field={'parameterization','parameter_source_start','parameter_source_end','parameter_normalization_span'}
      if(isfield(model,field{1})),state.(field{1})=model.(field{1});endif
    endfor
  elseif(strcmp(kind,'fourier'))
    order=model.order;
    if(!isscalar(order)||order<1||order>63||order!=fix(order)||numel(model.coefficients)!=2*order+1||!isscalar(model.period)||!isfinite(model.period)||model.period<=0||!isscalar(model.origin)||!isfinite(model.origin))
      error('GXTXT:Numeric','Fourier editable declaration requires order1..63 and a finite positive period');
    endif
    initial=model.coefficients(:);state=struct('model',kind,'parametric',false,'order',order,'period',model.period,'origin',model.origin,'fundamental_angular_frequency',2*pi/model.period);
    ids={'constant'};for k=1:order,ids{end+1}=sprintf('cos_%d',k);ids{end+1}=sprintf('sin_%d',k);endfor
    units=repmat({'response'},1,numel(ids));
  else
    error('GXTXT:Numeric','This curve model has no supported finite editable parameter declaration');
  endif
  if(!isnumeric(initial)||!isreal(initial)||any(!isfinite(initial))),error('GXTXT:Numeric','Curve parameters must be finite real numbers');endif
  if(isempty(values)),values=initial;endif
  if(!isnumeric(values)||!isreal(values)||!isvector(values)||numel(values)!=numel(initial)||any(!isfinite(values(:))))
    error('GXTXT:Numeric','Manual curve parameter count or finite real values differ');
  endif
  values=double(values(:));lower=-Inf(size(values));upper=Inf(size(values));
  if(strcmp(kind,'circular_arc'))
    lower(3)=realmin;
    if(values(3)<=0||abs(values(5)-values(4))<1e-12),error('GXTXT:Numeric','Circular arc needs a positive radius and a nonzero oriented angle interval');endif
    for k=1:5,state.(fields{k})=values(k);endfor
    state.orientation=sign(values(5)-values(4));
  elseif(any(strcmp(kind,{'quadratic_bezier','cubic_bezier'})))
    state.control_points=reshape(values,degree+1,2);
  elseif(strcmp(kind,'parametric_polynomial')),state.coefficients=reshape(values,degree+1,2);
  else,state.coefficients=values;endif
  state.parameters=values;
  out=struct('schema','gxtxt.curve_parameter_state.v1','model',state,'parameter_ids',{ids},'unit_roles',{units},...
    'parameters',values,'lower_bounds',lower,'upper_bounds',upper,'fixed_mask',false(size(values)),...
    'nonlinear_optimization',false,'accepted',false,'initial_values_affect_direct_solver',false);
endfunction
