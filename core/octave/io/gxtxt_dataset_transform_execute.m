% Public CORE Dataset Transform transport for standard Octave modules.
% SPDX-License-Identifier: GPL-3.0-or-later
function result = gxtxt_dataset_transform_execute(config_path, manifest)
  root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
  request_path = [tempname() '.json'];
  result_path = [tempname() '.json'];
  unwind_protect
    fid = fopen(request_path,'w');
    if (fid < 0), error('Cannot create Dataset Transform request'); endif
    unwind_protect
      fprintf(fid,'%s',jsonencode(manifest));
    unwind_protect_cleanup
      fclose(fid);
    end_unwind_protect
    command = ['python3 -B ' quote_local(fullfile(root,'core','python','dataset_transform_cli_v1.py')) ...
               ' --runtime ' quote_local(config_path) ' --request ' quote_local(request_path) ...
               ' --result ' quote_local(result_path) ' 2>&1'];
    [status, message] = system(command);
    if (status != 0), error('Dataset Transform: %s',strtrim(message)); endif
    result = jsondecode(fileread(result_path));
  unwind_protect_cleanup
    if (exist(request_path,'file') == 2), unlink(request_path); endif
    if (exist(result_path,'file') == 2), unlink(result_path); endif
  end_unwind_protect
endfunction

function text = quote_local(value)
  % POSIX single-argument quoting also protects paths containing apostrophes.
  text = ["'" strrep(value,"'","'\"'\"'") "'"];
endfunction
