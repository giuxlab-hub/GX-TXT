% SPDX-License-Identifier: GPL-3.0-or-later
% GX-TXT Sequential Table Join - Standard Module API entry point.

thisdir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(fileparts(thisdir))));
addpath(fullfile(root,'core','octave','io'));
addpath(fullfile(root,'core','octave','analysis'));
addpath(fullfile(root,'core','octave','util'));
addpath(thisdir);

args = argv();
config_path = '';
for k = 1:numel(args)-1
  if (strcmp(args{k},'--config'))
    config_path = args{k+1};
    break;
  endif
endfor
if (isempty(config_path))
  error('sequence.table_join: --config is required');
endif

try
  sequence_table_join_main(config_path);
catch err
  try
    gxtxt_progress_fail('failed',err.message);
  catch
  end_try_catch
  rethrow(err);
end_try_catch
