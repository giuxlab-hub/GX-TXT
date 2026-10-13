% GX-TXT Hypothesis Tests Standard Module API entry point.
% SPDX-License-Identifier: GPL-3.0-or-later
runtime_dir=fileparts(mfilename('fullpath'));
module_dir=fileparts(runtime_dir);
framework_root=fileparts(fileparts(fileparts(module_dir)));
addpath(runtime_dir);
addpath(fullfile(framework_root,'core','octave'));
addpath(fullfile(framework_root,'core','octave','analysis'));
addpath(fullfile(framework_root,'core','octave','io'));
addpath(fullfile(framework_root,'core','octave','util'));
addpath(fullfile(framework_root,'core','octave','units'));
addpath(fullfile(framework_root,'plugins','modules','math.numeric','api','octave'));
analysis_statistics_tests_main(argv(),framework_root);
