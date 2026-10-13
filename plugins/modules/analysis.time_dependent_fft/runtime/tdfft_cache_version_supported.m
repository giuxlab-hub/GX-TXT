function ok=tdfft_cache_version_supported(cache)
% Result schema is unchanged by the numerical-service migration.
% Preserve source/settings validation and the original producer metadata.
% SPDX-License-Identifier: GPL-3.0-or-later
  ok=isfield(cache,'meta') && isfield(cache.meta,'module_version') && ...
    any(strcmp(cache.meta.module_version,{'1.3.0','1.3.1','1.3.2','1.3.3'}));
endfunction
