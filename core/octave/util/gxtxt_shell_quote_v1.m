function quoted=gxtxt_shell_quote_v1(value)
% Quote one argument for the local Octave system() shell on Linux or Windows.
% SPDX-License-Identifier: GPL-3.0-or-later
  if(!ischar(value)||rows(value)!=1||any(value==sprintf('\n'))||any(value==sprintf('\r')))
    error('GXTXT:ShellQuote','shell argument must be one text line');
  endif
  if(ispc())
    % cmd.exe expands percent variables, and delayed expansion may expand !.
    % Reject these spellings until a shell-free child-process API is available.
    if(any(value=='"')||any(value=='%')||any(value=='!'))
      error('GXTXT:ShellQuote','Windows shell argument contains an unsupported CMD expansion or quote character');
    endif
    quoted=['"' value '"'];
  else
    quoted=['''' strrep(value,'''','''"''"''') ''''];
  endif
endfunction
