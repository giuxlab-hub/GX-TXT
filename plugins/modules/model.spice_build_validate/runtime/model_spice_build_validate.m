% GX-TXT Standard Module API v1 - SPICE Build and Validation launcher
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it

this_file = mfilename('fullpath');
runtime_dir = fileparts(this_file);
module_dir = fileparts(runtime_dir);
modules_dir = fileparts(module_dir);
plugins_dir = fileparts(modules_dir);
package_root = fileparts(plugins_dir);

addpath(runtime_dir);
addpath(fullfile(package_root,'core','octave'));
addpath(fullfile(package_root,'core','octave','graphics'));
addpath(fullfile(package_root,'core','octave','io'));
addpath(fullfile(package_root,'core','octave','util'));

if (exist('model_spice_build_validate_main','file') != 2)
  error('model.spice_build_validate: implementation missing: %s', ...
        fullfile(runtime_dir,'model_spice_build_validate_main.m'));
endif

model_spice_build_validate_main(argv());
