function result = triode_koren_v1_spice(operation,request)
% SPICE Adapter API v1 for mathematical model triode.koren_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% The adapter reproduces only the static plate-current law implemented by
% triode_koren_v1.m. It intentionally adds no grid current, capacitances,
% heater, thermal model, secondary emission, or other dynamic effects.

  if(nargin<1), error('triode.koren_v1 SPICE adapter: operation required'); endif
  if(nargin<2), request=struct(); endif
  operation=lower(strtrim(operation));
  switch operation
    case 'describe'
      result=describe_adapter();
    case 'export'
      result=export_model(request);
    case 'sample_points'
      result=sample_points(request);
    case 'testbench'
      result=build_testbench(request);
    otherwise
      error('triode.koren_v1 SPICE adapter: unsupported operation: %s',operation);
  endswitch
endfunction

function d=describe_adapter()
  d=struct();
  d.api_version=1;
  d.adapter_id='triode.koren_v1.spice';
  d.adapter_version='1';
  d.terminal_names={'plate','grid','cathode'};
  d.model_input_roles={'x','family'};
  d.model_input_quantities={'V(plate,cathode)','V(grid,cathode)'};
  d.output_quantity='I(plate->cathode)';
  d.model_output_unit='mA';
  d.spice_output_unit='A';
  d.spice_to_model_scale=1000.0;
  d.supported_profiles={'x_sweep','family_sweep'};
  d.supports_arbitrary_points=true;
  d.simulator_constraints='ngspice behavioral B source with max, abs, exp, ln, sqrt and pow';
endfunction

function r=export_model(q)
  require_fields(q,{'output_path','device_name','theta','param_names','gx_version','module_id','module_version','model_id','model_version','timestamp','parameter_source'});
  expected={'mu','Kp','Kvb','Kg1','Ex'};
  names=q.param_names;
  if(!iscell(names)||numel(names)!=numel(expected)||!all(strcmp(names,expected)))
    error('triode.koren_v1 SPICE adapter: parameter order must be mu;Kp;Kvb;Kg1;Ex');
  endif
  theta=q.theta(:).';
  if(numel(theta)!=5||any(!isfinite(theta))), error('triode.koren_v1 SPICE adapter: invalid parameter vector'); endif
  if(theta(2)<=0||theta(4)<=0||theta(5)<=0), error('triode.koren_v1 SPICE adapter: Kp, Kg1 and Ex must be positive'); endif
  device=sanitize_subckt_name(q.device_name);
  fid=fopen(q.output_path,'w'); if(fid<0), error('Cannot write SPICE model: %s',q.output_path); endif
  unwind_protect
    fprintf(fid,'* GX-TXT generated SPICE model\n');
    fprintf(fid,'* SPDX-License-Identifier: GPL-3.0-or-later\n');
    fprintf(fid,'* Generated: %s\n',q.timestamp);
    fprintf(fid,'* GX-TXT version: %s\n',q.gx_version);
    fprintf(fid,'* Generator: %s v%s\n',q.module_id,q.module_version);
    fprintf(fid,'* Mathematical model: %s v%s\n',q.model_id,q.model_version);
    fprintf(fid,'* SPICE adapter: triode.koren_v1.spice v1 / API 1\n');
    [~,ps_name,ps_ext]=fileparts(q.parameter_source);
    fprintf(fid,'* Parameter source: %s%s\n',ps_name,ps_ext);
    for i=1:numel(expected), fprintf(fid,'* %s = %.17g\n',expected{i},theta(i)); endfor
    fprintf(fid,'* Static law only: no grid current, capacitances, heater or thermal/dynamic effects.\n');
    fprintf(fid,'.SUBCKT %s plate grid cathode\n',device);
    fprintf(fid,'.param mu=%.17g Kp=%.17g Kvb=%.17g Kg1=%.17g Ex=%.17g\n',theta(1),theta(2),theta(3),theta(4),theta(5));
    fprintf(fid,['BPLATE plate cathode I={2*pow(max((V(plate,cathode)/Kp)*(max(Kp*(1/mu+V(grid,cathode)/sqrt(max(Kvb+V(plate,cathode)*V(plate,cathode),2.220446049250313e-16))),0)' ...
                 '+ln(1+exp(-abs(Kp*(1/mu+V(grid,cathode)/sqrt(max(Kvb+V(plate,cathode)*V(plate,cathode),2.220446049250313e-16))))))),0),Ex)/Kg1}\n']);
    fprintf(fid,'.ENDS %s\n',device);
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  r=struct('output_path',q.output_path,'device_name',device,'adapter_id','triode.koren_v1.spice','adapter_version','1');
endfunction

