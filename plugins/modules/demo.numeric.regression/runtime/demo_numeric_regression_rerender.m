% GX-TXT Numerical Regression Demo - cache-only rerender entry point.
% SPDX-License-Identifier: GPL-3.0-or-later
this_file=mfilename('fullpath');runtime_dir=fileparts(this_file);module_dir=fileparts(runtime_dir);modules_dir=fileparts(module_dir);plugins_dir=fileparts(modules_dir);framework_root=fileparts(plugins_dir);
addpath(runtime_dir);addpath(fullfile(framework_root,'core','octave'));addpath(fullfile(framework_root,'core','octave','graphics'));addpath(fullfile(framework_root,'core','octave','io'));addpath(fullfile(framework_root,'core','octave','util'));
demo_numeric_regression_rerender_main(argv());
