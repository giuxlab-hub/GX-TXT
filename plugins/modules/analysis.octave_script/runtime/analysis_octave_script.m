% GX-TXT Octave Script - Standard Module API entry point.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file = mfilename('fullpath');
runtime_dir = fileparts(this_file);
module_dir = fileparts(runtime_dir);
modules_dir = fileparts(module_dir);
plugins_dir = fileparts(modules_dir);
framework_root = fileparts(plugins_dir);
addpath(runtime_dir);
addpath(fullfile(framework_root, 'core', 'octave'));
addpath(fullfile(framework_root, 'core', 'octave', 'util'));
addpath(fullfile(framework_root, 'core', 'octave', 'io'));
if (exist('analysis_octave_script_main', 'file') != 2)
  error('analysis.octave_script: implementation missing');
endif
analysis_octave_script_main(argv(), framework_root);
