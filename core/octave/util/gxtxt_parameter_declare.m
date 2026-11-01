function gxtxt_parameter_declare(name, type, varargin)
% Public literal declaration v1; discovery happens in CORE before execution.
% Effective invocation values are in gxtxt_context().parameters. No writes.
% SPDX-License-Identifier: GPL-3.0-or-later
  if (nargin < 2 || !ischar(name) || !ischar(type) || mod(numel(varargin),2) != 0)
    error('gxtxt_parameter_declare: expected literal name, type and name/value options');
  endif
endfunction
