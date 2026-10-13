% SPDX-License-Identifier: GPL-3.0-or-later
% Exact left join of source_value onto left_key using right_key.
% Keys may be numeric/logical or strings (cellstr/char). Duplicate right keys
% are reported as ambiguous_match; unmatched left keys remain unavailable.
function R = gxtxt_analysis_op_join(left_key,right_key,source_value)
  lk=columnize(left_key);rk=columnize(right_key);sv=columnize(source_value);
  if(numel(rk)!=numel(sv)),error('GXTXT:AnalysisJoin','right_key/source_value length mismatch');endif
  if(!same_key_class(lk,rk)),error('GXTXT:AnalysisJoin','left_key/right_key types are incompatible');endif
  n=numel(lk);v=empty_values_like(sv,n);st=repmat({'unavailable'},n,1);rs=repmat({'unmatched'},n,1);srcidx=NaN(n,1);
  for i=1:n
    hit=key_hits(rk,lk,i);
    if(numel(hit)==1)
      if(iscell(sv)),v{i}=sv{hit};else v(i)=sv(hit);endif
      st{i}='valid';rs{i}='';srcidx(i)=hit;
    elseif(numel(hit)>1)
      rs{i}='ambiguous_match';
    endif
  endfor
  R=struct('values',{v},'status',{st},'reason',{rs},'source_indices',srcidx,'method','exact');
endfunction
function v=columnize(v)
  if(ischar(v)&&size(v,1)>1),v=cellstr(v);elseif(ischar(v)),v={v};elseif(iscell(v)),v=v(:);else v=v(:);endif
endfunction
function tf=same_key_class(a,b)
  tf=(iscell(a)&&iscell(b))||((isnumeric(a)||islogical(a))&&(isnumeric(b)||islogical(b)));
endfunction
function h=key_hits(keys,q,i)
  if(iscell(keys)),h=find(strcmp(keys,q{i}));else
    x=q(i);if(!isfinite(x)),h=[];else h=find(keys==x);endif
  endif
endfunction
function v=empty_values_like(src,n)
  if(iscell(src)),v=repmat({''},n,1);elseif(islogical(src)),v=false(n,1);else v=NaN(n,1);endif
endfunction
