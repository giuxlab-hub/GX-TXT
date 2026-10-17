% Freeze evaluation, not estimation, into independently runnable source.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_model_export_v1(model,options)
  if(ischar(model)),model=gxtxt_numeric_model_state_decode_v1(model);endif
  if(!isstruct(model)||numel(model)!=1||!isstruct(options)||numel(options)!=1)
    error('GXTXT:Numeric:Export','Model export needs one saved model and options struct');
  endif
  if(isfield(model,'schema')&&strcmp(model.schema,'gxtxt.rational_state.v1')),model=gxtxt_numeric_v1('rational_model_restore',model);endif
  if(isfield(model,'kind')&&strcmp(model.kind,'surface')),out=surface_export(model,options);return;endif
  allowed={'name','domain','orientation','delta_u','delta_v','x_unit','y_unit','query_unit','source_reference','parameter_units','polar_frame','positive_predictor','model_id','parameter_ids','parameter_values'};
  if(any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric:Export','Unknown model export option');endif
  name=opt(options,'name','fit_model');
  if(!ischar(name)||isempty(regexp(name,'^fit_[A-Za-z][A-Za-z0-9_]{0,55}$','once')))
    error('GXTXT:Numeric:Export','Function name must start with fit_ followed by a letter and at most 55 letters, digits or underscores');
  endif
  domain=opt(options,'domain',[]);
  if(!isnumeric(domain)||!isreal(domain)||numel(domain)!=2||any(!isfinite(domain))||domain(2)<=domain(1))
    error('GXTXT:Numeric:Export','Export requires an explicit increasing finite evaluated domain');
  endif
  orientation=opt(options,'orientation','y_of_x');
  if(!any(strcmp(orientation,{'y_of_x','x_of_y','r_of_theta','parametric'}))),error('GXTXT:Numeric:Export','Unknown orientation');endif
  du=opt(options,'delta_u',0);dv=opt(options,'delta_v',0);finite([du,dv]);
  if(!isscalar(du)||!isscalar(dv)),error('GXTXT:Numeric:Export','Translations must be scalar');endif
  parametric=false;positive=false;equation='';py={};oc={};coefficients=struct();registered=[];implicit=[];complex_projection=[];rational=[];implicit_py={};implicit_oc={};
  if(isfield(model,'kind'))
    kind=model.kind;
    if(strcmp(kind,'rational'))
      rational=gxtxt_numeric_rational_v1('validate',model);
      if(!any(strcmp(orientation,{'y_of_x','x_of_y'}))||du!=0||dv!=0),error('GXTXT:Numeric:Export','Rational export requires untranslated physical response coordinates');endif
      expected=struct('query_unit',rational.predictor_unit,'model_id','math.numeric.rational');
      if(strcmp(orientation,'y_of_x')),expected.x_unit=rational.predictor_unit;expected.y_unit=rational.response_unit;
      else expected.y_unit=rational.predictor_unit;expected.x_unit=rational.response_unit;endif
      for field=fieldnames(expected).'
        key=field{1};if(isfield(options,key)&&!strcmp(options.(key),expected.(key))),error('GXTXT:Numeric:Export','Rational export metadata conflicts with captured %s',key);endif
        options.(key)=expected.(key);
      endfor
      for pair={'parameter_ids','parameter_ids';'parameter_values','parameters';'parameter_units','parameter_units'}.'
        key=pair{1};actual=rational.(pair{2});
        if(isfield(options,key)&&!isequaln(options.(key)(:),actual(:))),error('GXTXT:Numeric:Export','Rational export parameter identity changed');endif
        options.(key)=actual;
      endfor
      rational_domain=gxtxt_numeric_rational_v1('guard',rational,[min(domain(1),rational.declared_domain(1)),max(domain(2),rational.declared_domain(2))]);
      p=rational.parameters(:);[programs,compiled]=gxtxt_numeric_fit_program_v1(rational.formula_model,1,numel(p));
      [py,oc]=assign(py,oc,'p',p.');[pe,oe,equation]=expression(programs{1});py=[py,pe];oc=[oc,oe];
      coefficients=struct('parameters',p,'parameter_ids',{rational.parameter_ids},'rational_declaration_sha256',rational.declaration_sha256);
    elseif(strcmp(kind,'complex_projection'))
      complex_projection=gxtxt_numeric_complex_retained_v1('validate',model);
      if(!strcmp(orientation,'y_of_x')||du!=0||dv!=0||domain(1)<=0),error('GXTXT:Numeric:Export','Complex export requires untranslated physical frequency coordinates and a positive domain');endif
      physical=complex_projection.model;channel=complex_projection.channel;positive=true;
      expected=struct('x_unit',physical.predictor_unit,'query_unit',physical.predictor_unit,'y_unit',complex_projection.response_unit,'model_id','math.numeric.complex_response');
      for field=fieldnames(expected).'
        key=field{1};if(isfield(options,key)&&!strcmp(options.(key),expected.(key))),error('GXTXT:Numeric:Export','Complex export metadata conflicts with captured %s',key);endif
        options.(key)=expected.(key);
      endfor
      for pair={'parameter_ids','parameter_ids';'parameter_values','parameters';'parameter_units','parameter_units'}.'
        key=pair{1};actual=physical.(pair{2});
        if(isfield(options,key)&&!isequaln(options.(key)(:),actual(:))),error('GXTXT:Numeric:Export','Complex export parameter identity differs from the retained model');endif
        options.(key)=actual;
      endfor
      p=physical.parameters(:);[programs,compiled]=gxtxt_numeric_fit_program_v1(physical.physical_model,1,numel(p));
      [py,oc]=assign(py,oc,'p',p.');equations=cell(1,2);
      for component=1:2
        [pe,oe,equations{component}]=expression(programs{2*channel-2+component});py=[py,pe];oc=[oc,oe];
        variable='real_part';if(component==2),variable='imaginary_part';endif
        py{end+1}=[variable ' = np.broadcast_to(y, u.shape).copy()'];oc{end+1}=[variable '=y+zeros(size(u));'];
      endfor
      switch(complex_projection.projection)
        case 'real',py{end+1}='y = real_part';oc{end+1}='y=real_part;';
        case 'imaginary',py{end+1}='y = imaginary_part';oc{end+1}='y=imaginary_part;';
        case {'magnitude','db20'}
          py{end+1}='y = np.hypot(real_part, imaginary_part)';oc{end+1}='y=hypot(real_part,imaginary_part);';
          if(strcmp(complex_projection.projection,'db20'))
            py{end+1}='if np.any(y <= 0): raise ValueError("Zero-amplitude dB projection is unavailable")';
            oc{end+1}='if(any(y<=0)),error("Zero-amplitude dB projection is unavailable");endif';
            py{end+1}=sprintf('y = 20*(np.log10(y)-np.log10(%s))',num(complex_projection.reference));
            oc{end+1}=sprintf('y=20*(log10(y)-log10(%s));',num(complex_projection.reference));
          endif
      endswitch
      equation=[strrep(equations{1},'f(u)=','R(u)='),'\quad ',strrep(equations{2},'f(u)=','I(u)='),'\quad \mathrm{projection}=',complex_projection.projection];
      coefficients=struct('parameters',p,'parameter_ids',{physical.parameter_ids},'channel_id',model.channel_id,'projection',model.projection,'complex_declaration_sha256',model.declaration_sha256);
    elseif(strcmp(kind,'implicit_branch'))
      implicit=gxtxt_numeric_implicit_retained_v1('validate',model);
      if(!strcmp(orientation,implicit.orientation)||du!=0||dv!=0),error('GXTXT:Numeric:Export','Implicit export requires its declared response branch and physical coordinates');endif
      branch=implicit.branch;
      if(domain(1)<branch.independent_domain(1)||domain(2)>branch.independent_domain(2)),error('GXTXT:Numeric:Export','Export domain exceeds the declared implicit branch');endif
      p=implicit.model.parameters(:);[programs,compiled]=gxtxt_numeric_fit_program_v1(implicit.model.equation_model,2,numel(p));
      coordinates={'u','v'};if(branch.response_index==1),coordinates={'v','u'};endif
      [pe,oe,equation]=expression(programs{1},coordinates);
      implicit_py={'def _implicit_equation(u, v, p):'};implicit_oc={'function y=implicit_equation(u,v,p)'};
      for line=pe,implicit_py{end+1}=['    ',line{1}];endfor
      implicit_py{end+1}='    return y';
      implicit_oc=[implicit_oc,oe,{'endfunction'}];
      [py,oc]=assign(py,oc,'p',p.');
      py{end+1}=sprintf('y = _implicit_branch(u, p, %s, %s, %s, %s, %d)',num(branch.bracket(1)),num(branch.bracket(2)),num(branch.x_tolerance),num(branch.response_tolerance),branch.max_iterations);
      oc{end+1}=sprintf('y = implicit_branch(u, p, %s, %s, %s, %s, %d);',num(branch.bracket(1)),num(branch.bracket(2)),num(branch.x_tolerance),num(branch.response_tolerance),branch.max_iterations);
      equation=[strrep(equation,'f(u)=','0='),'\quad \text{on the explicitly declared continuous branch}'];
      coefficients=struct('parameters',p,'parameter_ids',{implicit.model.parameter_ids},'branch',branch,'equation_declaration_sha256',implicit.model.declaration_sha256);
    elseif(strcmp(kind,'registered_callback_source'))
      registered=gxtxt_numeric_registered_model_export_v1(model,options);
      [py,oc]=assign(py,oc,'p',model.parameters(:));
      py{end+1}=['y = _registered_response(u, p, ',registered.spec_json,')'];
      oc{end+1}=['y = registered_response(u, p, jsondecode(''',registered.spec_json,'''));'];
      equation=['f(u)=\operatorname{registered}_{\mathrm{',model.source_sha256(1:16),'}}(\mathbf{p},u)'];
      coefficients=struct('parameters',model.parameters(:),'parameter_ids',{model.parameter_ids},'executable_source_sha256',model.source_sha256);
    elseif(strcmp(kind,'polynomial_export'))
      c=model.coefficients(:);center=0;scale=1;
      if(isfield(model,'scaled_coefficients'))
        c=model.scaled_coefficients(:);center=model.x_center;scale=model.x_scale;
      endif
      finite([c;center;scale]);if(!isscalar(center)||!isscalar(scale)||scale<=0),error('GXTXT:Numeric:Export','Invalid polynomial scaling');endif
      [py,oc]=assign(py,oc,'c',c.');
      py{end+1}=sprintf('y = np.polyval(c.ravel(), (u - %s) / %s)',num(center),num(scale));
      oc{end+1}=sprintf('y = polyval(c, (u - %s) / %s);',num(center),num(scale));
      equation=sprintf('f(u)=\\sum_{j=0}^{%d} c_j ((u-(%s))/(%s))^{%d-j}',numel(c)-1,num(center),num(scale),numel(c)-1);
      coefficients=struct('c',c,'center',center,'scale',scale,'physical_coefficients',model.coefficients(:));
    else
      p=model.parameters(:);finite(p);
      [programs,compiled]=gxtxt_numeric_fit_program_v1(model,1,numel(p));
      if(numel(programs)!=1),error('GXTXT:Numeric:Export','Curve export requires one response');endif
      if(isfield(model,'source_sha256')&&!strcmp(model.source_sha256,compiled.source_sha256)),error('GXTXT:Numeric:Export','Frozen expression SHA mismatch');endif
      positive=strcmp(kind,'power_law')||(isfield(compiled,'input_constraints')&&strcmp(compiled.input_constraints.domain,'positive_real'));
      [py,oc]=assign(py,oc,'p',p.');
      [pe,oe,equation]=expression(programs{1});py=[py,pe];oc=[oc,oe];
      coefficients=struct('parameters',p,'parameter_ids',{compiled.parameter_ids},'expression_source_sha256',compiled.source_sha256);
    endif
  elseif(isfield(model,'model'))
    kind=model.model;parametric=any(strcmp(kind,{'circular_arc','quadratic_bezier','cubic_bezier','parametric_polynomial','parametric_spline'}));
    switch(kind)
      case 'circular_arc'
        c=[model.center_x,model.center_y,model.radius,model.angle_start,model.angle_end];finite(c);
        [py,oc]=assign(py,oc,'c',c);
        py=[py,{'a = c[0, 3] + u * (c[0, 4] - c[0, 3])','x = c[0, 0] + c[0, 2] * np.cos(a)','y = c[0, 1] + c[0, 2] * np.sin(a)'}];
        oc=[oc,{'a=c(4)+u*(c(5)-c(4));','x=c(1)+c(3)*cos(a);','y=c(2)+c(3)*sin(a);'}];
        equation='(x_f(t),y_f(t))=(c_0+c_2\\cos a,c_1+c_2\\sin a),\\quad a=c_3+t(c_4-c_3)';coefficients=struct('c',c);
      case {'quadratic_bezier','cubic_bezier'}
        c=model.control_points;d=rows(c)-1;finite(c);
        if(columns(c)!=2||!any(d==[2,3])),error('GXTXT:Numeric:Export','Invalid Bezier controls');endif
        [py,oc]=assign(py,oc,'c',c);py=[py,{'x = np.zeros_like(u)','y = np.zeros_like(u)'}];oc=[oc,{'x=zeros(size(u)); y=x;'}];
        for j=0:d
          py{end+1}=sprintf('b = %s * (1-u)**%d * u**%d',num(nchoosek(d,j)),d-j,j);
          py{end+1}=sprintf('x += b*c[%d, 0]; y += b*c[%d, 1]',j,j);
          oc{end+1}=sprintf('b=%s*(1-u).^%d.*u.^%d; x+=b*c(%d,1); y+=b*c(%d,2);',num(nchoosek(d,j)),d-j,j,j+1,j+1);
        endfor
        equation=sprintf('(x_f(t),y_f(t))=\\sum_{j=0}^{%d}\\binom{%d}{j}(1-t)^{%d-j}t^j C_j',d,d,d);coefficients=struct('C',c);
      case 'parametric_polynomial'
        c=model.coefficients;finite(c);[py,oc]=assign(py,oc,'c',c);
        py=[py,{'x = np.polyval(c[:, 0], u)','y = np.polyval(c[:, 1], u)'}];oc=[oc,{'x=polyval(c(:,1),u); y=polyval(c(:,2),u);'}];
        equation=sprintf('(x_f(t),y_f(t))=\\sum_{j=0}^{%d} C_j t^{%d-j}',rows(c)-1,rows(c)-1);coefficients=struct('C',c);
      case {'akima','bspline','pchip','smoothing_spline','parametric_spline'}
        normalized=false;
        if(any(strcmp(kind,{'akima','bspline'})))
          model=gxtxt_numeric_knot_splines_v1('validate',model);knots=model.knots;cy=model.coefficients_y;cx=[];
          if(!any(strcmp(orientation,{'y_of_x','x_of_y'}))),error('GXTXT:Numeric:Export','Knot model export requires a physical scalar response orientation');endif
          expected=struct('model_id',['math.numeric.' kind],'query_unit',model.x_unit,'x_unit',model.x_unit,'y_unit',model.y_unit);
          if(strcmp(orientation,'x_of_y')),expected.x_unit=model.y_unit;expected.y_unit=model.x_unit;endif
          for field=fieldnames(expected).'
            key=field{1};if(isfield(options,key)&&!strcmp(options.(key),expected.(key))),error('GXTXT:Numeric:Export','Knot model export cannot relabel physical units or scientific identity');endif
            options.(key)=expected.(key);
          endfor
        elseif(strcmp(kind,'pchip'))
          pp=pchip(model.source_x,model.source_y);knots=pp.breaks(:);cy=pp.coefs;cx=[];
        elseif(strcmp(kind,'smoothing_spline'))
          knots=model.source_x(:);h=diff(knots);v=model.smoothed_y(:);m=model.second_derivatives(:);
          cy=[diff(m)./(6*h),m(1:end-1)/2,diff(v)./h-h.*(2*m(1:end-1)+m(2:end))/6,v(1:end-1)];cx=[];
        else
          knots=model.knots(:);cx=model.coefficients_x;cy=model.coefficients_y;normalized=true;
        endif
        finite([knots;cy(:);cx(:)]);
        if(any(diff(knots)<=0)||rows(cy)!=numel(knots)-1||columns(cy)!=4),error('GXTXT:Numeric:Export','Invalid piecewise cubic state');endif
        if(domain(1)+(1-parametric)*du<knots(1)||domain(2)+(1-parametric)*du>knots(end)),error('GXTXT:Numeric:Export','Export domain exceeds frozen interpolation knots');endif
        [py,oc]=assign(py,oc,'knots',knots.');[py,oc]=assign(py,oc,'cy',cy);
        py{end+1}=sprintf('y = _piecewise(u, knots.ravel(), cy, %s)',ternary(normalized,'True','False'));
        oc{end+1}=sprintf('y = piecewise(u, knots, cy, %d);',normalized);
        if(parametric)
          [py,oc]=assign(py,oc,'cx',cx);py{end+1}='x = _piecewise(u, knots.ravel(), cx, True)';oc{end+1}='x=piecewise(u,knots,cx,true);';
        endif
        equation='f(u)=((c_{i,0}z+c_{i,1})z+c_{i,2})z+c_{i,3},\\quad k_i\\le u\\le k_{i+1}';
        if(normalized),equation=[equation,',\\ z=(u-k_i)/(k_{i+1}-k_i)'];else equation=[equation,',\\ z=u-k_i'];endif
        if(parametric),equation=[equation,';\\quad x_f,y_f\\text{ use }C_x,C_y\\text{ respectively}'];endif
        coefficients=struct('knots',knots,'C_y',cy,'C_x',cx);
      case 'fourier'
        c=model.coefficients(:);finite([c;model.origin;model.fundamental_angular_frequency]);[py,oc]=assign(py,oc,'c',c.');
        py{end+1}=sprintf('a = (u - %s) * %s',num(model.origin),num(model.fundamental_angular_frequency));
        oc{end+1}=sprintf('a = (u - %s) * %s;',num(model.origin),num(model.fundamental_angular_frequency));
        py{end+1}='y = np.full_like(u, c[0, 0])';oc{end+1}='y=c(1)*ones(size(u));';
        for j=1:model.order
          py{end+1}=sprintf('y += c[0, %d]*np.cos(%d*a) + c[0, %d]*np.sin(%d*a)',2*j-1,j,2*j,j);
          oc{end+1}=sprintf('y += c(%d)*cos(%d*a) + c(%d)*sin(%d*a);',2*j,j,2*j+1,j);
        endfor
        equation=sprintf('f(u)=c_0+\\sum_{j=1}^{%d}(c_{2j-1}\\cos(ja)+c_{2j}\\sin(ja)),\\quad a=(u-(%s))(%s)',model.order,num(model.origin),num(model.fundamental_angular_frequency));
        coefficients=struct('c',c,'origin',model.origin,'omega',model.fundamental_angular_frequency);
      otherwise,error('GXTXT:Numeric:Export','Unsupported saved curve model');
    endswitch
  else,error('GXTXT:Numeric:Export','Saved model lacks its scientific identity');endif
  if(parametric!=strcmp(orientation,'parametric')),error('GXTXT:Numeric:Export','Model and orientation differ');endif
  if(parametric&&(domain(1)<0||domain(2)>1)),error('GXTXT:Numeric:Export','Parametric export domain must lie in [0,1]');endif
  if(!parametric),py{end+1}='x = q';oc{end+1}='x=q;';else
    py{end+1}=sprintf('x = x - %s',num(du));oc{end+1}=sprintf('x = x - %s;',num(du));
  endif
  py{end+1}=sprintf('y = np.broadcast_to(y, q.shape) - %s',num(dv));oc{end+1}=sprintf('y = y + zeros(size(q)) - %s;',num(dv));
  mapping=sprintf('u=q+(%s),\\quad (X,Y)=(q,f(u)-(%s))',num(du),num(dv));
  if(parametric),mapping=sprintf('(X,Y)=(x_f(t)-(%s),y_f(t)-(%s))',num(du),num(dv));endif
  if(strcmp(orientation,'x_of_y'))
    py{end+1}='x, y = y, x';oc{end+1}='temp=x; x=y; y=temp;';mapping=sprintf('u=q+(%s),\\quad (X,Y)=(f(u)-(%s),q)',num(du),num(dv));
  elseif(strcmp(orientation,'r_of_theta'))
    frame=opt(options,'polar_frame',struct());
    defaults=struct('origin',[0,0],'theta_zero',0,'clockwise',false,'angle_unit','rad','unwrap_policy','cut','angle_cut',0);
    for field=fieldnames(defaults).',if(!isfield(frame,field{1})),frame.(field{1})=defaults.(field{1});endif;endfor
    checked=gxtxt_numeric_v1('cartesian_coordinates',domain(:),ones(2,1),frame); %#ok
    factor=1;if(strcmp(frame.angle_unit,'deg')),factor=pi/180;endif
    direction=1;if(frame.clockwise),direction=-1;endif
    py=[py,{'if np.any(y < 0): raise ValueError("Negative physical radius")',sprintf('a = %s + q * %s',num(frame.theta_zero),num(direction*factor)),sprintf('x, y = %s + y*np.cos(a), %s + y*np.sin(a)',num(frame.origin(1)),num(frame.origin(2))) }];
    oc=[oc,{'if(any(y<0)),error("Negative physical radius");endif',sprintf('a = %s + q * %s;',num(frame.theta_zero),num(direction*factor)),sprintf('x = %s + y.*cos(a); y = %s + y.*sin(a);',num(frame.origin(1)),num(frame.origin(2)))}];
    mapping=sprintf('r=f(q+(%s))-(%s),\\ a=(%s)+q(%s),\\ (X,Y)=((%s)+r\\cos a,(%s)+r\\sin a)',num(du),num(dv),num(frame.theta_zero),num(direction*factor),num(frame.origin(1)),num(frame.origin(2)));
  endif
  declared_positive=opt(options,'positive_predictor',false);
  if(!isscalar(declared_positive)||!any(declared_positive==[0,1])),error('GXTXT:Numeric:Export','Invalid positive-domain flag');endif
  positive=positive||declared_positive;
  meta=struct('schema','gxtxt.independent_model.v1','model',opt(options,'model_id',kind),'evaluation_representation',kind,'function_name',name,'orientation',orientation,'domain',domain(:).',...
    'x_unit',opt(options,'x_unit','unspecified'),'y_unit',opt(options,'y_unit','unspecified'),'query_unit',opt(options,'query_unit','unspecified'),...
    'source_reference',opt(options,'source_reference','NUMERIC_API_v1 saved model'),'parameter_units',{opt(options,'parameter_units',{})},...
    'precision','17 significant decimal digits, binary64 evaluation','query_contract','finite real scalar or vector; Nx2 physical X/Y output; outside evaluated domain refused',...
    'license','GPL-3.0-or-later','python_dependencies','NumPy; SciPy for erf or Voigt expressions','octave_dependencies','GNU Octave core; no GX-TXT runtime',...
    'coefficient_order','arrays in source order; polynomial and cubic powers descending','comparison_tolerance','abs(error) <= 5e-11 * max(1,abs(reference)); assess ill-conditioned expressions separately');
  if(!isempty(implicit))
    meta.implicit_branch=implicit.branch;meta.implicit_declaration_sha256=implicit.model.declaration_sha256;
    meta.equation_residual_mode=implicit.model.residual_mode;meta.branch_uniqueness='not_certified';
    meta.comparison_tolerance='Root coordinate tolerance and equation response tolerance are explicit in implicit_branch; assess root conditioning and do not assume global uniqueness';
    meta.query_contract='finite real scalar or vector in the declared domain; verified bracket roots only; an unavailable root raises an error; no fit or uncertainty';
  endif
  if(isfield(model,'schema')&&strcmp(model.schema,'gxtxt.knot_spline.v1'))
    meta.knot_model=struct('model',model.model,'degree',model.degree,'knots',model.knots,'boundary_condition',model.boundary_condition,...
      'endpoint_slopes',model.endpoint_slopes,'continuity_order',model.continuity_order,'method_class',model.method_class,'state_sha256',model.state_sha256);
  endif
  if(!isempty(complex_projection))
    meta.complex_channel_id=model.channel_id;meta.complex_projection=model.projection;meta.complex_declaration_sha256=model.declaration_sha256;
    meta.complex_recipe=model.recipe;meta.complex_component_unit=complex_projection.model.channel_units{complex_projection.channel};
    if(isfield(model,'reference')),meta.complex_reference=model.reference;endif
    meta.query_contract='positive finite frequency scalar or vector in the retained domain; Nx2 physical frequency/projection output; zero-amplitude dB raises an error; no fit or uncertainty';
  endif
  if(!isempty(rational))
    meta.rational_recipe=rational.recipe;
    for k=1:numel(meta.rational_recipe.parameters)
      meta.rational_recipe.parameters{k}.lower=sprintf('%.17g',rational.recipe.parameters{k}.lower);
      meta.rational_recipe.parameters{k}.upper=sprintf('%.17g',rational.recipe.parameters{k}.upper);
    endfor
    meta.rational_bound_encoding='signed_decimal_or_Inf_text';meta.rational_domain=rational_domain;
    meta.rational_observation_domain=opt(rational,'observation_domain',rational.declared_domain);
    meta.rational_declaration_sha256=rational.declaration_sha256;
    meta.query_contract='finite real scalar or vector; exact integer conversion; exported interval passed the rational denominator guard; no factor cancellation or fitting';
  endif
  meta.accepted_parameter_ids=opt(options,'parameter_ids',{});meta.accepted_parameter_values=opt(options,'parameter_values',[]);
  meta.parameter_units_order='accepted_parameter_ids; evaluation constants may use a different basis';
  if(!isempty(registered))
    for field=fieldnames(registered.metadata).',meta.(field{1})=registered.metadata.(field{1});endfor
  endif
  meta.coefficient_units_note='Constants use the displayed fit-space formula and declared axis units. Parametric t is dimensionless; vector coordinate constants follow X then Y.';
  if(strcmp(kind,'polynomial_export'))
    meta.coefficient_units_note='c is in descending powers of z=(u-center)/scale. With scaled_coefficients every c has the response unit; center and scale have the independent-axis unit. physical_coefficients are in descending powers of fit-space u. Accepted parameter IDs/values/units describe the original estimator coefficients, not the scaled c array.';
  elseif(strcmp(kind,'fourier')),meta.coefficient_units_note='Every Fourier c has the response unit; origin has the independent-axis unit and omega its reciprocal.';endif
  meta_json=jsonencode(meta);
  metadata_lines={};
  for key=fieldnames(meta).'
    line=[key{1},' = ',strrep(jsonencode(meta.(key{1})),'\','\u005c')];
    while(numel(line)>100),metadata_lines{end+1}=line(1:100);line=line(101:end);endwhile
    metadata_lines{end+1}=line;
  endfor
  metadata_text=strjoin(metadata_lines,sprintf('\n'));

  prepy={sprintf('def %s(q):',name),'    if np.iscomplexobj(q): raise ValueError("Query must be real")','    q = np.asarray(q, dtype=float)','    if q.ndim > 1: raise ValueError("Query must be a scalar or vector")','    q = q.reshape(-1)',sprintf('    if np.any(~np.isfinite(q)) or np.any(q < %s) or np.any(q > %s): raise ValueError("Query outside evaluated domain")',num(domain(1)),num(domain(2))),sprintf('    u = q + %s',num((!parametric)*du))};
  preoc={sprintf('function points=%s(q)',name),'  if(!isnumeric(q)||!isreal(q)||(!isempty(q)&&!isvector(q))),error("Query must be a real scalar or vector");endif','  q=double(q(:));',sprintf('  if(any(!isfinite(q))||any(q<%s)||any(q>%s)),error("Query outside evaluated domain");endif',num(domain(1)),num(domain(2))),sprintf('  u=q+(%s);',num((!parametric)*du))};
  if(!isempty(rational))
    prepy=[prepy(1:2),{'    raw = np.asarray(q)','    if np.issubdtype(raw.dtype, np.integer) and np.any((raw > 2**53) | (raw < -(2**53))): raise ValueError("Integer query cannot narrow exactly to binary64")'},prepy(3:end)];
    preoc=[preoc(1:2),{'  if(isinteger(q)&&(any(q(:)>cast(flintmax,class(q)))||any(q(:)<cast(-flintmax,class(q))))),error("Integer query cannot narrow exactly to binary64");endif'},preoc(3:end)];
  endif
  if(positive),prepy{end+1}='    if np.any(u <= 0): raise ValueError("Positive predictor required")';preoc{end+1}='  if(any(u<=0)),error("Positive predictor required");endif';endif
  for k=1:numel(py),prepy{end+1}=['    ',py{k}];endfor
  for k=1:numel(oc),preoc{end+1}=['  ',oc{k}];endfor
  prepy=[prepy,{'    points = np.column_stack((x, y))','    if not np.all(np.isfinite(points)): raise ValueError("Model evaluated outside its finite domain")','    return points'}];
  preoc=[preoc,{'  points=[x,y];','  if(!isreal(points)||any(!isfinite(points(:)))),error("Model evaluated outside its finite domain");endif','endfunction'}];
  here=fileparts(mfilename('fullpath'));
  python=['# SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n# Generated by NUMERIC_API_v1 model_export. No fitting or statistics.\n# '),meta_json,sprintf('\nimport numpy as np\n\n'),strjoin(prepy,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'model_export_python.txt'))];
  octave=['% SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n%% Generated by NUMERIC_API_v1 model_export. No fitting or statistics.\n%% '),meta_json,sprintf('\n'),strjoin(preoc,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'model_export_octave.txt'))];
  if(!isempty(implicit))
    python=[python,sprintf('\n\n'),strjoin(implicit_py,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'implicit_model_export_python.txt'))];
    octave=[octave,sprintf('\n\n'),strjoin(implicit_oc,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'implicit_model_export_octave.txt'))];
  endif
  if(!isempty(registered))
    python=[python,sprintf('\n\n'),fileread(fullfile(here,'registered_model_export_python.txt'))];
    octave=[octave,sprintf('\n\n'),fileread(fullfile(here,'registered_model_export_octave.txt'))];
  endif
  latex=['% SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n%% NUMERIC_API_v1 model_export; uses amsmath.\n'), '\[',equation,'\]',sprintf('\n'),'\[',mapping,'\]',sprintf('\n'), '\begin{verbatim}',sprintf('\n'),metadata_text,sprintf('\nFrozen numerical coefficients (17 significant digits):\n')];
  fields=fieldnames(coefficients);
  for k=1:numel(fields)
    key=fields{k};value=coefficients.(key);
    if(isnumeric(value)),text=matrix(value);else text=jsonencode(value);endif
    latex=[latex,key,' = ',text,sprintf('\n')];
  endfor
  latex=[latex,'\end{verbatim}',sprintf('\n')];
  statements=strjoin(py,' ');
  definitions={
    '_voigt(', '\[\operatorname{voigt}(z,\sigma,\gamma)=\frac{\Re[e^{-w^2}\operatorname{erfc}(-iw)]}{\sigma\sqrt{2\pi}},\quad w=\frac{z+i\gamma}{\sigma\sqrt{2}},\quad \sigma>0,\ \gamma\ge0.\]';
    '_shockley(', '\[I=I_s\operatorname{expm1}(u),\quad u+\frac{R_s I_s}{V_t}\operatorname{expm1}(u)=\frac{V}{V_t},\quad I_s,V_t>0,\ R_s\ge0.\]';
    '_logistic(', '\[\operatorname{logistic}(z)=\frac{1}{1+e^{-z}}.\]';
    '_positive(', '\[\operatorname{positive}(z)=\max(z,0).\]';
    '_exprel(', '\[\operatorname{exprel}(z)=\begin{cases}(e^z-1)/z&z\ne0,\\1&z=0.\end{cases}\]'};
  for k=1:rows(definitions)
    if(!isempty(strfind(statements,definitions{k,1}))),latex=[latex,definitions{k,2},sprintf('\n')];endif
  endfor
  if(max([numel(python),numel(octave),numel(latex)])>2*1024*1024),error('GXTXT:Numeric:Export','Independent text artifact exceeds 2 MiB; reduce model size explicitly');endif
  out=struct('python',python,'octave',octave,'latex',latex,'metadata_json',meta_json);
endfunction

function out=surface_export(model,options)
  model=gxtxt_numeric_surface_v1('validate',model);
  allowed={'name','domain','source_reference'};
  if(any(!ismember(fieldnames(options),allowed))),error('GXTXT:Numeric:Export','Surface export retains physical identities; only name, domain and source reference may be supplied');endif
  name=opt(options,'name','fit_surface');
  if(!ischar(name)||isempty(regexp(name,'^fit_[A-Za-z][A-Za-z0-9_]{0,55}$','once'))),error('GXTXT:Numeric:Export','Invalid exported surface function name');endif
  domain=opt(options,'domain',[]);finite(domain);
  if(!isequal(size(domain),[2,2])||any(domain(:,2)<domain(:,1))),error('GXTXT:Numeric:Export','Surface export needs explicit physical2-by-2 coordinate bounds');endif
  if(!isfield(model,'observation_domain')||any(domain(:,1)<model.observation_domain.bounds(:,1))||any(domain(:,2)>model.observation_domain.bounds(:,2))),error('GXTXT:Numeric:Export','Export bounds must lie within the retained surface coordinate bounds');endif
  p=model.parameters(:);[programs,compiled]=gxtxt_numeric_fit_program_v1(model.formula_model,2,numel(p));
  if(numel(programs)!=1||!strcmp(compiled.source_sha256,model.source_sha256)||!strcmp(compiled.binding_sha256,model.binding_sha256)),error('GXTXT:Numeric:Export','Surface expression identity changed');endif
  [py,oc]=assign({}, {}, 'p',p.');[pe,oe,equation]=expression(programs{1},{'u','v'});py=[py,pe];oc=[oc,oe];
  meta=struct('schema','gxtxt.independent_model.v1','model','math.numeric.surface','evaluation_representation','surface','function_name',name,'orientation','z_of_xy',...
    'domain',domain,'domain_meaning','axis_bounds_not_observation_coverage','predictor_ids',{model.predictor_ids},'predictor_units',{model.predictor_units},'response_id','z','response_unit',model.response_unit,...
    'accepted_parameter_ids',{model.parameter_ids},'accepted_parameter_values',p,'parameter_units',{model.parameter_units},'surface_recipe',model.recipe,'declaration_sha256',model.declaration_sha256,...
    'expression_source_sha256',model.source_sha256,'expression_binding_sha256',model.binding_sha256,'fit_geometry',model.fit_geometry,...
    'source_reference',opt(options,'source_reference','NUMERIC_API_v1 saved surface'),'precision','17 significant decimal digits, binary64 evaluation',...
    'query_contract','finite real N-by-2 exact X/Y pairs; N-by-3 X/Y/Z output; outside coordinate bounds refused; no fitting, inference or interpolation',...
    'license','GPL-3.0-or-later','python_dependencies','NumPy; SciPy for erf or Voigt expressions','octave_dependencies','GNU Octave core; no GX-TXT runtime',...
    'comparison_tolerance','abs(error) <= 5e-11 * max(1,abs(reference)); assess ill-conditioned expressions separately');
  meta_json=jsonencode(meta);here=fileparts(mfilename('fullpath'));
  head={sprintf('def %s(q):',name),'    q = np.asarray(q)',...
    '    if np.iscomplexobj(q) or q.ndim != 2 or q.shape[1] != 2 or q.shape[0] < 1 or q.shape[0] > 65536: raise ValueError("Query must be 1..65536 real XY pairs")',...
    '    if q.dtype.kind in "iu" and (np.any(q > 2**53) or np.any(q < -2**53)): raise ValueError("Unsafe integer narrowing")',...
    '    q = q.astype(float)',sprintf('    if np.any(~np.isfinite(q)) or np.any(q < np.array([%s,%s])) or np.any(q > np.array([%s,%s])): raise ValueError("Query outside surface bounds")',num(domain(1,1)),num(domain(2,1)),num(domain(1,2)),num(domain(2,2))),...
    '    u, v = q[:, 0].copy(), q[:, 1].copy()'};
  for line=py,head{end+1}=['    ' line{1}];endfor
  head=[head,{'    y = np.broadcast_to(y, u.shape)','    if np.any(~np.isfinite(y)): raise ValueError("Surface value is unavailable")','    return np.column_stack((q, y))'}];
  python=['# SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n# NUMERIC_API_v1 retained surface export\n# '),meta_json,sprintf('\nimport numpy as np\n\n'),strjoin(head,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'model_export_python.txt'))];
  head={sprintf('function points=%s(q)',name),'  if(!isnumeric(q)||!isreal(q)||ndims(q)>2||columns(q)!=2||rows(q)<1||rows(q)>65536),error("Query must be1..65536 real XY pairs");endif',...
    '  if((isa(q,"uint64")&&any(q(:)>uint64(flintmax)))||(isa(q,"int64")&&any(q(:)>int64(flintmax)|q(:)<-int64(flintmax)))),error("Unsafe integer narrowing");endif','  q=double(q);',...
    sprintf('  if(any(!isfinite(q(:)))||any(any(q<[%s,%s]))||any(any(q>[%s,%s]))),error("Query outside surface bounds");endif',num(domain(1,1)),num(domain(2,1)),num(domain(1,2)),num(domain(2,2))),'  u=q(:,1);v=q(:,2);'};
  for line=oc,head{end+1}=['  ' line{1}];endfor
  head=[head,{'  y=y+zeros(size(u));','  if(any(!isfinite(y))),error("Surface value is unavailable");endif','  points=[q,y];','endfunction'}];
  octave=['% SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n%% NUMERIC_API_v1 retained surface export\n%% '),meta_json,sprintf('\n'),strjoin(head,sprintf('\n')),sprintf('\n\n'),fileread(fullfile(here,'model_export_octave.txt'))];
  latex=['% SPDX-License-Identifier: GPL-3.0-or-later',sprintf('\n'), '\[u=x,\quad v=y\]',sprintf('\n'), '\[',strrep(equation,'f(u)=','z(x,y)='),'\]',sprintf('\n'), '\begin{verbatim}',sprintf('\n'),meta_json,sprintf('\n'), '\end{verbatim}',sprintf('\n')];
  if(max([numel(python),numel(octave),numel(latex)])>2*1024*1024),error('GXTXT:Numeric:Export','Independent surface artifact exceeds2MiB');endif
  out=struct('python',python,'octave',octave,'latex',latex,'metadata_json',meta_json);
endfunction

function value=opt(s,key,fallback)
  value=fallback;if(isfield(s,key)),value=s.(key);endif
endfunction
function finite(x)
  if(!isnumeric(x)||!isreal(x)||any(!isfinite(x(:)))),error('GXTXT:Numeric:Export','Frozen constants must be finite real numbers');endif
endfunction
function text=num(x)
  text=sprintf('%.17g',x);if(x==0&&signbit(x)),text='-0.0';endif
endfunction
function text=matrix(x)
  finite(x);rows_text=cell(1,rows(x));
  for i=1:rows(x),row=cell(1,columns(x));for j=1:columns(x),row{j}=num(x(i,j));endfor;rows_text{i}=strjoin(row,', ');endfor
  text=['[',strjoin(rows_text,'; '),']'];
endfunction
function [py,oc]=assign(py,oc,name,value)
  text=matrix(value);oc{end+1}=[name,'=',text,';'];
  text=strrep(text,'; ','], [');text=['[',text,']'];
  py{end+1}=[name,' = np.array(',text,', dtype=float)'];
endfunction
function v=ternary(test,a,b)
  v=b;if(test),v=a;endif
endfunction

function [py,oc,equation]=expression(code,coordinates)
  if(nargin<2),coordinates={'u'};endif
  py={};oc={};stack={};tex={};
  functions={'exp','log','sqrt','sin','cos','tan','sinh','cosh','tanh','abs','arctan','_erf','log10'};
  octave_functions={'exp','log','sqrt','sin','cos','tan','sinh','cosh','tanh','abs','atan','erf','log10'};
  for k=1:rows(code)
    op=code(k,1);value=code(k,2);name=sprintf('v%d',k);
    if(op==0),p=num(value);o=p;t=p;
    elseif(op==1),p=coordinates{value+1};o=p;t=p;
    elseif(op==2),p=sprintf('p[0, %d]',value);o=sprintf('p(%d)',value+1);t=sprintf('p_{%d}',value);
    else
      count=1;if(any(op==[3:7,29])),count=2;elseif(op==24),count=3;elseif(op==26),count=4;endif
      if(numel(stack)<count),error('GXTXT:Numeric:Export','Invalid compiled expression stack');endif
      a=stack(end-count+1:end);b=tex(end-count+1:end);stack(end-count+1:end)=[];tex(end-count+1:end)=[];
      if(any(op==[3:7,29]))
        operators={'+','-','*','/','**'};ooperators={'+','-','.*','./','.^'};
        if(op==29),p=sprintf('np.minimum(%s,%s)',a{:});o=sprintf('min(%s,%s)',a{:});t=sprintf('\\min(%s,%s)',b{:});
        else
          p=sprintf('(%s %s %s)',a{1},operators{op-2},a{2});o=sprintf('(%s %s %s)',a{1},ooperators{op-2},a{2});
          if(op==6),t=sprintf('\\frac{%s}{%s}',b{:});elseif(op==7),t=sprintf('(%s)^{%s}',b{:});else t=sprintf('(%s %s %s)',b{1},ternary(op==5,'\\cdot',operators{op-2}),b{2});endif
        endif
      elseif(op==8),p=['-',a{1}];o=p;t=['-(',b{1},')'];
      elseif(op==9),p=a{1};o=p;t=b{1};
      elseif(op>=10&&op<=22)
        f=functions{op-9};prefix='np.';if(f(1)=='_'),prefix='';endif
        p=[prefix,f,'(',a{1},')'];o=[octave_functions{op-9},'(',a{1},')'];t=['\operatorname{',octave_functions{op-9},'}(',b{1},')'];
      elseif(op==23),p=sprintf('(%s ** %s)',a{1},num(value));o=sprintf('(%s .^ %s)',a{1},num(value));t=sprintf('(%s)^{%s}',b{1},num(value));
      else
        names={'_voigt','_logistic','_shockley','_positive','_exprel'};f=names{op-23};
        p=[f,'(',strjoin(a,', '),')'];o=[f(2:end),'(',strjoin(a,', '),')'];t=['\operatorname{',f(2:end),'}(',strjoin(b,','),')'];
      endif
    endif
    py{end+1}=[name,' = ',p];oc{end+1}=[name,' = ',o,';'];stack{end+1}=name;tex{end+1}=t;
  endfor
  if(numel(stack)!=1),error('GXTXT:Numeric:Export','Invalid compiled final expression stack');endif
  py{end+1}=['y = ',stack{1}];oc{end+1}=['y = ',stack{1},';'];equation=['f(u)=',tex{1}];
endfunction
