% GX-TXT CORE registered Octave script entry point.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file = mfilename('fullpath');
octave_dir = fileparts(this_file);
core_dir = fileparts(octave_dir);
framework_root = fileparts(core_dir);
addpath(octave_dir);
addpath(fullfile(octave_dir, 'util'));
addpath(fullfile(octave_dir, 'io'));
analysis_octave_script_main(argv(), framework_root);