function r=sample_points(q)
  require_fields(q,{'profile','bounds','points_per_curve','group_count'});
  b=q.bounds;
  if(!isnumeric(b)||!isequal(size(b),[2 2])||any(!isfinite(b(:)))||b(1,2)<=b(1,1)||b(2,2)<=b(2,1))
    error('triode.koren_v1 SPICE adapter: invalid two-input bounds');
  endif
  np=max(2,round(q.points_per_curve)); ng=max(1,round(q.group_count));
  profile=lower(strtrim(q.profile)); points=[];
  if(strcmp(profile,'x_sweep'))
    xs=linspace(b(1,1),b(1,2),np); groups=linspace(b(2,1),b(2,2),ng);
    for i=1:numel(groups), points=[points; xs(:) repmat(groups(i),numel(xs),1)]; endfor
  elseif(strcmp(profile,'family_sweep'))
    fs=linspace(b(2,1),b(2,2),np); groups=linspace(b(1,1),b(1,2),ng);
    for i=1:numel(groups), points=[points; repmat(groups(i),numel(fs),1) fs(:)]; endfor
  else
    error('triode.koren_v1 SPICE adapter: unsupported generated profile: %s',profile);
  endif
  r=struct('profile',profile,'points',points);
endfunction

function r=build_testbench(q)
  require_fields(q,{'profile','points','output_path','result_file','model_file','device_name'});
  p=q.points;
  if(!isnumeric(p)||columns(p)!=2||rows(p)<1||any(!isfinite(p(:)))), error('triode.koren_v1 SPICE adapter: invalid testbench points'); endif
  device=sanitize_subckt_name(q.device_name);
  if(!is_safe_relative_name(q.model_file)||!is_safe_relative_name(q.result_file))
    error('triode.koren_v1 SPICE adapter: model/result filenames must be simple relative filenames');
  endif
  fid=fopen(q.output_path,'w'); if(fid<0), error('Cannot write SPICE testbench: %s',q.output_path); endif
  unwind_protect
    fprintf(fid,'* GX-TXT SPICE Adapter API v1 testbench\n');
    fprintf(fid,'* profile=%s points=%d\n',q.profile,rows(p));
    fprintf(fid,'.include "%s"\n',q.model_file);
    vecs=cell(rows(p),1);
    for i=1:rows(p)
      tag=sprintf('%05d',i); nsrc=['nsource_' tag]; nplate=['nplate_' tag]; ngrid=['ngrid_' tag];
      fprintf(fid,'VAX%s %s 0 %.17g\n',tag,nsrc,p(i,1));
      fprintf(fid,'VMEAS%s %s %s 0\n',tag,nsrc,nplate);
      fprintf(fid,'VFAM%s %s 0 %.17g\n',tag,ngrid,p(i,2));
      fprintf(fid,'XPT%s %s %s 0 %s\n',tag,nplate,ngrid,device);
      vecs{i}=sprintf('i(vmeas%s)',lower(tag));
    endfor
    fprintf(fid,'.control\n');
    fprintf(fid,'set wr_singlescale\n');
    fprintf(fid,'set wr_vecnames\n');
    fprintf(fid,'option numdgt=16\n');
    fprintf(fid,'op\n');
    fprintf(fid,'wrdata %s',q.result_file);
    for i=1:numel(vecs), fprintf(fid,' %s',vecs{i}); endfor
    fprintf(fid,'\nquit\n.endc\n.end\n');
  unwind_protect_cleanup
    fclose(fid);
  end_unwind_protect
  r=struct('output_path',q.output_path,'result_file',q.result_file,'result_vector_count',rows(p),'spice_to_model_scale',1000.0);
endfunction

function s=sanitize_subckt_name(s)
  s=strtrim(s); s=regexprep(s,'[^A-Za-z0-9_.$-]','_');
  if(isempty(s)), s='GXTXT_MODEL'; endif
endfunction

function tf=is_safe_relative_name(s)
  tf=ischar(s)&&!isempty(s)&&isempty(strfind(s,'/'))&&isempty(strfind(s,'\\'))&&isempty(strfind(s,'..'));
endfunction

function require_fields(s,names)
  for i=1:numel(names), if(!isfield(s,names{i})), error('triode.koren_v1 SPICE adapter: request missing field %s',names{i}); endif; endfor
endfunction
