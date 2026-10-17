function gxtxt_registered_callable_v1(function_handle, cfg)
% Invoke one public consumer inside the existing supervised callback lifetime.
% SPDX-License-Identifier: GPL-3.0-or-later
  payload = jsondecode(gxtxt_ini_get(cfg, 'registered_callable.payload_json', ''));
  handle = gxtxt_callback_register(function_handle);
  unwind_protect
    result = gxtxt_api_call(gxtxt_ini_get(cfg, 'registered_callable.consumer_api', ''), ...
      gxtxt_ini_get(cfg, 'registered_callable.consumer_operation', ''), {handle, payload});
    receipt = struct('format', 'gxtxt.registered_callable_result.v1');
    keys = {'callable_id','contract','source_sha256','revision','declaration_sha256','consumer_api','consumer_operation'};
    for k = 1:numel(keys)
      receipt.(keys{k}) = gxtxt_ini_get(cfg, ['registered_callable.' keys{k}], '');
    endfor
    bounded_receipt(result, 0, 4096);
    receipt.result = result;
    encoded = jsonencode(receipt);
    if (numel(unicode2native(encoded, 'UTF-8')) > 1048576)
      error('GXTXT:ScriptCallback:ReceiptLimit', 'Callable result control receipt exceeds 1 MiB');
    endif
    destination = fullfile(gxtxt_ini_get(cfg, 'runtime.output_dir', ''), 'registered_callable_result.json');
    if (exist(destination, 'file')), error('GXTXT:ScriptCallback:ReceiptExists', 'Callable result receipt already exists'); endif
    [fd, message] = fopen(destination, 'wb');
    if (fd < 0), error('GXTXT:ScriptCallback:ReceiptWrite', '%s', message); endif
    unwind_protect
      fwrite(fd, unicode2native([encoded sprintf('\n')], 'UTF-8'), 'uint8');
    unwind_protect_cleanup
      fclose(fd);
    end_unwind_protect
  unwind_protect_cleanup
    gxtxt_callback_release(handle);
  end_unwind_protect
endfunction

function budget = bounded_receipt(value, depth, budget)
  budget -= 1;
  if (depth > 16 || budget < 0)
    error('GXTXT:ScriptCallback:ReceiptLimit', 'Callable result must be bounded control data; retain scientific arrays with their resource owner');
  endif
  if (isstruct(value))
    if (!isscalar(value)), error('GXTXT:ScriptCallback:ReceiptLimit', 'Receipt structs must be scalar'); endif
    names = fieldnames(value);
    for k = 1:numel(names), budget = bounded_receipt(value.(names{k}), depth+1, budget); endfor
  elseif (iscell(value))
    for k = 1:numel(value), budget = bounded_receipt(value{k}, depth+1, budget); endfor
  elseif (isnumeric(value) || islogical(value))
    if (numel(value) > 64 || !isreal(value) || any(!isfinite(value(:))))
      error('GXTXT:ScriptCallback:ReceiptLimit', 'Receipt arrays must contain at most 64 finite real control values');
    endif
  elseif (!ischar(value))
    error('GXTXT:ScriptCallback:ReceiptType', 'Callable result is not inert control data');
  endif
endfunction
