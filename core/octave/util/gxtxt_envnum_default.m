% SPDX-License-Identifier: GPL-3.0-or-later
function v = gxtxt_envnum_default(name,defaultValue)
    raw = getenv(name);
    if (isempty(raw))
        v = defaultValue;
        return;
    endif
    x = str2double(raw);
    if (isfinite(x))
        v = x;
    elseif (strcmpi(strtrim(raw),'nan'))
        v = NaN;
    else
        v = defaultValue;
    endif
endfunction
