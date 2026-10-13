% SPDX-License-Identifier: GPL-3.0-or-later
function v = gxtxt_getenv_default(name,defaultValue)
    raw = getenv(name);
    if (isempty(raw))
        v = defaultValue;
    else
        v = raw;
    endif
endfunction
