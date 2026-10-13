% GX-TXT Standard Module API v1 - Curve Family Fitting launcher
% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
%
% This file is the standard_octave CLI entry point declared by module.ini.
% It only prepares framework/runtime paths and delegates to the scientific main.

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

if (exist('curvefit_family_global_main','file') != 2)
  error('curvefit.family_global: implementation missing: %s', ...
        fullfile(runtime_dir,'curvefit_family_global_main.m'));
endif

curvefit_family_global_main(argv());
