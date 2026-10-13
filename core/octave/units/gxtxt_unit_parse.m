% SPDX-License-Identifier: GPL-3.0-or-later
% Minimal SI-prefix/unit parser for GX-TXT Unit/Dimension API v1.
% v0.9.7.1 also recognizes identity-preserved semantic level units
% dB, dBFS and FS; v0.9.7.3 adds ppm and pH as identity-only metadata.
% Returns scale to canonical symbolic SI dimensions and a dimension key.
function U = gxtxt_unit_parse(unit)
  unit=strtrim(unit);
  unit=strrep(unit,'µ','u');unit=strrep(unit,'Ω','Ohm');unit=strrep(unit,'·','*');
  R=gxtxt_unit_registry_lookup(unit);
  if(!isempty(fieldnames(R)) && !isempty(R.canonical_unit))
    U=struct('unit',unit,'scale',1,'dims',struct(),'dimensionless',false,'kind','registered','semantic',unit);return;
  endif
  sem=semantic_unit_key(unit);
  if(!isempty(sem))
    U=struct('unit',unit,'scale',1,'dims',struct(),'dimensionless',false,'kind','semantic','semantic',sem);return;
  endif
  if(isempty(unit)||any(strcmp(unit,{'1','dimensionless'})))
    U=struct('unit',unit,'scale',1,'dims',struct(),'dimensionless',true,'kind','linear','semantic','');return;
  endif
  parts=regexp(unit,'([*/])','split');ops=regexp(unit,'([*/])','tokens');
  dims=struct();scale=1;sign=1;
  for i=1:numel(parts)
    tok=strtrim(parts{i});if(isempty(tok)),error('GXTXT:Unit','invalid unit expression: %s',unit);endif
    if(i>1),op=ops{i-1}{1};if(strcmp(op,'/')),sign=-1;else sign=1;endif;else sign=1;endif
    m=regexp(tok,'^([A-Za-z]+)(?:\^([+-]?[0-9]+))?$','tokens','once');if(isempty(m)),error('GXTXT:Unit','unsupported unit token: %s',tok);endif
    sym=m{1};pw=1;if(numel(m)>1&&!isempty(m{2})),pw=str2double(m{2});endif;pw*=sign;
    try [sc,base,bd]=single_unit(sym);
    catch
      U=struct('unit',unit,'scale',1,'dims',struct(),'dimensionless',false,'kind','opaque','semantic',unit);return;
    end_try_catch
    scale*=sc^pw;dims=merge_dims(dims,bd,pw);
  endfor
  U=struct('unit',unit,'scale',scale,'dims',dims,'dimensionless',isempty(fieldnames(dims)),'kind','linear','semantic','');
endfunction
function sem=semantic_unit_key(u)
  if(any(strcmp(u,{'dB','dBFS','FS','ppm','pH'}))),sem=u;else sem='';endif
endfunction
function [sc,base,d]=single_unit(sym)
  % Time aliases are real units (not SI prefixes) and canonicalize to seconds.
  if(strcmp(sym,'min')),sc=60;base='s';d=base_dims('s');return;endif
  if(strcmp(sym,'h')),sc=3600;base='s';d=base_dims('s');return;endif
  if(strcmp(sym,'day')),sc=86400;base='s';d=base_dims('s');return;endif
  % Exact base symbols first, so m means metre while mA means milliampere.
  bases={'A','V','s','Hz','Ohm','W','J','K','mol','m','g'};
  if(any(strcmp(sym,bases))),prefix='';base=sym;else
    prefixes={'da','G','M','k','h','d','c','m','u','n','p'};prefix='';base='';
    for i=1:numel(prefixes),pr=prefixes{i};if(length(sym)>length(pr)&&strcmp(sym(1:length(pr)),pr)&&any(strcmp(sym(length(pr)+1:end),bases))),prefix=pr;base=sym(length(pr)+1:end);break;endif;endfor
    if(isempty(base)),error('GXTXT:Unit','unknown unit: %s',sym);endif
  endif
  sc=prefix_scale(prefix);d=base_dims(base);
endfunction
function s=prefix_scale(p)
  switch p,case '',s=1;case 'da',s=1e1;case 'G',s=1e9;case 'M',s=1e6;case 'k',s=1e3;case 'h',s=1e2;case 'd',s=1e-1;case 'c',s=1e-2;case 'm',s=1e-3;case 'u',s=1e-6;case 'n',s=1e-9;case 'p',s=1e-12;otherwise,error('GXTXT:Unit','unknown SI prefix');endswitch
endfunction
function d=base_dims(b)
  d=struct();switch b
    case 'A',d.A=1;case 'V',d.V=1;case 's',d.s=1;case 'Hz',d.s=-1;case 'Ohm',d.V=1;d.A=-1;case 'W',d.V=1;d.A=1;case 'J',d.V=1;d.A=1;d.s=1;case 'K',d.K=1;case 'mol',d.mol=1;case 'm',d.m=1;case 'g',d.g=1;
  endswitch
endfunction
function d=merge_dims(d,a,mul)
  f=fieldnames(a);for i=1:numel(f),k=f{i};if(!isfield(d,k)),d.(k)=0;endif;d.(k)+=a.(k)*mul;if(d.(k)==0),d=rmfield(d,k);endif;endfor
endfunction
