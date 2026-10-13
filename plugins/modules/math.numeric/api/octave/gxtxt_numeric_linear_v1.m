% Complex linear algebra backend for public NUMERIC_API_v1.
% SPDX-License-Identifier: GPL-3.0-or-later
function out=gxtxt_numeric_linear_v1(action,input,other,opts)
  if(nargin!=4||!ischar(action)||!isstruct(opts)||numel(opts)!=1)
    error('GXTXT:Numeric:InvalidArguments','linear_matrix requires action, A, B, and options');
  endif
  A=read_operand(input,'A');
  if(isempty(other)),B=[];else B=read_operand(other,'B');endif
  action=lower(strtrim(action));
  tol=option_number(opts,'rank_tolerance',[]);
  if(!isempty(tol)&&(!isfinite(tol)||tol<0)),error('GXTXT:Numeric:InvalidTolerance','rank_tolerance must be finite and nonnegative');endif
  s=svd(A);if(isempty(tol)),tol=max(size(A))*eps(max(s));endif
  numerical_rank=sum(s>tol);
  out=struct('rows',rows(A),'cols',columns(A),'rank',numerical_rank,'rank_tolerance',tol,'condition_number',cond(A));
  switch(action)
    case 'inspect'
      out.hermitian=isequal(A,A');out.symmetric=isequal(A,A.');
      out.norm_one=norm(A,1);out.norm_frobenius=norm(A,'fro');out.norm_infinity=norm(A,Inf);
      out.positive_definite=false;
      if(rows(A)==columns(A))
        out=put_complex(out,'trace',trace(A));out=put_complex(out,'determinant',det(A));
        if(out.hermitian),[~,p]=chol(A);out.positive_definite=(p==0);endif
      endif
    case {'transpose','conjugate_transpose','inverse','pseudoinverse','exponential','logarithm','square_root','power','diagonal','diagonal_construct','rectangular_to_polar','polar_to_rectangular'}
      switch(action)
        case 'transpose',V=A.';
        case 'conjugate_transpose',V=A';
        case 'diagonal',V=diag(A);
        case 'diagonal_construct'
          if(!isvector(A)),error('GXTXT:Numeric:DimensionMismatch','diagonal_construct requires a vector');endif
          V=diag(A(:));
        case 'rectangular_to_polar'
          out.magnitude=abs(A);out.phase_rad=angle(A);return;
        case 'polar_to_rectangular'
          if(any(imag(A(:))!=0)||any(real(A(:))<0))
            error('GXTXT:Numeric:InvalidOperand','polar_to_rectangular requires nonnegative real magnitudes');
          endif
          require_other(B,action);
          if(!isequal(size(A),size(B))||any(imag(B(:))!=0))
            error('GXTXT:Numeric:DimensionMismatch','phase must be a real matrix matching magnitude');
          endif
          V=A.*exp(1i*B);
        case 'pseudoinverse',V=pinv(A,tol);
        case 'inverse'
          require_square(A,action);require_full_rank(A,numerical_rank,action);
          require_condition(A,opts);V=A\eye(rows(A));
        case 'exponential'
          require_square(A,action);V=expm(A);
        case 'logarithm'
          require_square(A,action);require_full_rank(A,numerical_rank,action);V=logm(A);
          out.reconstruction_residual=norm(expm(V)-A,'fro')/max(norm(A,'fro'),eps);
        case 'square_root'
          require_square(A,action);V=sqrtm(A);
          out.reconstruction_residual=norm(V*V-A,'fro')/max(norm(A,'fro'),eps);
        case 'power'
          require_square(A,action);p=option_number(opts,'exponent',[]);
          if(isempty(p)||!isfinite(p)||p!=fix(p)),error('GXTXT:Numeric:InvalidExponent','matrix power requires an integer exponent');endif
          if(p<0),require_full_rank(A,numerical_rank,action);require_condition(A,opts);endif
          V=A^p;
      endswitch
      out=put_complex(out,'value',V);
    case 'identity'
      out=put_complex(out,'value',eye(rows(A),columns(A)));
    case 'multiply'
      require_other(B,action);if(columns(A)!=rows(B)),error('GXTXT:Numeric:DimensionMismatch','matrix multiplication inner dimensions differ');endif
      out=put_complex(out,'value',A*B);
    case 'solve'
      require_other(B,action);if(rows(A)!=rows(B)),error('GXTXT:Numeric:DimensionMismatch','B row count must match A');endif
      policy=option_text(opts,'rank_policy','error');
      if(!any(strcmp(policy,{'error','minimum_norm'}))),error('GXTXT:Numeric:InvalidPolicy','rank_policy must be error or minimum_norm');endif
      if(strcmp(policy,'error'))
        if(numerical_rank<min(size(A))),error('GXTXT:Numeric:RankDeficient','A is rank deficient; request minimum_norm explicitly');endif
        require_condition(A,opts);X=A\B;
      else X=pinv(A,tol)*B;endif
      R=A*X-B;
      out=put_complex(out,'value',X);out=put_complex(out,'residual',R);
      out.residual_norm=norm(R,'fro');out.relative_residual=out.residual_norm/max(norm(B,'fro'),eps);
      out.solution_kind=policy;out.rhs_columns=columns(B);
    case 'lu'
      require_square(A,action);[L,U,P]=lu(A);
      out=put_complex(out,'l',L);out=put_complex(out,'u',U);out=put_complex(out,'p',P);
    case 'schur'
      require_square(A,action);[U,T]=schur(A,'complex');
      out=put_complex(out,'q',U);out=put_complex(out,'t',T);
      out.reconstruction_residual=norm(U*T*U'-A,'fro')/max(norm(A,'fro'),eps);
    case 'qr'
      [Q,R,P]=qr(A);
      out=put_complex(out,'q',Q);out=put_complex(out,'r',R);out=put_complex(out,'p',P);
    case 'cholesky'
      require_square(A,action);
      if(!isequal(A,A')),error('GXTXT:Numeric:NotHermitian','Cholesky requires a Hermitian matrix');endif
      [R,p]=chol(A);if(p!=0),error('GXTXT:Numeric:NotPositiveDefinite','Cholesky requires a positive definite matrix');endif
      out=put_complex(out,'r',R);
    case 'svd'
      [U,S,V]=svd(A,'econ');
      out=put_complex(out,'u',U);out=put_complex(out,'s',S);out=put_complex(out,'v',V);
    case {'eigen','hermitian_eigen','generalized_eigen'}
      require_square(A,action);
      if(strcmp(action,'hermitian_eigen')&&!isequal(A,A'))
        error('GXTXT:Numeric:NotHermitian','Hermitian eigenproblem requires A=A conjugate transpose');
      endif
      if(strcmp(action,'generalized_eigen'))
        require_other(B,action);if(!isequal(size(A),size(B))),error('GXTXT:Numeric:DimensionMismatch','generalized eigenproblem requires equal square shapes');endif
        if(rank(B)<rows(B)),error('GXTXT:Numeric:RankDeficient','generalized eigenproblem requires nonsingular B');endif
        [V,D]=eig(A,B);
      else [V,D]=eig(A);endif
      out=put_complex(out,'eigenvectors',V);out=put_complex(out,'eigenvalues',diag(D));
    otherwise
      error('GXTXT:Numeric:UnknownOperation','unknown linear_matrix action: %s',action);
  endswitch
endfunction

function A=read_operand(input,name)
  if(isstruct(input))
    if(!isfield(input,'real')||!isfield(input,'imaginary'))
      error('GXTXT:Numeric:InvalidOperand','%s requires real and imaginary fields',name);
    endif
    R=input.real;I=input.imaginary;
    if(!isequal(size(R),size(I))),error('GXTXT:Numeric:DimensionMismatch','%s real and imaginary shapes differ',name);endif
    A=complex(R,I);
  else A=input;endif
  if(!isnumeric(A)||ndims(A)!=2||isempty(A)||any(!isfinite(real(A(:))))||any(!isfinite(imag(A(:)))))
    error('GXTXT:Numeric:InvalidOperand','%s must be a nonempty finite real or complex matrix',name);
  endif
  A=double(A);
endfunction
function out=put_complex(out,name,value)
  if(any(!isfinite(real(value(:))))||any(!isfinite(imag(value(:)))))
    error('GXTXT:Numeric:NonFiniteResult','%s produced NaN or Inf',name);
  endif
  out.([name '_real'])=real(value);out.([name '_imaginary'])=imag(value);
endfunction
function require_square(A,action)
  if(rows(A)!=columns(A)),error('GXTXT:Numeric:DimensionMismatch','%s requires a square matrix',action);endif
endfunction
function require_full_rank(A,r,action)
  if(r<min(size(A))),error('GXTXT:Numeric:RankDeficient','%s requires full rank',action);endif
endfunction
function require_other(B,action)
  if(isempty(B)),error('GXTXT:Numeric:InvalidArguments','%s requires B',action);endif
endfunction
function require_condition(A,opts)
  limit=option_number(opts,'condition_limit',1e12);
  if(!isfinite(limit)||limit<1),error('GXTXT:Numeric:InvalidTolerance','condition_limit must be finite and >= 1');endif
  if(cond(A)>limit),error('GXTXT:Numeric:IllConditioned','A exceeds condition_limit; use minimum_norm or an explicit larger limit');endif
endfunction
function value=option_number(opts,name,default)
  value=default;if(isfield(opts,name)),value=opts.(name);if(ischar(value)),value=str2double(value);endif;endif
  if(!isempty(value)&&(!isnumeric(value)||!isscalar(value)||!isreal(value)))
    error('GXTXT:Numeric:InvalidArguments','%s must be a real scalar',name);
  endif
endfunction
function value=option_text(opts,name,default)
  value=default;if(isfield(opts,name)),value=opts.(name);endif
  if(!ischar(value)),error('GXTXT:Numeric:InvalidArguments','%s must be text',name);endif
  value=lower(strtrim(value));
endfunction
